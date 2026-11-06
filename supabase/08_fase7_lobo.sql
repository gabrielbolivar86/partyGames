-- =====================================================================
-- Party Games App · Fase 7: Hombre Lobo (etapa 1: motor + Lobo, Aldeano, Vidente, Bruja, Cazador, Alcalde)
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1 a 6.
--
-- Seguridad: los ROLES nunca están en una tabla pública. wolf_state (pública) solo tiene la fase y un
-- número de versión; cuando cambia, cada celular vuelve a pedir SU vista (wolf_my_view), que el
-- servidor arma según quién pregunta.
-- =====================================================================

-- =====================================================================
-- TABLAS
-- =====================================================================
create table if not exists public.wolf_state (
  event_id     uuid primary key references public.events(id) on delete cascade,
  game_id      uuid,
  status       text not null default 'none' check (status in ('none', 'lobby', 'setup', 'playing', 'finished')),
  phase        text,            -- dealt | night | night_witch | dawn | mayor | debate | vote | verdict | duty | finished
  seq          integer not null default 0,   -- sube en cada cambio de fase (clave de las acciones)
  night_seq    integer,                      -- seq de la fase 'night' actual (para resolver con la bruja)
  night_no     integer not null default 0,
  day_no       integer not null default 0,
  ends_at      timestamptz,
  narrator_id  uuid references public.players(id) on delete set null,
  config       jsonb not null default '{"night":60,"witch":30,"debate":240,"vote":60,"duty":30,"mayor":true,"public_deck":true}',
  deck         jsonb,          -- baraja pública {rol: cantidad} (si el narrador la deja pública)
  winner       text,
  after_duty   text,
  last_result  jsonb,          -- lo último que se anunció (muertes, votación)
  pts_win      integer not null default 8,
  pts_survive  integer not null default 2,
  version      integer not null default 0,
  updated_at   timestamptz not null default now()
);

create table if not exists public.wolf_seats (
  event_id     uuid not null references public.events(id) on delete cascade,
  game_id      uuid not null,
  player_id    uuid not null references public.players(id) on delete cascade,
  seat         integer,
  role         text,            -- lobo | aldeano | vidente | bruja | cazador
  alive        boolean not null default true,
  card_seen    boolean not null default false,
  heal_left    boolean not null default true,
  kill_left    boolean not null default true,
  is_mayor     boolean not null default false,
  duty_hunter  boolean not null default false,
  duty_mayor   boolean not null default false,
  death_text   text,
  joined_at    timestamptz not null default now(),
  primary key (game_id, player_id)
);

create table if not exists public.wolf_actions (
  event_id   uuid not null references public.events(id) on delete cascade,
  game_id    uuid not null,
  seq        integer not null,
  kind       text not null,    -- wolf | seer | suspect | heal | poison | mayor | vote | shoot | successor
  actor_id   uuid not null references public.players(id) on delete cascade,
  target_id  uuid references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (game_id, seq, kind, actor_id)
);

insert into public.wolf_state (event_id) select id from public.events on conflict do nothing;

alter table public.wolf_state   enable row level security;
alter table public.wolf_seats   enable row level security;
alter table public.wolf_actions enable row level security;
drop policy if exists "lobo: lectura pública" on public.wolf_state;
create policy "lobo: lectura pública" on public.wolf_state for select to anon, authenticated using (true);
grant select on public.wolf_state to anon, authenticated;
-- wolf_seats y wolf_actions: sin políticas → solo vía funciones

-- =====================================================================
-- AUXILIARES
-- =====================================================================
create or replace function public.ensure_event_rows()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if v_event is null then raise exception 'No hay una fiesta activa'; end if;
  insert into costume_contest (event_id) values (v_event) on conflict do nothing;
  insert into dashboard_state (event_id) values (v_event) on conflict do nothing;
  insert into code_hunt (event_id) values (v_event) on conflict do nothing;
  insert into persona_game (event_id) values (v_event) on conflict do nothing;
  insert into impostor_game (event_id) values (v_event) on conflict do nothing;
  insert into gift_game (event_id) values (v_event) on conflict do nothing;
  insert into wolf_state (event_id) values (v_event) on conflict do nothing;
  return v_event;
end $$;

create or replace function public.wolf_bump()
returns void language sql security definer set search_path = public as $$
  update wolf_state set version = version + 1, updated_at = now() where event_id = active_event_id()
$$;

create or replace function public.wolf_is_narrator()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from wolf_state where event_id = active_event_id()
                 and narrator_id is not null and narrator_id = current_player_id())
$$;

create or replace function public.wolf_role_name(p_role text)
returns text language sql immutable as $$
  select case p_role when 'lobo' then 'Lobo' when 'aldeano' then 'Aldeano' when 'vidente' then 'Vidente'
                     when 'bruja' then 'Bruja' when 'cazador' then 'Cazador' else coalesce(p_role, '?') end
$$;

-- Víctima elegida por la manada (mayoría de lobos vivos; empate = desempate estable)
create or replace function public.wolf_victim(p_game uuid, p_seq integer)
returns uuid language sql stable security definer set search_path = public as $$
  select a.target_id
  from wolf_actions a
  join wolf_seats s on s.game_id = a.game_id and s.player_id = a.actor_id and s.alive and s.role = 'lobo'
  join wolf_seats t on t.game_id = a.game_id and t.player_id = a.target_id and t.alive
  where a.game_id = p_game and a.seq = p_seq and a.kind = 'wolf'
  group by a.target_id
  order by count(*) desc, md5(a.target_id::text || p_seq::text)
  limit 1
$$;

-- Matar a alguien: anota deberes (cazador dispara, alcalde elige sucesor)
create or replace function public.wolf_kill(p_game uuid, p_player uuid, p_text text)
returns void language sql security definer set search_path = public as $$
  update wolf_seats
  set alive = false, death_text = p_text,
      duty_hunter = (role = 'cazador'),
      duty_mayor = is_mayor
  where game_id = p_game and player_id = p_player and alive
$$;

-- ¿Ganó alguien? devuelve 'village' | 'wolves' | null
create or replace function public.wolf_check_win(p_game uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when count(*) filter (where alive and role = 'lobo') = 0 then 'village'
    when count(*) filter (where alive and role = 'lobo') >= count(*) filter (where alive and role <> 'lobo') then 'wolves'
  end
  from wolf_seats where game_id = p_game
$$;

create or replace function public.wolf_finish(p_winner text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_s     wolf_state%rowtype;
begin
  select * into v_s from wolf_state where event_id = v_event;
  if v_s.status = 'finished' then return; end if;
  insert into points_ledger (event_id, player_id, source, points, reason)
  select v_event, w.player_id, 'lobo',
         v_s.pts_win + case when w.alive then v_s.pts_survive else 0 end,
         case when p_winner = 'wolves' then 'Hombre Lobo: ganaron los lobos' else 'Hombre Lobo: ganó la aldea' end
         || case when w.alive then ' (sobreviviste)' else '' end
  from wolf_seats w
  where w.game_id = v_s.game_id
    and ((p_winner = 'wolves' and w.role = 'lobo') or (p_winner = 'village' and w.role <> 'lobo'))
    and v_s.pts_win + case when w.alive then v_s.pts_survive else 0 end <> 0;
  update wolf_state
  set status = 'finished', phase = 'finished', winner = p_winner, ends_at = null, seq = seq + 1
  where event_id = v_event;
  update dashboard_state set mode = 'wolf', updated_at = now() where event_id = v_event;
end $$;

-- Después de muertes: si hay deberes pendientes → fase 'duty'; si alguien ganó → fin; si no → p_next
create or replace function public.wolf_after_deaths(p_next text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_s     wolf_state%rowtype;
  v_win   text;
  v_secs  integer;
begin
  select * into v_s from wolf_state where event_id = v_event;
  if exists (select 1 from wolf_seats where game_id = v_s.game_id and (duty_hunter or duty_mayor)) then
    update wolf_state set phase = 'duty', after_duty = p_next, seq = seq + 1,
      ends_at = now() + make_interval(secs => coalesce((config->>'duty')::int, 30))
    where event_id = v_event;
    return;
  end if;
  v_win := wolf_check_win(v_s.game_id);
  if v_win is not null then perform wolf_finish(v_win); return; end if;

  v_secs := case p_next when 'night' then (v_s.config->>'night')::int when 'debate' then (v_s.config->>'debate')::int
                        when 'vote' then (v_s.config->>'vote')::int when 'mayor' then (v_s.config->>'vote')::int end;
  update wolf_state
  set phase = p_next, seq = seq + 1,
      night_no = night_no + case when p_next = 'night' then 1 else 0 end,
      night_seq = case when p_next = 'night' then seq + 1 else night_seq end,
      ends_at = case when v_secs is null then null else now() + make_interval(secs => v_secs) end
  where event_id = v_event;
end $$;

-- =====================================================================
-- RPC: JUGADORES
-- =====================================================================
create or replace function public.wolf_join()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_player uuid := current_player_id();
  v_s      wolf_state%rowtype;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status <> 'lobby' then return json_build_object('ok', false, 'error', 'La mesa no está abierta'); end if;
  if v_s.narrator_id = v_player then return json_build_object('ok', false, 'error', 'El narrador no juega'); end if;
  if (select count(*) from wolf_seats where game_id = v_s.game_id) >= 25 then
    return json_build_object('ok', false, 'error', 'La mesa está llena (25)');
  end if;
  insert into wolf_seats (event_id, game_id, player_id) values (v_s.event_id, v_s.game_id, v_player)
  on conflict do nothing;
  perform wolf_bump();
  return json_build_object('ok', true);
end $$;

create or replace function public.wolf_leave()
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status = 'lobby' then
    delete from wolf_seats where game_id = v_s.game_id and player_id = current_player_id();
    perform wolf_bump();
  end if;
end $$;

create or replace function public.wolf_mark_seen()
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  select * into v_s from wolf_state where event_id = active_event_id();
  update wolf_seats set card_seen = true where game_id = v_s.game_id and player_id = current_player_id() and not card_seen;
  if found then perform wolf_bump(); end if;
end $$;

-- Acción del jugador según la fase. p_target null = borrar la elección.
create or replace function public.wolf_act(p_kind text, p_target uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_player uuid := current_player_id();
  v_s      wolf_state%rowtype;
  v_me     wolf_seats%rowtype;
  v_t      wolf_seats%rowtype;
  v_ok     boolean := false;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  select * into v_me from wolf_seats where game_id = v_s.game_id and player_id = v_player;
  if v_s.status <> 'playing' or v_me.player_id is null then return json_build_object('ok', false, 'error', 'No estás en la partida'); end if;
  if p_target is not null then
    select * into v_t from wolf_seats where game_id = v_s.game_id and player_id = p_target;
    if v_t.player_id is null then return json_build_object('ok', false, 'error', 'Jugador inválido'); end if;
  end if;

  -- Deberes de muertos (cazador / alcalde)
  if v_s.phase = 'duty' then
    v_ok := (p_kind = 'shoot' and v_me.duty_hunter) or (p_kind = 'successor' and v_me.duty_mayor);
    if not v_ok then return json_build_object('ok', false, 'error', 'No tienes nada que hacer ahora'); end if;
    if p_target is not null and (not v_t.alive or p_target = v_player) then
      return json_build_object('ok', false, 'error', 'Elige a alguien vivo');
    end if;
  else
    if not v_me.alive then return json_build_object('ok', false, 'error', 'Estás muerto 💀'); end if;
    if p_target is not null and not v_t.alive then return json_build_object('ok', false, 'error', 'Esa persona está muerta'); end if;

    if v_s.phase = 'night' then
      if p_kind = 'wolf' and v_me.role = 'lobo' then
        v_ok := p_target is null or v_t.role <> 'lobo';
        if not v_ok then return json_build_object('ok', false, 'error', 'No puedes atacar a otro lobo'); end if;
      elsif p_kind = 'seer' and v_me.role = 'vidente' then
        if exists (select 1 from wolf_actions where game_id = v_s.game_id and seq = v_s.seq and kind = 'seer' and actor_id = v_player) then
          return json_build_object('ok', false, 'error', 'Ya usaste tu visión esta noche');
        end if;
        v_ok := p_target is not null and p_target <> v_player;
      elsif p_kind = 'suspect' and v_me.role not in ('lobo', 'vidente') then
        v_ok := p_target is null or p_target <> v_player;
      end if;
    elsif v_s.phase = 'night_witch' and v_me.role = 'bruja' then
      if p_kind = 'heal' then
        v_ok := v_me.heal_left and (p_target is null or p_target = wolf_victim(v_s.game_id, v_s.night_seq));
        if not v_ok then return json_build_object('ok', false, 'error', 'Solo puedes salvar a la víctima de los lobos (y una vez por partida)'); end if;
      elsif p_kind = 'poison' then
        v_ok := v_me.kill_left and (p_target is null or p_target <> v_player);
        if not v_ok then return json_build_object('ok', false, 'error', 'Ya usaste tu veneno'); end if;
      end if;
    elsif v_s.phase = 'mayor' and p_kind = 'mayor' then
      v_ok := true;
    elsif v_s.phase = 'vote' and p_kind = 'vote' then
      v_ok := p_target is null or p_target <> v_player;
    end if;
  end if;

  if not v_ok then return json_build_object('ok', false, 'error', 'No puedes hacer eso ahora'); end if;

  if p_target is null then
    delete from wolf_actions where game_id = v_s.game_id and seq = v_s.seq and kind = p_kind and actor_id = v_player;
  else
    insert into wolf_actions (event_id, game_id, seq, kind, actor_id, target_id)
    values (v_s.event_id, v_s.game_id, v_s.seq, p_kind, v_player, p_target)
    on conflict (game_id, seq, kind, actor_id) do update set target_id = excluded.target_id, created_at = now();
  end if;
  perform wolf_bump();
  return json_build_object('ok', true,
    'seen_role', case when p_kind = 'seer' then wolf_role_name(v_t.role) end);
end $$;

-- Lista pública de jugadores (rol solo si murió o terminó la partida)
create or replace function public.wolf_players_public(p_game uuid, p_show_votes boolean, p_seq integer, p_kind text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'id', s.player_id, 'name', pname(s.player_id), 'seat', s.seat, 'alive', s.alive, 'mayor', s.is_mayor,
           'role', case when not s.alive or st.status = 'finished' then s.role end,
           'voted', case when p_show_votes then exists (select 1 from wolf_actions a where a.game_id = p_game and a.seq = p_seq
                                                         and a.kind = p_kind and a.actor_id = s.player_id) end)
         order by s.seat nulls last, s.joined_at), '[]'::json)
  from wolf_seats s
  join wolf_state st on st.game_id = s.game_id
  where s.game_id = p_game
$$;

-- Lo que ve el celular de cada jugador
create or replace function public.wolf_my_view()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_player uuid := current_player_id();
  v_s      wolf_state%rowtype;
  v_me     wolf_seats%rowtype;
  v_n      integer;
  v_left   uuid;
  v_right  uuid;
  v_kind   text;
  v_extra  json;
begin
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status is null or v_s.status = 'none' then return json_build_object('status', 'none'); end if;
  select * into v_me from wolf_seats where game_id = v_s.game_id and player_id = v_player;

  -- Vecinos de asiento
  if v_me.seat is not null then
    select count(*) into v_n from wolf_seats where game_id = v_s.game_id;
    select player_id into v_left from wolf_seats where game_id = v_s.game_id and seat = case when v_me.seat = 1 then v_n else v_me.seat - 1 end;
    select player_id into v_right from wolf_seats where game_id = v_s.game_id and seat = case when v_me.seat = v_n then 1 else v_me.seat + 1 end;
  end if;

  -- Qué acción le toca ahora
  if v_s.status = 'playing' and v_me.player_id is not null then
    if v_s.phase = 'duty' then
      v_kind := case when v_me.duty_hunter then 'shoot' when v_me.duty_mayor then 'successor' end;
    elsif v_me.alive then
      v_kind := case
        when v_s.phase = 'night' and v_me.role = 'lobo' then 'wolf'
        when v_s.phase = 'night' and v_me.role = 'vidente' then 'seer'
        when v_s.phase = 'night' then 'suspect'
        when v_s.phase = 'night_witch' and v_me.role = 'bruja' then 'witch'
        when v_s.phase = 'mayor' then 'mayor'
        when v_s.phase = 'vote' then 'vote'
      end;
    end if;

    v_extra := json_build_object(
      -- Manada: los lobos se ven entre ellos y ven en vivo a quién elige cada uno
      'pack', case when v_me.role = 'lobo' then
                (select json_agg(json_build_object('name', pname(s.player_id), 'alive', s.alive,
                   'choice', (select pname(a.target_id) from wolf_actions a where a.game_id = s.game_id and a.seq = v_s.seq
                              and a.kind = 'wolf' and a.actor_id = s.player_id and v_s.phase = 'night')))
                 from wolf_seats s where s.game_id = v_s.game_id and s.role = 'lobo' and s.player_id <> v_player) end,
      -- Vidente: historial de lo que vio
      'visions', case when v_me.role = 'vidente' then
                   (select json_agg(json_build_object('name', pname(a.target_id), 'role', wolf_role_name(t.role)) order by a.seq)
                    from wolf_actions a join wolf_seats t on t.game_id = a.game_id and t.player_id = a.target_id
                    where a.game_id = v_s.game_id and a.kind = 'seer' and a.actor_id = v_player) end,
      -- Bruja: víctima de esta noche y pociones
      'witch', case when v_me.role = 'bruja' and v_s.phase = 'night_witch' then
                 json_build_object('victim', pname(wolf_victim(v_s.game_id, v_s.night_seq)),
                                   'victim_id', wolf_victim(v_s.game_id, v_s.night_seq),
                                   'heal_left', v_me.heal_left, 'kill_left', v_me.kill_left) end,
      'potions', case when v_me.role = 'bruja' then json_build_object('heal', v_me.heal_left, 'kill', v_me.kill_left) end
    );
  end if;

  return json_build_object(
    'status', v_s.status, 'phase', v_s.phase, 'night_no', v_s.night_no, 'day_no', v_s.day_no,
    'ends_at', v_s.ends_at, 'now', now(),
    'me', v_player,
    'is_narrator', v_s.narrator_id = v_player,
    'narrator', pname(v_s.narrator_id),
    'joined', v_me.player_id is not null,
    'joined_count', (select count(*) from wolf_seats where game_id = v_s.game_id),
    'role', v_me.role, 'alive', v_me.alive, 'card_seen', v_me.card_seen, 'is_mayor', v_me.is_mayor,
    'death_text', v_me.death_text,
    'neighbors', case when v_left is not null then json_build_array(pname(v_left), pname(v_right)) end,
    'action', v_kind,
    'my_choice', (select json_object_agg(a.kind, a.target_id) from wolf_actions a
                  where a.game_id = v_s.game_id and a.seq = v_s.seq and a.actor_id = v_player),
    'extra', v_extra,
    'players', wolf_players_public(v_s.game_id, false, 0, ''),
    'deck', v_s.deck,
    'last_result', v_s.last_result,
    'winner', v_s.winner
  );
end $$;

-- Lo que muestra la TV
create or replace function public.wolf_public_view()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status is null or v_s.status = 'none' then return json_build_object('status', 'none'); end if;
  return json_build_object(
    'status', v_s.status, 'phase', v_s.phase, 'night_no', v_s.night_no, 'day_no', v_s.day_no,
    'ends_at', v_s.ends_at, 'now', now(),
    'narrator', pname(v_s.narrator_id),
    'players', wolf_players_public(v_s.game_id, v_s.phase in ('vote', 'mayor'), v_s.seq,
                                   case when v_s.phase = 'mayor' then 'mayor' else 'vote' end),
    'deck', v_s.deck,
    'last_result', v_s.last_result,
    'winner', v_s.winner,
    'mayor_enabled', coalesce((v_s.config->>'mayor')::boolean, true)
  );
end $$;

-- =====================================================================
-- RPC: NARRADOR
-- =====================================================================
create or replace function public.wolf_narrator_view()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  return json_build_object(
    'status', v_s.status, 'phase', v_s.phase, 'night_no', v_s.night_no, 'day_no', v_s.day_no,
    'ends_at', v_s.ends_at, 'now', now(), 'config', v_s.config, 'winner', v_s.winner, 'last_result', v_s.last_result,
    'seats', (select coalesce(json_agg(json_build_object(
                'id', s.player_id, 'name', pname(s.player_id), 'seat', s.seat, 'role', s.role, 'alive', s.alive,
                'seen', s.card_seen, 'mayor', s.is_mayor, 'duty_hunter', s.duty_hunter, 'duty_mayor', s.duty_mayor,
                'heal_left', s.heal_left, 'kill_left', s.kill_left,
                'acted', exists (select 1 from wolf_actions a where a.game_id = s.game_id and a.seq = v_s.seq and a.actor_id = s.player_id))
              order by s.seat nulls last, s.joined_at), '[]'::json)
              from wolf_seats s where s.game_id = v_s.game_id),
    'actions', (select coalesce(json_agg(json_build_object('kind', a.kind, 'actor', pname(a.actor_id), 'target', pname(a.target_id))), '[]'::json)
                from wolf_actions a where a.game_id = v_s.game_id and a.seq = v_s.seq),
    'victim', case when v_s.phase in ('night', 'night_witch') then pname(wolf_victim(v_s.game_id, v_s.night_seq)) end,
    'witch_actions', case when v_s.phase = 'night_witch' then
                       (select json_agg(json_build_object('kind', a.kind, 'target', pname(a.target_id)))
                        from wolf_actions a where a.game_id = v_s.game_id and a.seq = v_s.seq) end
  );
end $$;

create or replace function public.wolf_kick(p_player uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not (wolf_is_narrator() or is_admin()) then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status not in ('lobby', 'setup') then raise exception 'La partida ya empezó'; end if;
  delete from wolf_seats where game_id = v_s.game_id and player_id = p_player;
  perform wolf_bump();
end $$;

create or replace function public.wolf_close_table()
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status <> 'lobby' then raise exception 'La mesa no está abierta'; end if;
  if (select count(*) from wolf_seats where game_id = v_s.game_id) < 4 then raise exception 'Se necesitan al menos 4 jugadores (ideal 6 o más)'; end if;
  update wolf_state set status = 'setup' where event_id = v_s.event_id;
  perform wolf_bump();
end $$;

create or replace function public.wolf_reopen_table()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  update wolf_state set status = 'lobby' where event_id = active_event_id() and status = 'setup';
  perform wolf_bump();
end $$;

-- Configuración (tiempos, alcalde, baraja pública)
create or replace function public.wolf_set_config(p_config jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  update wolf_state set config = config || (p_config - 'deck') where event_id = active_event_id();
  perform wolf_bump();
end $$;

-- Repartir: p_deck = {"lobo":2,"vidente":1,"bruja":1,"cazador":1}; el resto son aldeanos
create or replace function public.wolf_deal(p_deck jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s      wolf_state%rowtype;
  v_n      integer;
  v_roles  text[] := '{}';
  v_role   text;
  v_k      integer;
  v_spec   integer := 0;
  v_full   jsonb;
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id() for update;
  if v_s.status <> 'setup' then raise exception 'Primero cierra la mesa'; end if;
  select count(*) into v_n from wolf_seats where game_id = v_s.game_id;

  for v_role, v_k in select key, value::int from jsonb_each_text(p_deck) loop
    if v_role not in ('lobo', 'vidente', 'bruja', 'cazador') then raise exception 'Rol no disponible: %', v_role; end if;
    if v_k < 0 then raise exception 'Cantidad inválida'; end if;
    v_roles := v_roles || array_fill(v_role, array[v_k]);
    v_spec := v_spec + v_k;
  end loop;
  if coalesce((p_deck->>'lobo')::int, 0) < 1 then raise exception 'Debe haber al menos 1 lobo'; end if;
  if v_spec > v_n then raise exception 'Hay más roles especiales (%) que jugadores (%)', v_spec, v_n; end if;
  v_roles := v_roles || array_fill('aldeano'::text, array[v_n - v_spec]);
  v_full := p_deck || jsonb_build_object('aldeano', v_n - v_spec);

  -- Roles y asientos al azar
  with r as (select role, row_number() over (order by random()) as rn from unnest(v_roles) as role),
       p as (select player_id, row_number() over (order by random()) as rn from wolf_seats where game_id = v_s.game_id)
  update wolf_seats w set role = r.role, seat = p.rn, alive = true, card_seen = false, heal_left = true, kill_left = true,
                          is_mayor = false, duty_hunter = false, duty_mayor = false, death_text = null
  from p join r on r.rn = p.rn
  where w.game_id = v_s.game_id and w.player_id = p.player_id;

  update wolf_state
  set status = 'playing', phase = 'dealt', seq = seq + 1, night_no = 0, day_no = 0, ends_at = null, winner = null,
      last_result = null, deck = case when coalesce((config->>'public_deck')::boolean, true) then v_full end
  where event_id = v_s.event_id;
  update dashboard_state set mode = 'wolf', updated_at = now() where event_id = v_s.event_id;
  perform wolf_bump();
end $$;

-- Resolver la noche (ataque de lobos, pociones)
create or replace function public.wolf_resolve_night()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s       wolf_state%rowtype;
  v_victim  uuid;
  v_witch   wolf_seats%rowtype;
  v_healed  boolean := false;
  v_poison  uuid;
  v_before  uuid[];
  v_deaths  json;
begin
  select * into v_s from wolf_state where event_id = active_event_id();
  v_victim := wolf_victim(v_s.game_id, v_s.night_seq);
  select * into v_witch from wolf_seats where game_id = v_s.game_id and role = 'bruja' and alive limit 1;
  if v_witch.player_id is not null then
    v_healed := v_witch.heal_left and v_victim is not null and exists (
      select 1 from wolf_actions where game_id = v_s.game_id and seq = v_s.seq and kind = 'heal'
      and actor_id = v_witch.player_id and target_id = v_victim) and v_s.phase = 'night_witch';
    if v_witch.kill_left and v_s.phase = 'night_witch' then
      select target_id into v_poison from wolf_actions
      where game_id = v_s.game_id and seq = v_s.seq and kind = 'poison' and actor_id = v_witch.player_id;
    end if;
    update wolf_seats set heal_left = heal_left and not v_healed, kill_left = kill_left and v_poison is null
    where game_id = v_s.game_id and player_id = v_witch.player_id;
  end if;

  select array_agg(player_id) into v_before from wolf_seats where game_id = v_s.game_id and alive;
  if v_victim is not null and not v_healed then
    perform wolf_kill(v_s.game_id, v_victim, 'Atacado por los lobos (noche ' || v_s.night_no || ')');
  end if;
  if v_poison is not null then
    perform wolf_kill(v_s.game_id, v_poison, 'Envenenado (noche ' || v_s.night_no || ')');
  end if;

  select coalesce(json_agg(json_build_object('name', pname(player_id), 'role', wolf_role_name(role))), '[]'::json)
  into v_deaths from wolf_seats where game_id = v_s.game_id and not alive and player_id = any(v_before);

  update wolf_state set day_no = night_no,
    last_result = json_build_object('type', 'night', 'night', v_s.night_no, 'deaths', v_deaths)
  where event_id = v_s.event_id;
  perform wolf_after_deaths('dawn');
end $$;

-- Siguiente fase (el narrador controla el ritmo)
create or replace function public.wolf_advance()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s      wolf_state%rowtype;
  v_top    uuid;
  v_topn   numeric;
  v_ties   integer;
  v_votes  json;
  v_before uuid[];
  v_deaths json;
  r        record;
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id() for update;
  if v_s.status <> 'playing' then raise exception 'No hay partida en juego'; end if;

  if v_s.phase = 'dealt' then
    perform wolf_after_deaths('night');

  elsif v_s.phase = 'night' then
    if exists (select 1 from wolf_seats where game_id = v_s.game_id and role = 'bruja' and alive and (heal_left or kill_left)) then
      update wolf_state set phase = 'night_witch', seq = seq + 1,
        ends_at = now() + make_interval(secs => coalesce((config->>'witch')::int, 30))
      where event_id = v_s.event_id;
    else
      perform wolf_resolve_night();
    end if;

  elsif v_s.phase = 'night_witch' then
    perform wolf_resolve_night();

  elsif v_s.phase = 'dawn' then
    if v_s.day_no = 1 and coalesce((v_s.config->>'mayor')::boolean, true)
       and not exists (select 1 from wolf_seats where game_id = v_s.game_id and is_mayor and alive) then
      perform wolf_after_deaths('mayor');
    else
      perform wolf_after_deaths('debate');
    end if;

  elsif v_s.phase = 'mayor' then
    select a.target_id into v_top
    from wolf_actions a
    join wolf_seats vv on vv.game_id = a.game_id and vv.player_id = a.actor_id and vv.alive
    join wolf_seats tt on tt.game_id = a.game_id and tt.player_id = a.target_id and tt.alive
    where a.game_id = v_s.game_id and a.seq = v_s.seq and a.kind = 'mayor'
    group by a.target_id order by count(*) desc, random() limit 1;
    if v_top is not null then
      update wolf_seats set is_mayor = (player_id = v_top) where game_id = v_s.game_id;
    end if;
    update wolf_state set last_result = json_build_object('type', 'mayor', 'name', pname(v_top)) where event_id = v_s.event_id;
    perform wolf_after_deaths('debate');

  elsif v_s.phase = 'debate' then
    perform wolf_after_deaths('vote');

  elsif v_s.phase = 'vote' then
    -- Conteo (el alcalde vale doble)
    select coalesce(json_agg(json_build_object('target', pname(x.target_id), 'votes', x.w, 'voters', x.voters) order by x.w desc), '[]'::json)
    into v_votes from (
      select a.target_id, sum(case when vv.is_mayor then 2 else 1 end) as w,
             json_agg(pname(a.actor_id) || case when vv.is_mayor then ' 🎖️' else '' end) as voters
      from wolf_actions a
      join wolf_seats vv on vv.game_id = a.game_id and vv.player_id = a.actor_id and vv.alive
      join wolf_seats tt on tt.game_id = a.game_id and tt.player_id = a.target_id and tt.alive
      where a.game_id = v_s.game_id and a.seq = v_s.seq and a.kind = 'vote'
      group by a.target_id) x;

    select x.target_id, x.w into v_top, v_topn from (
      select a.target_id, sum(case when vv.is_mayor then 2 else 1 end) as w
      from wolf_actions a
      join wolf_seats vv on vv.game_id = a.game_id and vv.player_id = a.actor_id and vv.alive
      join wolf_seats tt on tt.game_id = a.game_id and tt.player_id = a.target_id and tt.alive
      where a.game_id = v_s.game_id and a.seq = v_s.seq and a.kind = 'vote'
      group by a.target_id) x order by x.w desc limit 1;
    select count(*) into v_ties from (
      select a.target_id from wolf_actions a
      join wolf_seats vv on vv.game_id = a.game_id and vv.player_id = a.actor_id and vv.alive
      join wolf_seats tt on tt.game_id = a.game_id and tt.player_id = a.target_id and tt.alive
      where a.game_id = v_s.game_id and a.seq = v_s.seq and a.kind = 'vote'
      group by a.target_id having sum(case when vv.is_mayor then 2 else 1 end) = v_topn) t;

    if v_top is not null and v_ties = 1 then
      perform wolf_kill(v_s.game_id, v_top, 'Linchado por la aldea (día ' || v_s.day_no || ')');
      update wolf_state set last_result = json_build_object('type', 'vote', 'day', v_s.day_no, 'votes', v_votes,
          'lynched', json_build_object('name', pname(v_top), 'role', (select wolf_role_name(role) from wolf_seats where game_id = v_s.game_id and player_id = v_top))),
          phase = 'verdict', seq = seq + 1, ends_at = null
      where event_id = v_s.event_id;
    else
      update wolf_state set last_result = json_build_object('type', 'vote', 'day', v_s.day_no, 'votes', v_votes,
          'tie', v_top is not null),
          phase = 'verdict', seq = seq + 1, ends_at = null
      where event_id = v_s.event_id;
    end if;
    -- Deberes o victoria se revisan al salir del veredicto

  elsif v_s.phase = 'verdict' then
    perform wolf_after_deaths('night');

  elsif v_s.phase = 'duty' then
    select array_agg(player_id) into v_before from wolf_seats where game_id = v_s.game_id and alive;
    for r in select * from wolf_seats where game_id = v_s.game_id and (duty_hunter or duty_mayor) loop
      if r.duty_mayor then
        update wolf_seats set is_mayor = false where game_id = v_s.game_id and player_id = r.player_id;
        update wolf_seats s set is_mayor = true
        from wolf_actions a
        where a.game_id = v_s.game_id and a.seq = v_s.seq and a.kind = 'successor' and a.actor_id = r.player_id
          and s.game_id = a.game_id and s.player_id = a.target_id and s.alive;
      end if;
      update wolf_seats set duty_mayor = false, duty_hunter = false where game_id = v_s.game_id and player_id = r.player_id;
      if r.duty_hunter then
        for v_top in select target_id from wolf_actions
                     where game_id = v_s.game_id and seq = v_s.seq and kind = 'shoot' and actor_id = r.player_id loop
          perform wolf_kill(v_s.game_id, v_top, 'Disparo del cazador');
        end loop;
      end if;
    end loop;
    select coalesce(json_agg(json_build_object('name', pname(player_id), 'role', wolf_role_name(role))), '[]'::json)
    into v_deaths from wolf_seats where game_id = v_s.game_id and not alive and player_id = any(v_before);
    if json_array_length(v_deaths) > 0 then
      update wolf_state set last_result = json_build_object('type', 'shot', 'deaths', v_deaths) where event_id = v_s.event_id;
    end if;
    perform wolf_after_deaths(coalesce(v_s.after_duty, 'night'));
  end if;

  perform wolf_bump();
end $$;

-- Correcciones del narrador: matar o revivir
create or replace function public.wolf_override(p_player uuid, p_alive boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if p_alive then
    update wolf_seats set alive = true, death_text = null, duty_hunter = false, duty_mayor = false
    where game_id = v_s.game_id and player_id = p_player;
  else
    perform wolf_kill(v_s.game_id, p_player, 'Eliminado por el narrador');
    update wolf_seats set duty_hunter = false, duty_mayor = false where game_id = v_s.game_id and player_id = p_player;
  end if;
  perform wolf_bump();
end $$;

-- Terminar a mano declarando ganador
create or replace function public.wolf_declare_winner(p_winner text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  if p_winner not in ('village', 'wolves') then raise exception 'Ganador inválido'; end if;
  perform wolf_finish(p_winner);
  perform wolf_bump();
end $$;

-- =====================================================================
-- RPC: ADMIN (no ve roles)
-- =====================================================================
create or replace function public.admin_wolf_overview()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  return json_build_object(
    'status', coalesce(v_s.status, 'none'), 'phase', v_s.phase, 'night_no', v_s.night_no, 'day_no', v_s.day_no,
    'narrator', pname(v_s.narrator_id), 'narrator_id', v_s.narrator_id, 'winner', v_s.winner,
    'players', (select coalesce(json_agg(pname(player_id)), '[]'::json) from wolf_seats where game_id = v_s.game_id),
    'settings', json_build_object('win', coalesce(v_s.pts_win, 8), 'survive', coalesce(v_s.pts_survive, 2))
  );
end $$;

-- Abrir una mesa nueva con un narrador
create or replace function public.admin_wolf_open(p_narrator uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  if (select status from wolf_state where event_id = v_event) in ('lobby', 'setup', 'playing') then
    raise exception 'Ya hay una partida. Cancélala primero.';
  end if;
  if not exists (select 1 from players where id = p_narrator and event_id = v_event and approved) then
    raise exception 'Elige un narrador';
  end if;
  update wolf_state
  set game_id = gen_random_uuid(), status = 'lobby', phase = null, seq = 0, night_seq = null, night_no = 0, day_no = 0,
      ends_at = null, narrator_id = p_narrator, deck = null, winner = null, after_duty = null, last_result = null,
      version = version + 1, updated_at = now()
  where event_id = v_event;
end $$;

create or replace function public.admin_wolf_set_narrator(p_narrator uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if exists (select 1 from wolf_seats where game_id = v_s.game_id and player_id = p_narrator) then
    raise exception 'Esa persona está jugando; no puede narrar';
  end if;
  update wolf_state set narrator_id = p_narrator where event_id = v_s.event_id;
  perform wolf_bump();
end $$;

create or replace function public.admin_wolf_cancel()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  update wolf_state set status = 'none', phase = null, ends_at = null, version = version + 1, updated_at = now()
  where event_id = active_event_id();
end $$;

create or replace function public.admin_wolf_settings(p_win integer, p_survive integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if least(p_win, p_survive) < 0 or greatest(p_win, p_survive) > 500 then raise exception 'Puntos fuera de rango'; end if;
  v_event := ensure_event_rows();
  update wolf_state set pts_win = p_win, pts_survive = p_survive where event_id = v_event;
end $$;

-- =====================================================================
-- PANTALLA Y REINICIO (redefinidos)
-- =====================================================================
create or replace function public.admin_set_dashboard(p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_mode not in ('leaderboard', 'costume_reveal', 'codes', 'persona', 'impostor', 'gift', 'wolf', 'final') then
    raise exception 'Modo inválido';
  end if;
  v_event := ensure_event_rows();
  update dashboard_state set mode = p_mode, updated_at = now() where event_id = v_event;
end $$;

create or replace function public.admin_reset(p_scope text, p_confirm text, p_event_name text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_confirm is distinct from 'BORRAR' then raise exception 'Confirmación incorrecta'; end if;
  if p_scope not in ('points', 'all') then raise exception 'Opción inválida'; end if;
  v_event := ensure_event_rows();

  delete from points_ledger   where event_id = v_event;
  -- Disfraces
  delete from costume_ballots where event_id = v_event;
  delete from costume_results where event_id = v_event;
  update costume_contest
  set status = 'not_started', reveal_step = 0, opened_at = null, closed_at = null, updated_at = now()
  where event_id = v_event;
  -- Caza de códigos (los códigos se conservan)
  delete from hunt_claims where event_id = v_event;
  delete from hunt_failed where player_id in (select id from players where event_id = v_event);
  update code_hunt set status = 'not_started', updated_at = now() where event_id = v_event;
  -- ¿Quién es el personaje? (los datos se conservan)
  delete from persona_rounds where event_id = v_event;
  update persona_game
  set current_round_id = null, round_status = 'none', ends_at = null, votes_count = 0, updated_at = now()
  where event_id = v_event;
  -- El Impostor
  delete from impostor_rounds where event_id = v_event;
  update impostor_game
  set status = 'none', current_round_id = null, vote_no = 0, vote_status = 'none', last_result = null, updated_at = now()
  where event_id = v_event;
  -- El Regalo Loco
  delete from gift_rounds where event_id = v_event;
  update gift_game
  set status = 'none', current_round_id = null, read_index = 0, reveal_step = 0,
      parts_done = 0, parts_total = 0, voters_done = 0, updated_at = now()
  where event_id = v_event;
  -- Hombre Lobo
  delete from wolf_actions where event_id = v_event;
  delete from wolf_seats where event_id = v_event;
  update wolf_state set status = 'none', phase = null, game_id = null, narrator_id = null, ends_at = null,
    last_result = null, winner = null, version = version + 1, updated_at = now()
  where event_id = v_event;
  -- Pantalla (y descongelar). El wifi se conserva.
  update dashboard_state set mode = 'leaderboard', frozen_at = null, updated_at = now() where event_id = v_event;

  if p_scope = 'all' then
    delete from players where event_id = v_event and not is_admin;
    if coalesce(trim(p_event_name), '') <> '' then
      update events set name = trim(p_event_name) where id = v_event;
    end if;
  end if;
end $$;

grant execute on all functions in schema public to anon, authenticated;

-- Tiempo real: solo la tabla pública de estado
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'wolf_state') then
    alter publication supabase_realtime add table public.wolf_state;
  end if;
end $$;

-- =====================================================================
-- Party Games App · Fase 8: "Me ausento un rato", todos juegan automáticamente,
-- pestañas de juegos y temporizador del Regalo Loco.
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1 a 7 (incluido 08_fase7_lobo.sql).
--
-- Qué agrega:
--   • players.away: el invitado (o el admin) lo marca con "⏸ Me ausento un rato" / "▶︎ Ya volví".
--     Mientras está ausente: no actúa, no vota y nadie lo puede elegir. Conserva su carta/rol.
--   • Hombre Lobo: TODOS los presentes quedan sentados automáticamente al abrir la mesa (sin "Unirme").
--     El admin y el narrador pueden "matar" a alguien que se fue y no vuelve.
--   • Impostor / Regalo: los ausentes no entran a la ronda nueva. Personaje: no salen sus datos.
--   • Regalo Loco: temporizador de escritura (30 s por defecto) y reasignar partes a otra persona.
--   • get_my_games(): qué juegos están activos para mostrar pestañas y el aviso "¡Empezó…!".
-- =====================================================================

-- =====================================================================
-- COLUMNAS NUEVAS
-- =====================================================================
alter table public.players     add column if not exists away        boolean not null default false;
alter table public.players     add column if not exists away_since  timestamptz;
alter table public.wolf_state  add column if not exists excluded    uuid[] not null default '{}';
alter table public.gift_game   add column if not exists writing_seconds integer not null default 30;
alter table public.gift_game   add column if not exists ends_at     timestamptz;
alter table public.gift_chains add column if not exists object_writer_id uuid references public.players(id) on delete cascade;

-- =====================================================================
-- AUSENTE
-- =====================================================================
create or replace function public.is_away(p_player uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select away from players where id = p_player), false)
$$;

-- Sienta en la mesa del Lobo (mientras está abierta o se arma la baraja) a todos los presentes:
-- aprobados, no ausentes, no narrador y no sacados a mano por el narrador.
create or replace function public.wolf_sync_lobby()
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status is null or v_s.status not in ('lobby', 'setup') or v_s.game_id is null then return; end if;
  delete from wolf_seats w using players p
  where w.game_id = v_s.game_id and p.id = w.player_id
    and (p.away or not p.approved or p.id = v_s.narrator_id or p.id = any(v_s.excluded));
  insert into wolf_seats (event_id, game_id, player_id)
  select v_s.event_id, v_s.game_id, p.id
  from players p
  where p.event_id = v_s.event_id and p.approved and not p.away
    and p.id is distinct from v_s.narrator_id and not (p.id = any(v_s.excluded))
  on conflict do nothing;
end $$;

-- Efectos de entrar/salir de "ausente" en los juegos en curso
create or replace function public.away_changed(p_player uuid, p_away boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_w     wolf_state%rowtype;
  v_i     impostor_game%rowtype;
begin
  -- Hombre Lobo
  select * into v_w from wolf_state where event_id = v_event;
  if v_w.status in ('lobby', 'setup') then
    perform wolf_sync_lobby();
  elsif v_w.status = 'playing' and p_away then
    -- Lo que eligió (o lo que eligieron sobre él) en la fase actual deja de contar
    delete from wolf_actions where game_id = v_w.game_id and seq = v_w.seq
      and (actor_id = p_player or target_id = p_player);
  end if;
  update wolf_state set version = version + 1, updated_at = now() where event_id = v_event;

  -- Impostor: sus votos (y los votos hacia él) de la votación abierta dejan de contar
  select * into v_i from impostor_game where event_id = v_event;
  if p_away and v_i.status = 'playing' and v_i.vote_status = 'open' then
    delete from impostor_votes where round_id = v_i.current_round_id and vote_no = v_i.vote_no
      and (voter_id = p_player or target_id = p_player);
  end if;
  update impostor_game set updated_at = now() where event_id = v_event;
  update gift_game set updated_at = now() where event_id = v_event;
end $$;

create or replace function public.set_my_away(p_away boolean)
returns json language plpgsql security definer set search_path = public as $$
declare v_player uuid := current_player_id();
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  update players set away = p_away, away_since = case when p_away then now() end
  where id = v_player and away is distinct from p_away;
  if found then perform away_changed(v_player, p_away); end if;
  return json_build_object('ok', true, 'away', p_away);
end $$;

create or replace function public.admin_set_away(p_player uuid, p_away boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_admin() or wolf_is_narrator()) then raise exception 'Solo el admin puede hacer esto'; end if;
  update players set away = p_away, away_since = case when p_away then now() end
  where id = p_player and event_id = active_event_id() and away is distinct from p_away;
  if found then perform away_changed(p_player, p_away); end if;
end $$;

-- Tabla general y lista de invitados con el estado "ausente"
drop function if exists public.get_leaderboard();
create function public.get_leaderboard()
returns table (player_id uuid, name text, nickname text, has_costume boolean, costume text, points bigint, away boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.nickname, p.has_costume, p.costume,
         coalesce(sum(l.points) filter (
           where l.visible and (board_frozen_at() is null or l.created_at <= board_frozen_at())), 0)::bigint as pts,
         p.away
  from players p
  left join points_ledger l on l.player_id = p.id
  where p.event_id = active_event_id() and p.approved
  group by p.id
  order by pts desc, p.name
$$;

drop function if exists public.admin_players();
create function public.admin_players()
returns table (player_id uuid, name text, nickname text, has_costume boolean, costume text,
               approved boolean, is_admin boolean, devices bigint, away boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  return query
    select p.id, p.name, p.nickname, p.has_costume, p.costume, p.approved, p.is_admin,
           (select count(*) from player_devices d where d.player_id = p.id and d.status = 'approved'),
           p.away
    from players p
    where p.event_id = active_event_id() and p.approved
    order by p.name;
end $$;

-- =====================================================================
-- HOMBRE LOBO
-- =====================================================================

-- Lista pública de jugadores (con "ausente")
create or replace function public.wolf_players_public(p_game uuid, p_show_votes boolean, p_seq integer, p_kind text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'id', s.player_id, 'name', pname(s.player_id), 'seat', s.seat, 'alive', s.alive, 'mayor', s.is_mayor,
           'away', p.away,
           'role', case when not s.alive or st.status = 'finished' then s.role end,
           'voted', case when p_show_votes then exists (select 1 from wolf_actions a where a.game_id = p_game and a.seq = p_seq
                                                         and a.kind = p_kind and a.actor_id = s.player_id) end)
         order by s.seat nulls last, s.joined_at), '[]'::json)
  from wolf_seats s
  join wolf_state st on st.game_id = s.game_id
  join players p on p.id = s.player_id
  where s.game_id = p_game
$$;

-- Quiénes NO están en la mesa (para que el narrador / admin los vuelva a sumar)
create or replace function public.wolf_benched_json()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'id', p.id, 'name', coalesce(p.nickname, p.name), 'away', p.away,
           'excluded', p.id = any(st.excluded)) order by coalesce(p.nickname, p.name)), '[]'::json)
  from players p
  join wolf_state st on st.event_id = p.event_id
  where p.event_id = active_event_id() and p.approved
    and p.id is distinct from st.narrator_id
    and not exists (select 1 from wolf_seats s where s.game_id = st.game_id and s.player_id = p.id)
$$;

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
  if is_away(v_player) then
    return json_build_object('ok', false, 'error', 'Estás ausente ⏸. Toca "Ya volví" para seguir jugando.');
  end if;
  if p_target is not null then
    select * into v_t from wolf_seats where game_id = v_s.game_id and player_id = p_target;
    if v_t.player_id is null then return json_build_object('ok', false, 'error', 'Jugador inválido'); end if;
    if is_away(p_target) then return json_build_object('ok', false, 'error', 'Esa persona está ausente ⏸'); end if;
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

-- Vista del jugador (igual que antes + 'away')
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

  if v_me.seat is not null then
    select count(*) into v_n from wolf_seats where game_id = v_s.game_id;
    select player_id into v_left from wolf_seats where game_id = v_s.game_id and seat = case when v_me.seat = 1 then v_n else v_me.seat - 1 end;
    select player_id into v_right from wolf_seats where game_id = v_s.game_id and seat = case when v_me.seat = v_n then 1 else v_me.seat + 1 end;
  end if;

  if v_s.status = 'playing' and v_me.player_id is not null then
    if is_away(v_player) then
      v_kind := null;
    elsif v_s.phase = 'duty' then
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
      'pack', case when v_me.role = 'lobo' then
                (select json_agg(json_build_object('name', pname(s.player_id), 'alive', s.alive,
                   'choice', (select pname(a.target_id) from wolf_actions a where a.game_id = s.game_id and a.seq = v_s.seq
                              and a.kind = 'wolf' and a.actor_id = s.player_id and v_s.phase = 'night')))
                 from wolf_seats s where s.game_id = v_s.game_id and s.role = 'lobo' and s.player_id <> v_player) end,
      'visions', case when v_me.role = 'vidente' then
                   (select json_agg(json_build_object('name', pname(a.target_id), 'role', wolf_role_name(t.role)) order by a.seq)
                    from wolf_actions a join wolf_seats t on t.game_id = a.game_id and t.player_id = a.target_id
                    where a.game_id = v_s.game_id and a.kind = 'seer' and a.actor_id = v_player) end,
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
    'away', is_away(v_player),
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
                'away', p.away,
                'seen', s.card_seen, 'mayor', s.is_mayor, 'duty_hunter', s.duty_hunter, 'duty_mayor', s.duty_mayor,
                'heal_left', s.heal_left, 'kill_left', s.kill_left,
                'acted', exists (select 1 from wolf_actions a where a.game_id = s.game_id and a.seq = v_s.seq and a.actor_id = s.player_id))
              order by s.seat nulls last, s.joined_at), '[]'::json)
              from wolf_seats s join players p on p.id = s.player_id where s.game_id = v_s.game_id),
    'benched', wolf_benched_json(),
    'actions', (select coalesce(json_agg(json_build_object('kind', a.kind, 'actor', pname(a.actor_id), 'target', pname(a.target_id))), '[]'::json)
                from wolf_actions a where a.game_id = v_s.game_id and a.seq = v_s.seq),
    'victim', case when v_s.phase in ('night', 'night_witch') then pname(wolf_victim(v_s.game_id, v_s.night_seq)) end,
    'witch_actions', case when v_s.phase = 'night_witch' then
                       (select json_agg(json_build_object('kind', a.kind, 'target', pname(a.target_id)))
                        from wolf_actions a where a.game_id = v_s.game_id and a.seq = v_s.seq) end
  );
end $$;

-- Sacar de la mesa (antes de repartir). Queda "excluido" hasta que lo vuelvan a sumar.
create or replace function public.wolf_kick(p_player uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not (wolf_is_narrator() or is_admin()) then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status not in ('lobby', 'setup') then raise exception 'La partida ya empezó'; end if;
  update wolf_state set excluded = array_append(array_remove(excluded, p_player), p_player) where event_id = v_s.event_id;
  delete from wolf_seats where game_id = v_s.game_id and player_id = p_player;
  perform wolf_bump();
end $$;

-- Volver a sumar a la mesa (también lo saca de "ausente")
create or replace function public.wolf_unkick(p_player uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not (wolf_is_narrator() or is_admin()) then raise exception 'Solo el narrador'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status not in ('lobby', 'setup') then raise exception 'La partida ya empezó: entra en la siguiente'; end if;
  update wolf_state set excluded = array_remove(excluded, p_player) where event_id = v_s.event_id;
  update players set away = false, away_since = null where id = p_player and away;
  perform wolf_sync_lobby();
  perform wolf_bump();
end $$;

create or replace function public.wolf_close_table()
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not wolf_is_narrator() then raise exception 'Solo el narrador'; end if;
  perform wolf_sync_lobby();
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status <> 'lobby' then raise exception 'La mesa no está abierta'; end if;
  if (select count(*) from wolf_seats where game_id = v_s.game_id) < 4 then raise exception 'Se necesitan al menos 4 jugadores (ideal 6 o más)'; end if;
  update wolf_state set status = 'setup' where event_id = v_s.event_id;
  perform wolf_bump();
end $$;

-- Repartir (igual que antes, pero primero sienta a los que acaban de llegar / volver)
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
  perform wolf_sync_lobby();
  select * into v_s from wolf_state where event_id = active_event_id() for update;
  if v_s.status <> 'setup' then raise exception 'Primero cierra la mesa'; end if;
  select count(*) into v_n from wolf_seats where game_id = v_s.game_id;
  if v_n < 4 then raise exception 'Se necesitan al menos 4 jugadores'; end if;

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

-- "Matar" a alguien que se fue (narrador o admin). Se revela su carta.
create or replace function public.wolf_kill_away(p_player uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s wolf_state%rowtype;
  v_role text;
begin
  if not (wolf_is_narrator() or is_admin()) then raise exception 'Solo el narrador o el admin'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status <> 'playing' then raise exception 'No hay partida en juego'; end if;
  select role into v_role from wolf_seats where game_id = v_s.game_id and player_id = p_player and alive;
  if v_role is null then raise exception 'Esa persona no está viva en la partida'; end if;
  perform wolf_kill(v_s.game_id, p_player, 'Se retiró de la partida');
  -- No dispara ni elige sucesor (no está); si era alcalde, el cargo queda libre
  update wolf_seats set duty_hunter = false, duty_mayor = false, is_mayor = false
  where game_id = v_s.game_id and player_id = p_player;
  delete from wolf_actions where game_id = v_s.game_id and seq = v_s.seq and (actor_id = p_player or target_id = p_player);
  update wolf_state set last_result = json_build_object('type', 'left',
      'deaths', json_build_array(json_build_object('name', pname(p_player), 'role', wolf_role_name(v_role))))
  where event_id = v_s.event_id;
  perform wolf_bump();
end $$;

-- Admin: abrir mesa → todos los presentes quedan sentados
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
      excluded = '{}', version = version + 1, updated_at = now()
  where event_id = v_event;
  perform wolf_sync_lobby();
  perform wolf_bump();
end $$;

create or replace function public.admin_wolf_set_narrator(p_narrator uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_s wolf_state%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_s from wolf_state where event_id = active_event_id();
  if v_s.status = 'playing' and exists (select 1 from wolf_seats where game_id = v_s.game_id and player_id = p_narrator) then
    raise exception 'Esa persona está jugando; no puede narrar';
  end if;
  update wolf_state set narrator_id = p_narrator where event_id = v_s.event_id;
  perform wolf_sync_lobby();   -- antes de repartir: el narrador nuevo sale de la mesa y el anterior entra
  perform wolf_bump();
end $$;

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
    'seats', (select coalesce(json_agg(json_build_object('id', s.player_id, 'name', pname(s.player_id),
                'alive', s.alive, 'away', p.away) order by pname(s.player_id)), '[]'::json)
              from wolf_seats s join players p on p.id = s.player_id where s.game_id = v_s.game_id),
    'benched', case when v_s.status in ('lobby', 'setup', 'playing') then wolf_benched_json() else '[]'::json end,
    'settings', json_build_object('win', coalesce(v_s.pts_win, 8), 'survive', coalesce(v_s.pts_survive, 2))
  );
end $$;

-- =====================================================================
-- IMPOSTOR
-- =====================================================================
create or replace function public.impostor_players_json(p_round uuid)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'id', p.id, 'name', coalesce(p.nickname, p.name), 'order', ip.speak_order, 'alive', ip.alive,
           'away', p.away,
           'role', case when not ip.alive or r.status = 'finished' then ip.role end)
         order by ip.speak_order), '[]'::json)
  from impostor_players ip
  join players p on p.id = ip.player_id
  join impostor_rounds r on r.id = ip.round_id
  where ip.round_id = p_round
$$;

create or replace function public.get_impostor_board()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     impostor_game%rowtype;
  v_r     impostor_rounds%rowtype;
begin
  select * into v_g from impostor_game where event_id = v_event;
  if v_g.current_round_id is not null then
    select * into v_r from impostor_rounds where id = v_g.current_round_id;
  end if;
  if v_r.id is null then return json_build_object('status', 'none'); end if;
  return json_build_object(
    'status', v_g.status,
    'number', v_r.number,
    'impostor_count', v_r.impostor_count,
    'players', impostor_players_json(v_r.id),
    'vote', json_build_object(
      'no', v_g.vote_no, 'kind', v_g.vote_kind, 'status', v_g.vote_status,
      'tally', case when v_g.vote_no > 0 then impostor_tally_json(v_r.id, v_g.vote_no) else '[]'::json end,
      'voted', (select count(*) from impostor_votes where round_id = v_r.id and vote_no = v_g.vote_no),
      'eligible', (select count(*) from impostor_players ip join players p on p.id = ip.player_id
                   where ip.round_id = v_r.id and ip.alive and not p.away)),
    'last_result', v_g.last_result,
    'winner', v_r.winner,
    'win_reason', v_r.win_reason,
    'word', case when v_r.status = 'finished' then v_r.word end
  );
end $$;

create or replace function public.vote_impostor(p_target uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      impostor_game%rowtype;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_g from impostor_game where event_id = v_event;
  if v_g.status <> 'playing' or v_g.vote_status <> 'open' then
    return json_build_object('ok', false, 'error', 'La votación no está abierta');
  end if;
  if is_away(v_player) then
    return json_build_object('ok', false, 'error', 'Estás ausente ⏸. Toca "Ya volví" para votar.');
  end if;
  if not exists (select 1 from impostor_players where round_id = v_g.current_round_id and player_id = v_player and alive) then
    return json_build_object('ok', false, 'error', 'Solo votan los jugadores que siguen en la ronda');
  end if;
  if p_target = v_player or not exists (select 1 from impostor_players
                                        where round_id = v_g.current_round_id and player_id = p_target and alive) then
    return json_build_object('ok', false, 'error', 'Elige a otro jugador que siga en la ronda');
  end if;
  if is_away(p_target) then return json_build_object('ok', false, 'error', 'Esa persona está ausente ⏸'); end if;

  insert into impostor_votes (round_id, vote_no, voter_id, target_id)
  values (v_g.current_round_id, v_g.vote_no, v_player, p_target)
  on conflict (round_id, vote_no, voter_id) do update set target_id = excluded.target_id, created_at = now();

  update impostor_game set updated_at = now() where event_id = v_event;
  return json_build_object('ok', true);
end $$;

-- Empezar: entran los elegidos que estén presentes (los ausentes entran en la siguiente ronda)
create or replace function public.admin_impostor_start(
  p_players uuid[], p_impostors integer, p_word text default null, p_hint text default null,
  p_category text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid;
  v_g      impostor_game%rowtype;
  v_n      integer;
  v_word   text;
  v_hint   text;
  v_round  uuid;
  v_number integer;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  select * into v_g from impostor_game where event_id = v_event for update;
  if v_g.status = 'playing' then raise exception 'Ya hay una ronda en juego. Termínala o cancélala.'; end if;

  select count(*) into v_n from players
  where id = any(p_players) and event_id = v_event and approved and not away;
  if v_n < 3 then raise exception 'Se necesitan al menos 3 jugadores presentes'; end if;
  if p_impostors < 1 or p_impostors * 2 >= v_n then
    raise exception 'Con % jugadores puede haber entre 1 y % impostores', v_n, greatest(1, (v_n - 1) / 2);
  end if;

  if coalesce(trim(p_word), '') <> '' then
    if coalesce(trim(p_hint), '') = '' then raise exception 'Escribe también la pista para los impostores'; end if;
    v_word := trim(p_word); v_hint := trim(p_hint);
  else
    select w.word,
           case when w.hint2 is not null and random() < 0.5 then w.hint2 else w.hint end
    into v_word, v_hint
    from impostor_words w
    where p_category is null or p_category = '' or w.category = p_category
    order by (exists (select 1 from impostor_rounds r where r.event_id = v_event and r.word = w.word)), random()
    limit 1;
    if v_word is null then raise exception 'No hay palabras en esa categoría'; end if;
  end if;

  select coalesce(max(number), 0) + 1 into v_number from impostor_rounds where event_id = v_event;
  insert into impostor_rounds (event_id, number, word, hint, impostor_count)
  values (v_event, v_number, v_word, v_hint, p_impostors)
  returning id into v_round;

  insert into impostor_players (round_id, player_id, role, speak_order)
  select v_round, x.id,
         case when x.imp_rank <= p_impostors then 'impostor' else 'crew' end,
         x.speak
  from (
    select p.id,
           row_number() over (order by random()) as imp_rank,
           row_number() over (order by random()) as speak
    from players p
    where p.id = any(p_players) and p.event_id = v_event and p.approved and not p.away
  ) x;

  update impostor_game
  set status = 'playing', current_round_id = v_round, vote_no = 0, vote_kind = 'defense', vote_status = 'none',
      last_result = null, updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'impostor', updated_at = now() where event_id = v_event;
end $$;

-- =====================================================================
-- ¿QUIÉN ES EL PERSONAJE? (no salen datos de ausentes)
-- =====================================================================
create or replace function public.admin_persona_start()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid;
  v_g      persona_game%rowtype;
  v_owner  uuid;
  v_fact   text;
  v_fact_id uuid;
  v_number integer;
  v_round  uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  select * into v_g from persona_game where event_id = v_event for update;
  if v_g.round_status = 'voting' then raise exception 'Ya hay una ronda en votación'; end if;

  select f.player_id, f.text, f.id into v_owner, v_fact, v_fact_id
  from persona_facts f join players p on p.id = f.player_id
  where f.event_id = v_event and p.approved and not p.away and not f.discarded and not persona_fact_used(f.id)
  order by random() limit 1;
  if v_owner is null then
    if exists (select 1 from persona_facts f join players p on p.id = f.player_id
               where f.event_id = v_event and p.approved and p.away and not f.discarded and not persona_fact_used(f.id)) then
      raise exception 'Solo quedan datos de personas ausentes ⏸. Espera a que vuelvan.';
    end if;
    raise exception 'No quedan datos curiosos sin usar 🤷';
  end if;

  select coalesce(max(number), 0) + 1 into v_number from persona_rounds where event_id = v_event;
  insert into persona_rounds (event_id, number, owner_id, fact_id, fact, ends_at)
  values (v_event, v_number, v_owner, v_fact_id, v_fact, now() + make_interval(secs => v_g.seconds))
  returning id into v_round;

  update persona_game
  set current_round_id = v_round, round_status = 'voting',
      ends_at = now() + make_interval(secs => v_g.seconds), votes_count = 0, updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'persona', updated_at = now() where event_id = v_event;
end $$;

-- =====================================================================
-- EL REGALO LOCO: temporizador + reasignar partes
-- (quien escribe el objeto puede ser distinto de quien "regala": object_writer_id)
-- =====================================================================
create or replace function public.gift_podium_json(p_round uuid, p_step integer)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'place', c.place, 'phrase', c.phrase, 'votes', c.votes,
           'authors', json_build_array(pname(coalesce(c.object_writer_id, c.giver_id)), pname(c.use_writer_id), pname(c.reaction_writer_id)))
         order by c.place), '[]'::json)
  from gift_chains c
  where c.round_id = p_round and c.place is not null and c.place <= 3 and c.place >= 4 - p_step and c.votes > 0
$$;

-- Mis tareas de escritura (normalmente 3; más si el admin me pasó partes de alguien)
create or replace function public.gift_my_tasks(p_round uuid, p_player uuid)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('chain', t.chain, 'part', t.part, 'text', t.txt, 'recipient', t.recipient)
                           order by t.ord, t.chain), '[]'::json)
  from (
    select c.id as chain, 'object' as part, 1 as ord, c.object_text as txt, pname(c.recipient_id) as recipient
    from gift_chains c where c.round_id = p_round and coalesce(c.object_writer_id, c.giver_id) = p_player
    union all
    select c.id, 'use', 2, c.use_text, null from gift_chains c where c.round_id = p_round and c.use_writer_id = p_player
    union all
    select c.id, 'reaction', 3, c.reaction_text, null from gift_chains c where c.round_id = p_round and c.reaction_writer_id = p_player
  ) t
$$;

create or replace function public.get_gift_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      gift_game%rowtype;
  v_tasks  json;
begin
  select * into v_g from gift_game where event_id = v_event;
  if v_g.status is null or v_g.status = 'none' or v_g.current_round_id is null then
    return json_build_object('status', 'none');
  end if;
  v_tasks := gift_my_tasks(v_g.current_round_id, v_player);

  return json_build_object(
    'status', v_g.status,
    'round_id', v_g.current_round_id,
    'now', now(),
    'ends_at', case when v_g.status = 'writing' then v_g.ends_at end,
    'participant', json_array_length(v_tasks) > 0 or exists (
                     select 1 from gift_chains where round_id = v_g.current_round_id and giver_id = v_player),
    'tasks', v_tasks,
    'progress', json_build_object('done', v_g.parts_done, 'total', v_g.parts_total),
    'phrases', case when v_g.status in ('voting', 'results') then
                 (select coalesce(json_agg(json_build_object(
                     'id', c.id, 'n', c.read_order, 'phrase', c.phrase,
                     'mine', v_player in (coalesce(c.object_writer_id, c.giver_id), c.use_writer_id, c.reaction_writer_id))
                     order by c.read_order), '[]'::json)
                  from gift_chains c where c.round_id = v_g.current_round_id) end,
    'my_votes', (select coalesce(json_agg(chain_id), '[]'::json) from gift_votes
                 where round_id = v_g.current_round_id and voter_id = v_player),
    'podium', case when v_g.status = 'results' then gift_podium_json(v_g.current_round_id, v_g.reveal_step) end
  );
end $$;

-- Guardar una parte concreta (cadena + parte)
create or replace function public.save_gift_text(p_chain uuid, p_part text, p_text text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      gift_game%rowtype;
  v_txt    text := nullif(trim(coalesce(p_text, '')), '');
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_g from gift_game where event_id = v_event;
  if v_g.status is distinct from 'writing' then
    return json_build_object('ok', false, 'error', 'Ya no se puede escribir ⏰');
  end if;
  if v_g.ends_at is not null and now() > v_g.ends_at + interval '3 seconds' then
    return json_build_object('ok', false, 'error', '¡Se acabó el tiempo! ⏰');
  end if;
  if char_length(coalesce(v_txt, '')) > 80 then return json_build_object('ok', false, 'error', 'Máximo 80 caracteres'); end if;

  if p_part = 'object' then
    update gift_chains set object_text = v_txt
    where id = p_chain and round_id = v_g.current_round_id and coalesce(object_writer_id, giver_id) = v_player;
  elsif p_part = 'use' then
    update gift_chains set use_text = v_txt where id = p_chain and round_id = v_g.current_round_id and use_writer_id = v_player;
  elsif p_part = 'reaction' then
    update gift_chains set reaction_text = v_txt where id = p_chain and round_id = v_g.current_round_id and reaction_writer_id = v_player;
  else
    raise exception 'Parte inválida';
  end if;
  if not found then return json_build_object('ok', false, 'error', 'Esa parte ya no es tuya'); end if;

  perform gift_refresh_progress(v_g.current_round_id);
  return json_build_object('ok', true);
end $$;

-- Versión anterior (por si algún celular tiene la app vieja abierta)
create or replace function public.save_gift_part(p_part text, p_text text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_player uuid := current_player_id();
  v_chain  uuid;
begin
  select c.id into v_chain from gift_chains c join gift_game g on g.current_round_id = c.round_id
  where g.event_id = active_event_id()
    and ((p_part = 'object' and coalesce(c.object_writer_id, c.giver_id) = v_player)
      or (p_part = 'use' and c.use_writer_id = v_player)
      or (p_part = 'reaction' and c.reaction_writer_id = v_player))
  limit 1;
  return save_gift_text(v_chain, p_part, p_text);
end $$;

create or replace function public.vote_gift(p_chains uuid[])
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      gift_game%rowtype;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_g from gift_game where event_id = v_event;
  if v_g.status is distinct from 'voting' then return json_build_object('ok', false, 'error', 'La votación no está abierta'); end if;
  if coalesce(cardinality(p_chains), 0) > 3 then return json_build_object('ok', false, 'error', 'Máximo 3 frases'); end if;

  delete from gift_votes where round_id = v_g.current_round_id and voter_id = v_player;
  insert into gift_votes (round_id, voter_id, chain_id)
  select distinct v_g.current_round_id, v_player, c.id
  from gift_chains c
  where c.round_id = v_g.current_round_id and c.id = any(p_chains)
    and v_player not in (coalesce(c.object_writer_id, c.giver_id), c.use_writer_id, c.reaction_writer_id);

  perform gift_refresh_progress(v_g.current_round_id);
  return json_build_object('ok', true);
end $$;

create or replace function public.get_gift_board()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_g gift_game%rowtype;
begin
  select * into v_g from gift_game where event_id = active_event_id();
  if v_g.status is null or v_g.status = 'none' or v_g.current_round_id is null then
    return json_build_object('status', 'none');
  end if;
  return json_build_object(
    'status', v_g.status,
    'now', now(),
    'ends_at', case when v_g.status = 'writing' then v_g.ends_at end,
    'number', (select number from gift_rounds where id = v_g.current_round_id),
    'progress', json_build_object('done', v_g.parts_done, 'total', v_g.parts_total),
    'players', (select count(*) from gift_chains where round_id = v_g.current_round_id),
    'voters_done', v_g.voters_done,
    'read_index', v_g.read_index,
    'current', case when v_g.status = 'reading' then
                 (select json_build_object('n', c.read_order, 'phrase', c.phrase)
                  from gift_chains c where c.round_id = v_g.current_round_id and c.read_order = v_g.read_index) end,
    'phrases', case when v_g.status = 'voting' then gift_phrases_json(v_g.current_round_id) end,
    'reveal_step', v_g.reveal_step,
    'podium', case when v_g.status = 'results' then gift_podium_json(v_g.current_round_id, v_g.reveal_step) end
  );
end $$;

create or replace function public.admin_gift_overview()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     gift_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from gift_game where event_id = v_event;
  return json_build_object(
    'status', coalesce(v_g.status, 'none'),
    'now', now(),
    'ends_at', case when v_g.status = 'writing' then v_g.ends_at end,
    'settings', json_build_object('p1', coalesce(v_g.pts_1, 10), 'p2', coalesce(v_g.pts_2, 6), 'p3', coalesce(v_g.pts_3, 4),
                                  'seconds', coalesce(v_g.writing_seconds, 30)),
    'read_index', v_g.read_index,
    'reveal_step', v_g.reveal_step,
    'progress', json_build_object('done', v_g.parts_done, 'total', v_g.parts_total),
    'voters_done', v_g.voters_done,
    'count', (select count(*) from gift_chains where round_id = v_g.current_round_id),
    -- Quién no ha terminado (sin revelar QUÉ escribió) y cuántas partes le faltan
    'missing', (select coalesce(json_agg(json_build_object('id', x.pid, 'name', pname(x.pid), 'parts', x.n,
                                                           'away', is_away(x.pid)) order by pname(x.pid)), '[]'::json) from (
                  select p.pid, count(*) as n from (
                    select coalesce(object_writer_id, giver_id) as pid from gift_chains where round_id = v_g.current_round_id and object_text is null
                    union all select use_writer_id from gift_chains where round_id = v_g.current_round_id and use_text is null
                    union all select reaction_writer_id from gift_chains where round_id = v_g.current_round_id and reaction_text is null) p
                  group by p.pid) x),
    'current', (select json_build_object('n', c.read_order, 'phrase', c.phrase)
                from gift_chains c where c.round_id = v_g.current_round_id and c.read_order = v_g.read_index),
    'results', (select coalesce(json_agg(json_build_object('place', c.place, 'votes', c.votes, 'tied', c.tied, 'phrase', c.phrase,
                   'authors', json_build_array(pname(coalesce(c.object_writer_id, c.giver_id)), pname(c.use_writer_id), pname(c.reaction_writer_id)))
                   order by c.place), '[]'::json)
                from gift_chains c where c.round_id = v_g.current_round_id and c.place is not null and c.place <= 5)
  );
end $$;

-- Tiempo para escribir (segundos). 0 = sin temporizador.
create or replace function public.admin_gift_timer(p_seconds integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_seconds <> 0 and p_seconds not between 10 and 600 then raise exception 'Entre 10 y 600 segundos (0 = sin tiempo)'; end if;
  v_event := ensure_event_rows();
  update gift_game set writing_seconds = p_seconds, updated_at = now() where event_id = v_event;
end $$;

-- Sumar (o quitar) tiempo a la escritura en curso
create or replace function public.admin_gift_add_time(p_seconds integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  update gift_game
  set ends_at = greatest(coalesce(ends_at, now()), now()) + make_interval(secs => p_seconds), updated_at = now()
  where event_id = active_event_id() and status = 'writing';
  if not found then raise exception 'No se está escribiendo'; end if;
end $$;

create or replace function public.admin_gift_start(p_players uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid;
  v_g      gift_game%rowtype;
  v_ids    uuid[];
  v_n      integer;
  v_round  uuid;
  v_number integer;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  select * into v_g from gift_game where event_id = v_event for update;
  if v_g.status in ('writing', 'reading', 'voting') then raise exception 'Ya hay un Regalo Loco en curso'; end if;

  select array_agg(id order by random()) into v_ids
  from players where id = any(p_players) and event_id = v_event and approved and not away;
  v_n := coalesce(cardinality(v_ids), 0);
  if v_n < 4 then raise exception 'Se necesitan al menos 4 jugadores presentes'; end if;

  select coalesce(max(number), 0) + 1 into v_number from gift_rounds where event_id = v_event;
  insert into gift_rounds (event_id, number) values (v_event, v_number) returning id into v_round;

  insert into gift_chains (round_id, read_order, giver_id, recipient_id, use_writer_id, reaction_writer_id)
  select v_round, row_number() over (order by random()),
         v_ids[i], v_ids[(i % v_n) + 1], v_ids[((i + 1) % v_n) + 1], v_ids[((i + 2) % v_n) + 1]
  from generate_series(1, v_n) as i;

  update gift_game
  set status = 'writing', current_round_id = v_round, read_index = 0, reveal_step = 0,
      parts_done = 0, parts_total = v_n * 3, voters_done = 0,
      ends_at = case when writing_seconds > 0 then now() + make_interval(secs => writing_seconds) end,
      updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'gift', updated_at = now() where event_id = v_event;
end $$;

-- Pasar las partes sin escribir de una persona a otra
create or replace function public.admin_gift_reassign(p_from uuid, p_to uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_g gift_game%rowtype;
  v_n integer := 0;
  v_k integer;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_from = p_to then raise exception 'Elige a otra persona'; end if;
  if not exists (select 1 from players where id = p_to and event_id = active_event_id() and approved) then
    raise exception 'Elige a quién se le pasan las partes';
  end if;
  select * into v_g from gift_game where event_id = active_event_id() for update;
  if v_g.status <> 'writing' then raise exception 'No se está escribiendo'; end if;

  update gift_chains set object_writer_id = p_to
  where round_id = v_g.current_round_id and object_text is null and coalesce(object_writer_id, giver_id) = p_from;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  update gift_chains set use_writer_id = p_to
  where round_id = v_g.current_round_id and use_text is null and use_writer_id = p_from;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  update gift_chains set reaction_writer_id = p_to
  where round_id = v_g.current_round_id and reaction_text is null and reaction_writer_id = p_from;
  get diagnostics v_k = row_count; v_n := v_n + v_k;

  -- Darle al menos 20 s para escribir
  update gift_game set ends_at = greatest(ends_at, now() + interval '20 seconds'), updated_at = now()
  where event_id = v_g.event_id and ends_at is not null;
  return json_build_object('ok', true, 'moved', v_n);
end $$;

-- Cerrar la escritura (interno): arma las frases (lo que falte se rellena) y pasa a lectura
create or replace function public.gift_do_close_writing()
returns void language plpgsql security definer set search_path = public as $$
declare v_g gift_game%rowtype;
begin
  select * into v_g from gift_game where event_id = active_event_id() for update;
  if v_g.status <> 'writing' then return; end if;

  update gift_chains c set phrase =
    pname(c.giver_id) || ' le regaló a ' || pname(c.recipient_id) || ' ' ||
    coalesce(c.object_text, (array['un regalo misterioso', 'una caja vacía', 'un calcetín sin par'])[1 + floor(random() * 3)::int]) ||
    ', que sirve para ' ||
    coalesce(c.use_text, (array['nada en absoluto', 'decorar el baño', 'molestar a los vecinos'])[1 + floor(random() * 3)::int]) ||
    ', y al recibirlo exclamó: «' ||
    coalesce(c.reaction_text, (array['…¿gracias?', '¡No puede ser!', '¡Justo lo que necesitaba!'])[1 + floor(random() * 3)::int]) || '»'
  where c.round_id = v_g.current_round_id;

  update gift_game set status = 'reading', read_index = 1, ends_at = null, updated_at = now() where event_id = v_g.event_id;
end $$;

create or replace function public.admin_gift_close_writing()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if (select status from gift_game where event_id = active_event_id()) <> 'writing' then raise exception 'No se está escribiendo'; end if;
  perform gift_do_close_writing();
end $$;

-- Cualquier celular la llama cuando su cuenta regresiva llega a 0: solo cierra si de verdad se acabó el tiempo
create or replace function public.gift_tick()
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from gift_game where event_id = active_event_id() and status = 'writing'
             and ends_at is not null and now() >= ends_at + interval '2 seconds') then
    perform gift_do_close_writing();
  end if;
end $$;

-- Cerrar votación (los autores ahora incluyen a quien escribió el objeto)
create or replace function public.admin_gift_close_vote()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     gift_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from gift_game where event_id = v_event for update;
  if v_g.status <> 'voting' then raise exception 'La votación no está abierta'; end if;

  update gift_chains c set votes = (select count(*) from gift_votes v where v.chain_id = c.id)
  where c.round_id = v_g.current_round_id;

  with ranked as (
    select id, votes,
           row_number() over (order by votes desc, random()) as place,
           count(*) over (partition by votes) as same
    from gift_chains where round_id = v_g.current_round_id
  )
  update gift_chains c set place = r.place, tied = r.same > 1 and r.place <= 3
  from ranked r where r.id = c.id;

  insert into points_ledger (event_id, player_id, source, points, reason, visible)
  select v_event, a.pid, 'regalo',
         case c.place when 1 then v_g.pts_1 when 2 then v_g.pts_2 else v_g.pts_3 end,
         'Regalo Loco: frase en ' || c.place || '.º lugar', false
  from gift_chains c
  cross join lateral (select distinct v.pid from (values (coalesce(c.object_writer_id, c.giver_id)), (c.use_writer_id), (c.reaction_writer_id)) as v(pid)) as a
  where c.round_id = v_g.current_round_id and c.place <= 3 and c.votes > 0
    and (case c.place when 1 then v_g.pts_1 when 2 then v_g.pts_2 else v_g.pts_3 end) <> 0;

  update gift_game set status = 'results', reveal_step = 0, updated_at = now() where event_id = v_event;
  update gift_rounds set status = 'finished' where id = v_g.current_round_id;
end $$;

-- =====================================================================
-- PESTAÑAS: qué juegos están activos para mí (y si me toca hacer algo)
-- =====================================================================
create or replace function public.get_my_games()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_c      text;
  v_h      text;
  v_p      persona_game%rowtype;
  v_pr     persona_rounds%rowtype;
  v_i      impostor_game%rowtype;
  v_g      gift_game%rowtype;
  v_w      wolf_state%rowtype;
  v_wv     json;
  v_games  json[] := '{}';
  v_att    boolean;
  v_act    text;
begin
  if v_player is null then return json_build_object('away', false, 'games', '[]'::json); end if;

  -- 🐺 Hombre Lobo
  select * into v_w from wolf_state where event_id = v_event;
  if v_w.status in ('lobby', 'setup', 'playing', 'finished') and v_w.game_id is not null then
    v_wv := wolf_my_view();
    v_act := v_wv->>'action';
    v_att := v_w.status = 'playing' and v_w.narrator_id is distinct from v_player and (
               (coalesce((v_wv->>'joined')::boolean, false) and not coalesce((v_wv->>'card_seen')::boolean, true))
               or (v_act in ('wolf', 'seer', 'mayor', 'vote', 'shoot', 'successor') and (v_wv->'my_choice'->>v_act) is null)
               or v_act = 'witch');
    v_games := v_games || json_build_object('id', 'wolf', 'key', 'wolf:' || v_w.game_id, 'status', v_w.status,
                 'narrator', v_w.narrator_id = v_player, 'attention', coalesce(v_att, false),
                 'live', v_w.status <> 'finished');
  end if;

  -- 🎁 Regalo Loco
  select * into v_g from gift_game where event_id = v_event;
  if v_g.status is not null and v_g.status <> 'none' and v_g.current_round_id is not null then
    v_att := (v_g.status = 'writing' and exists (
                select 1 from gift_chains c where c.round_id = v_g.current_round_id and (
                  (coalesce(c.object_writer_id, c.giver_id) = v_player and c.object_text is null)
                  or (c.use_writer_id = v_player and c.use_text is null)
                  or (c.reaction_writer_id = v_player and c.reaction_text is null))))
          or (v_g.status = 'voting' and not exists (
                select 1 from gift_votes where round_id = v_g.current_round_id and voter_id = v_player));
    v_games := v_games || json_build_object('id', 'gift', 'key', 'gift:' || v_g.current_round_id, 'status', v_g.status,
                 'attention', v_att, 'live', v_g.status <> 'results');
  end if;

  -- 🃏 Impostor
  select * into v_i from impostor_game where event_id = v_event;
  if v_i.status in ('playing', 'finished') and v_i.current_round_id is not null then
    v_att := v_i.status = 'playing' and v_i.vote_status = 'open' and not is_away(v_player)
             and exists (select 1 from impostor_players where round_id = v_i.current_round_id and player_id = v_player and alive)
             and not exists (select 1 from impostor_votes where round_id = v_i.current_round_id and vote_no = v_i.vote_no and voter_id = v_player);
    v_games := v_games || json_build_object('id', 'impostor', 'key', 'impostor:' || v_i.current_round_id, 'status', v_i.status,
                 'attention', v_att, 'live', v_i.status = 'playing');
  end if;

  -- 🕵️ ¿Quién es el personaje?
  select * into v_p from persona_game where event_id = v_event;
  if v_p.round_status in ('voting', 'revealed') and v_p.current_round_id is not null then
    select * into v_pr from persona_rounds where id = v_p.current_round_id;
    v_att := v_p.round_status = 'voting' and v_pr.owner_id <> v_player and now() < v_pr.ends_at
             and not exists (select 1 from persona_votes where round_id = v_pr.id and voter_id = v_player);
    v_games := v_games || json_build_object('id', 'persona', 'key', 'persona:' || v_p.current_round_id, 'status', v_p.round_status,
                 'attention', v_att, 'live', v_p.round_status = 'voting');
  end if;

  -- 🔍 Caza de códigos
  select status into v_h from code_hunt where event_id = v_event;
  if v_h = 'open' then
    v_games := v_games || json_build_object('id', 'codes', 'key', 'codes:open', 'status', v_h, 'attention', false, 'live', true);
  end if;

  -- 🎭 Disfraces
  select status into v_c from costume_contest where event_id = v_event;
  if v_c = 'open' then
    v_games := v_games || json_build_object('id', 'costume', 'key', 'costume:open', 'status', v_c,
                 'attention', not exists (select 1 from costume_ballots where voter_id = v_player), 'live', true);
  end if;

  return json_build_object('away', is_away(v_player), 'games', to_json(v_games));
end $$;

-- =====================================================================
-- REINICIO: también limpia "ausente"
-- =====================================================================
create or replace function public.admin_reset(p_scope text, p_confirm text, p_event_name text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_confirm is distinct from 'BORRAR' then raise exception 'Confirmación incorrecta'; end if;
  if p_scope not in ('points', 'all') then raise exception 'Opción inválida'; end if;
  v_event := ensure_event_rows();

  delete from points_ledger   where event_id = v_event;
  delete from costume_ballots where event_id = v_event;
  delete from costume_results where event_id = v_event;
  update costume_contest
  set status = 'not_started', reveal_step = 0, opened_at = null, closed_at = null, updated_at = now()
  where event_id = v_event;
  delete from hunt_claims where event_id = v_event;
  delete from hunt_failed where player_id in (select id from players where event_id = v_event);
  update code_hunt set status = 'not_started', updated_at = now() where event_id = v_event;
  delete from persona_rounds where event_id = v_event;
  update persona_game
  set current_round_id = null, round_status = 'none', ends_at = null, votes_count = 0, updated_at = now()
  where event_id = v_event;
  delete from impostor_rounds where event_id = v_event;
  update impostor_game
  set status = 'none', current_round_id = null, vote_no = 0, vote_status = 'none', last_result = null, updated_at = now()
  where event_id = v_event;
  delete from gift_rounds where event_id = v_event;
  update gift_game
  set status = 'none', current_round_id = null, read_index = 0, reveal_step = 0, ends_at = null,
      parts_done = 0, parts_total = 0, voters_done = 0, updated_at = now()
  where event_id = v_event;
  delete from wolf_actions where event_id = v_event;
  delete from wolf_seats where event_id = v_event;
  update wolf_state set status = 'none', phase = null, game_id = null, narrator_id = null, ends_at = null,
    last_result = null, winner = null, excluded = '{}', version = version + 1, updated_at = now()
  where event_id = v_event;
  update players set away = false, away_since = null where event_id = v_event and away;
  update dashboard_state set mode = 'leaderboard', frozen_at = null, updated_at = now() where event_id = v_event;

  if p_scope = 'all' then
    delete from players where event_id = v_event and not is_admin;
    if coalesce(trim(p_event_name), '') <> '' then
      update events set name = trim(p_event_name) where id = v_event;
    end if;
  end if;
end $$;

grant execute on all functions in schema public to anon, authenticated;

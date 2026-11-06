-- =====================================================================
-- Party Games App · Fase 4: ¿Quién es el personaje?
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1, 2 y 3.
-- =====================================================================

-- =====================================================================
-- TABLAS
-- =====================================================================

-- Configuración + ronda actual (público: NO contiene al dueño del dato)
create table if not exists public.persona_game (
  event_id           uuid primary key references public.events(id) on delete cascade,
  seconds            integer not null default 30,
  pts_correct        integer not null default 5,   -- por adivinar
  pts_owner_per_miss integer not null default 2,   -- (ya no se usa; reemplazado por owner_bonus)
  owner_cap          integer not null default 10,  -- (ya no se usa)
  owner_bonus        integer not null default 5,   -- al dueño cuando su dato sale; x2 si no lo atrapan
  current_round_id   uuid,
  round_status       text not null default 'none' check (round_status in ('none', 'voting', 'revealed')),
  ends_at            timestamptz,
  votes_count        integer not null default 0,
  updated_at         timestamptz not null default now()
);

-- Datos curiosos (cada invitado puede tener varios). PRIVADO.
create table if not exists public.persona_facts (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  text       text not null check (char_length(text) between 1 and 200),
  discarded  boolean not null default false,   -- el admin lo descartó (no vuelve a salir)
  created_at timestamptz not null default now()
);
create index if not exists persona_facts_player_idx on public.persona_facts (player_id);

-- Migración: los datos escritos en el registro (fase 1) pasan a esta tabla, sin duplicar
insert into public.persona_facts (event_id, player_id, text)
select p.event_id, p.id, trim(s.fun_fact)
from public.player_secrets s
join public.players p on p.id = s.player_id
where s.fun_fact_opt_in and coalesce(trim(s.fun_fact), '') <> ''
  and not exists (select 1 from public.persona_facts f where f.player_id = p.id and f.text = trim(s.fun_fact));

-- Rondas. PRIVADO (tiene al dueño del dato).
create table if not exists public.persona_rounds (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  number      integer not null,
  owner_id    uuid not null references public.players(id) on delete cascade,
  fact_id     uuid references public.persona_facts(id) on delete set null,
  fact        text not null,
  status      text not null default 'voting' check (status in ('voting', 'revealed', 'cancelled')),
  started_at  timestamptz not null default now(),
  ends_at     timestamptz not null,
  revealed_at timestamptz
);
create index if not exists persona_rounds_event_idx on public.persona_rounds (event_id, number);

-- Votos. PRIVADO.
create table if not exists public.persona_votes (
  round_id   uuid not null references public.persona_rounds(id) on delete cascade,
  voter_id   uuid not null references public.players(id) on delete cascade,
  guess_id   uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (round_id, voter_id)
);

-- Columnas nuevas (por si el archivo ya se había corrido antes)
alter table public.persona_game   add column if not exists owner_bonus  integer not null default 5;
alter table public.persona_rounds add column if not exists owner_points integer;
alter table public.persona_rounds add column if not exists caught       boolean;

insert into public.persona_game (event_id) select id from public.events on conflict do nothing;

-- =====================================================================
-- SEGURIDAD
-- =====================================================================
alter table public.persona_game   enable row level security;
alter table public.persona_rounds enable row level security;
alter table public.persona_votes  enable row level security;
alter table public.persona_facts  enable row level security;

drop policy if exists "persona: lectura pública" on public.persona_game;
create policy "persona: lectura pública" on public.persona_game for select to anon, authenticated using (true);
-- persona_rounds, persona_votes y persona_facts: sin políticas → solo vía funciones

grant select on public.persona_game to anon, authenticated;

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
  return v_event;
end $$;

-- ¿Ya salió este dato en una ronda (no cancelada)?
create or replace function public.persona_fact_used(p_fact uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from persona_rounds where fact_id = p_fact and status <> 'cancelled')
$$;

-- Registro (redefinido): el dato escrito al registrarse también entra al juego
create or replace function public.register_player(
  p_name text,
  p_nickname text,
  p_has_costume boolean,
  p_costume text,
  p_fun_fact text,
  p_fun_fact_opt_in boolean
) returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid;
begin
  if auth.uid() is null then raise exception 'No hay sesión en este dispositivo'; end if;
  if v_event is null then raise exception 'No hay una fiesta activa'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  if coalesce(p_has_costume, false) and coalesce(trim(p_costume), '') = '' then
    raise exception 'Cuéntanos de qué vienes disfrazado';
  end if;
  if char_length(coalesce(p_fun_fact, '')) > 200 then raise exception 'El dato curioso admite máximo 200 caracteres'; end if;
  if exists (select 1 from player_devices where auth_user_id = auth.uid()) then
    raise exception 'Este dispositivo ya está registrado';
  end if;
  if exists (select 1 from players
             where event_id = v_event and lower(trim(name)) = lower(trim(p_name))) then
    raise exception 'Ya hay alguien con ese nombre. Si eres tú, usa "Ya tengo perfil"; si no, agrega tu apellido.';
  end if;

  insert into players (event_id, name, nickname, has_costume, costume)
  values (v_event, trim(p_name), nullif(trim(p_nickname), ''), coalesce(p_has_costume, false),
          case when p_has_costume then nullif(trim(p_costume), '') end)
  returning id into v_player;

  insert into player_secrets (player_id, fun_fact, fun_fact_opt_in)
  values (v_player, nullif(trim(p_fun_fact), ''), coalesce(p_fun_fact_opt_in, false));

  if coalesce(p_fun_fact_opt_in, false) and coalesce(trim(p_fun_fact), '') <> '' then
    insert into persona_facts (event_id, player_id, text) values (v_event, v_player, trim(p_fun_fact));
  end if;

  insert into player_devices (player_id, auth_user_id, kind)
  values (v_player, auth.uid(), 'register');

  return my_status();
end $$;

-- Resultado de una ronda revelada (sirve para invitados, pantalla y admin)
create or replace function public.persona_result_json(p_round uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'owner', (select json_build_object('id', p.id, 'name', p.name, 'nickname', p.nickname, 'costume', p.costume)
              from persona_rounds r join players p on p.id = r.owner_id where r.id = p_round),
    'owner_points', (select owner_points from persona_rounds where id = p_round),
    'caught', (select caught from persona_rounds where id = p_round),
    'total', (select count(*) from persona_votes where round_id = p_round),
    'correct', (select count(*) from persona_votes v join persona_rounds r on r.id = v.round_id
                where v.round_id = p_round and v.guess_id = r.owner_id),
    'distribution', (select coalesce(json_agg(d order by d.votes desc, d.name), '[]'::json) from (
                       select coalesce(p.nickname, p.name) as name, count(*) as votes,
                              (v.guess_id = r.owner_id) as correct
                       from persona_votes v
                       join persona_rounds r on r.id = v.round_id
                       join players p on p.id = v.guess_id
                       where v.round_id = p_round
                       group by p.id, p.nickname, p.name, v.guess_id, r.owner_id
                       order by count(*) desc limit 8) d)
  )
$$;

-- =====================================================================
-- RPC: INVITADOS
-- =====================================================================

-- Mis datos curiosos: agregar (máx. 2), editar o borrar (solo los que no han salido)
create or replace function public.add_my_fact(p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v_player uuid := current_player_id();
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  if coalesce(trim(p_text), '') = '' then raise exception 'Escribe tu dato'; end if;
  if char_length(p_text) > 200 then raise exception 'Máximo 200 caracteres'; end if;
  if (select count(*) from persona_facts where player_id = v_player) >= 2 then
    raise exception 'Máximo 2 datos por persona';
  end if;
  insert into persona_facts (event_id, player_id, text) values (active_event_id(), v_player, trim(p_text));
end $$;

create or replace function public.update_my_fact(p_fact_id uuid, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare v_player uuid := current_player_id();
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  if coalesce(trim(p_text), '') = '' then raise exception 'Escribe tu dato'; end if;
  if char_length(p_text) > 200 then raise exception 'Máximo 200 caracteres'; end if;
  if persona_fact_used(p_fact_id) then raise exception 'Ese dato ya salió en el juego 😄'; end if;
  update persona_facts set text = trim(p_text) where id = p_fact_id and player_id = v_player;
end $$;

create or replace function public.delete_my_fact(p_fact_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_player uuid := current_player_id();
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  if persona_fact_used(p_fact_id) then raise exception 'Ese dato ya salió en el juego 😄'; end if;
  delete from persona_facts where id = p_fact_id and player_id = v_player;
end $$;

-- Todo lo que necesita el celular del invitado
create or replace function public.get_persona_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      persona_game%rowtype;
  v_r      persona_rounds%rowtype;
  v_vote   uuid;
  v_round  json := null;
begin
  select * into v_g from persona_game where event_id = v_event;
  if v_g.current_round_id is not null and v_g.round_status <> 'none' then
    select * into v_r from persona_rounds where id = v_g.current_round_id;
  end if;
  if v_r.id is not null then
    select guess_id into v_vote from persona_votes where round_id = v_r.id and voter_id = v_player;
    v_round := json_build_object(
      'id', v_r.id, 'number', v_r.number, 'status', v_r.status, 'fact', v_r.fact, 'ends_at', v_r.ends_at,
      'is_owner', v_r.owner_id = v_player,
      'my_vote', v_vote,
      'result', case when v_r.status = 'revealed' then persona_result_json(v_r.id) end,
      'my_correct', case when v_r.status = 'revealed' then v_vote is not null and v_vote = v_r.owner_id end
    );
  end if;

  return json_build_object(
    'now', now(),
    'settings', json_build_object('seconds', coalesce(v_g.seconds, 30), 'correct', coalesce(v_g.pts_correct, 5),
                                  'bonus', coalesce(v_g.owner_bonus, 5)),
    'round', v_round,
    'candidates', (select coalesce(json_agg(json_build_object('id', p.id, 'name', p.name, 'nickname', p.nickname)
                                            order by p.name), '[]'::json)
                   from players p where p.event_id = v_event and p.approved and p.id is distinct from v_player),
    'my_facts', (select coalesce(json_agg(json_build_object('id', f.id, 'text', f.text,
                                  'used', persona_fact_used(f.id)) order by f.created_at), '[]'::json)
                 from persona_facts f where f.player_id = v_player)
  );
end $$;

-- Votar (se puede cambiar el voto hasta que se acabe el tiempo)
create or replace function public.vote_persona(p_guess uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      persona_game%rowtype;
  v_r      persona_rounds%rowtype;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_g from persona_game where event_id = v_event;
  select * into v_r from persona_rounds where id = v_g.current_round_id;
  if v_r.id is null or v_r.status <> 'voting' then
    return json_build_object('ok', false, 'error', 'No hay una ronda en votación');
  end if;
  if now() > v_r.ends_at + interval '2 seconds' then
    return json_build_object('ok', false, 'error', '¡Se acabó el tiempo! ⏰');
  end if;
  if v_r.owner_id = v_player then
    return json_build_object('ok', false, 'error', '¡Es tu dato! No puedes votar 🤫');
  end if;
  if p_guess = v_player or not exists (select 1 from players where id = p_guess and event_id = v_event and approved) then
    return json_build_object('ok', false, 'error', 'Elige a otro invitado');
  end if;

  insert into persona_votes (round_id, voter_id, guess_id) values (v_r.id, v_player, p_guess)
  on conflict (round_id, voter_id) do update set guess_id = excluded.guess_id, created_at = now();

  update persona_game
  set votes_count = (select count(*) from persona_votes where round_id = v_r.id), updated_at = now()
  where event_id = v_event;

  return json_build_object('ok', true);
end $$;

-- Pantalla (público)
create or replace function public.get_persona_board()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     persona_game%rowtype;
  v_r     persona_rounds%rowtype;
begin
  select * into v_g from persona_game where event_id = v_event;
  if v_g.current_round_id is not null and v_g.round_status <> 'none' then
    select * into v_r from persona_rounds where id = v_g.current_round_id;
  end if;
  return json_build_object(
    'now', now(),
    'status', coalesce(v_g.round_status, 'none'),
    'rounds_done', (select count(*) from persona_rounds where event_id = v_event and status = 'revealed'),
    'round', case when v_r.id is null then null else json_build_object(
               'number', v_r.number, 'fact', v_r.fact, 'ends_at', v_r.ends_at, 'status', v_r.status,
               'votes', v_g.votes_count,
               'result', case when v_r.status = 'revealed' then persona_result_json(v_r.id) end) end
  );
end $$;

-- =====================================================================
-- RPC: ADMIN
-- =====================================================================

create or replace function public.admin_persona_overview()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     persona_game%rowtype;
  v_r     persona_rounds%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from persona_game where event_id = v_event;
  if v_g.current_round_id is not null and v_g.round_status <> 'none' then
    select * into v_r from persona_rounds where id = v_g.current_round_id;
  end if;
  return json_build_object(
    'now', now(),
    'settings', json_build_object('seconds', coalesce(v_g.seconds, 30), 'correct', coalesce(v_g.pts_correct, 5),
                                  'bonus', coalesce(v_g.owner_bonus, 5)),
    'pool', json_build_object(
      'with_fact', (select count(distinct f.player_id) from persona_facts f join players p on p.id = f.player_id
                    where f.event_id = v_event and p.approved and not f.discarded),
      'facts',     (select count(*) from persona_facts f join players p on p.id = f.player_id
                    where f.event_id = v_event and p.approved and not f.discarded),
      'available', (select count(*) from persona_facts f join players p on p.id = f.player_id
                    where f.event_id = v_event and p.approved and not f.discarded and not persona_fact_used(f.id)),
      'players', (select count(*) from players where event_id = v_event and approved)),
    'round', case when v_r.id is null then null else json_build_object(
               'id', v_r.id, 'number', v_r.number, 'fact', v_r.fact, 'status', v_r.status, 'ends_at', v_r.ends_at,
               'votes', v_g.votes_count,
               'owner', (select name from players where id = v_r.owner_id),
               'result', case when v_r.status = 'revealed' then persona_result_json(v_r.id) end) end,
    'history', (select coalesce(json_agg(json_build_object(
                   'number', r.number, 'owner', p.name, 'fact', r.fact,
                   'correct', (select count(*) from persona_votes v where v.round_id = r.id and v.guess_id = r.owner_id),
                   'total', (select count(*) from persona_votes v where v.round_id = r.id)) order by r.number desc), '[]'::json)
                from persona_rounds r join players p on p.id = r.owner_id
                where r.event_id = v_event and r.status = 'revealed')
  );
end $$;

drop function if exists public.admin_persona_settings(integer, integer, integer, integer);
create or replace function public.admin_persona_settings(p_seconds integer, p_correct integer, p_bonus integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_seconds not between 5 and 300 then raise exception 'El tiempo debe estar entre 5 y 300 segundos'; end if;
  if least(p_correct, p_bonus) < 0 or greatest(p_correct, p_bonus) > 500 then
    raise exception 'Puntos fuera de rango';
  end if;
  v_event := ensure_event_rows();
  update persona_game
  set seconds = p_seconds, pts_correct = p_correct, owner_bonus = p_bonus, updated_at = now()
  where event_id = v_event;
end $$;

-- Nueva ronda con un dato al azar que no se haya usado. Pone la pantalla en este juego.
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

  -- Un dato al azar de TODO el pool (cualquiera puede tener más de un dato → no se adivina por descarte)
  select f.player_id, f.text, f.id into v_owner, v_fact, v_fact_id
  from persona_facts f join players p on p.id = f.player_id
  where f.event_id = v_event and p.approved and not f.discarded and not persona_fact_used(f.id)
  order by random() limit 1;
  if v_owner is null then raise exception 'No quedan datos curiosos sin usar 🤷'; end if;

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

-- Revelar: calcula y entrega los puntos
create or replace function public.admin_persona_reveal()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid;
  v_g     persona_game%rowtype;
  v_r     persona_rounds%rowtype;
  v_total   integer;
  v_correct integer;
  v_caught  boolean;
  v_pts     integer;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  select * into v_g from persona_game where event_id = v_event for update;
  select * into v_r from persona_rounds where id = v_g.current_round_id;
  if v_r.id is null or v_r.status <> 'voting' then raise exception 'No hay una ronda en votación'; end if;

  -- Quienes adivinaron
  if v_g.pts_correct <> 0 then
    insert into points_ledger (event_id, player_id, source, points, reason)
    select v_event, v.voter_id, 'personaje', v_g.pts_correct, 'Adivinó el personaje (ronda #' || v_r.number || ')'
    from persona_votes v
    join players p on p.id = v.voter_id and p.approved
    where v.round_id = v_r.id and v.guess_id = v_r.owner_id;
  end if;

  -- El dueño: puntos extra por participar; x2 si NO lo atraparon (menos de la mitad acertó)
  select count(*), count(*) filter (where guess_id = v_r.owner_id)
  into v_total, v_correct
  from persona_votes where round_id = v_r.id;
  v_caught := v_total > 0 and v_correct * 2 > v_total;
  v_pts := case when v_caught then v_g.owner_bonus else v_g.owner_bonus * 2 end;
  if v_pts > 0 then
    insert into points_ledger (event_id, player_id, source, points, reason)
    values (v_event, v_r.owner_id, 'personaje', v_pts,
            case when v_caught then 'Tu dato salió en el juego (ronda #' || v_r.number || ')'
                 else '¡No te atraparon! Puntos x2 (ronda #' || v_r.number || ')' end);
  end if;

  update persona_rounds set owner_points = v_pts, caught = v_caught where id = v_r.id;
  update persona_rounds set status = 'revealed', revealed_at = now() where id = v_r.id;
  update persona_game set round_status = 'revealed', updated_at = now() where event_id = v_event;
end $$;

-- Cancelar la ronda en votación. p_discard = true → el dato no vuelve a salir (ej. no es apropiado)
create or replace function public.admin_persona_cancel(p_discard boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid;
  v_g     persona_game%rowtype;
  v_r     persona_rounds%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  select * into v_g from persona_game where event_id = v_event for update;
  select * into v_r from persona_rounds where id = v_g.current_round_id;
  if v_r.id is null or v_r.status <> 'voting' then raise exception 'No hay una ronda en votación'; end if;

  delete from persona_votes where round_id = v_r.id;
  update persona_rounds set status = 'cancelled' where id = v_r.id;
  if p_discard then
    update persona_facts set discarded = true where id = v_r.fact_id;
  end if;
  update persona_game
  set current_round_id = null, round_status = 'none', ends_at = null, votes_count = 0, updated_at = now()
  where event_id = v_event;
end $$;

-- Quitar la ronda revelada de la pantalla (vuelve a "esperando ronda")
create or replace function public.admin_persona_clear()
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  update persona_game
  set current_round_id = null, round_status = 'none', ends_at = null, votes_count = 0, updated_at = now()
  where event_id = v_event and round_status = 'revealed';
end $$;

-- Pantalla: se agrega el modo 'persona'
create or replace function public.admin_set_dashboard(p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_mode not in ('leaderboard', 'costume_reveal', 'codes', 'persona') then raise exception 'Modo inválido'; end if;
  v_event := ensure_event_rows();
  update dashboard_state set mode = p_mode, updated_at = now() where event_id = v_event;
end $$;

-- Reinicio (redefinido para incluir este juego). Los datos curiosos se conservan y vuelven a estar disponibles
-- (los de invitados eliminados con "Borrar todo" se borran con ellos).
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
  -- ¿Quién es el personaje?
  delete from persona_rounds where event_id = v_event;
  update persona_game
  set current_round_id = null, round_status = 'none', ends_at = null, votes_count = 0, updated_at = now()
  where event_id = v_event;
  -- Pantalla
  update dashboard_state set mode = 'leaderboard', updated_at = now() where event_id = v_event;

  if p_scope = 'all' then
    delete from players where event_id = v_event and not is_admin;
    if coalesce(trim(p_event_name), '') <> '' then
      update events set name = trim(p_event_name) where id = v_event;
    end if;
  end if;
end $$;

grant execute on all functions in schema public to anon, authenticated;

-- =====================================================================
-- TIEMPO REAL
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'persona_game') then
    alter publication supabase_realtime add table public.persona_game;
  end if;
end $$;

-- =====================================================================
-- Party Games App · Fase 6: El Regalo Loco + QR del wifi en la pantalla
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1 a 5.
-- =====================================================================

-- =====================================================================
-- WIFI: se guarda en la base (NO en el código de GitHub) y la pantalla dibuja el QR
-- =====================================================================
alter table public.events add column if not exists wifi_ssid     text;
alter table public.events add column if not exists wifi_password text;
alter table public.events add column if not exists wifi_security text not null default 'WPA';

-- Formato estándar de QR de wifi: WIFI:T:WPA;S:<red>;P:<clave>;;
create or replace function public.wifi_escape(p text)
returns text language sql immutable as $$
  select regexp_replace(coalesce(p, ''), '([\\;,:"])', '\\\1', 'g')
$$;

create or replace function public.admin_set_wifi(p_ssid text, p_password text, p_security text default 'WPA')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_security not in ('WPA', 'WEP', 'nopass') then raise exception 'Seguridad inválida'; end if;
  update events
  set wifi_ssid = nullif(trim(p_ssid), ''),
      wifi_password = case when p_security = 'nopass' then null else p_password end,
      wifi_security = p_security
  where id = active_event_id();
end $$;

create or replace function public.admin_get_wifi()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  return (select json_build_object('ssid', wifi_ssid, 'password', wifi_password, 'security', wifi_security)
          from events where id = active_event_id());
end $$;

-- =====================================================================
-- EL REGALO LOCO · TABLAS
-- =====================================================================

-- Estado público (sin textos ni autores)
create table if not exists public.gift_game (
  event_id         uuid primary key references public.events(id) on delete cascade,
  status           text not null default 'none'
                   check (status in ('none', 'writing', 'reading', 'voting', 'results')),
  current_round_id uuid,
  read_index       integer not null default 0,   -- frase que se muestra al leer
  reveal_step      integer not null default 0 check (reveal_step between 0 and 3),
  parts_done       integer not null default 0,   -- progreso de escritura (para la pantalla)
  parts_total      integer not null default 0,
  voters_done      integer not null default 0,
  pts_1            integer not null default 10,
  pts_2            integer not null default 6,
  pts_3            integer not null default 4,
  updated_at       timestamptz not null default now()
);

create table if not exists public.gift_rounds (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  number     integer not null,
  status     text not null default 'active' check (status in ('active', 'finished', 'cancelled')),
  created_at timestamptz not null default now()
);

-- Cada "cadena" = una frase. PRIVADO hasta que se lee.
create table if not exists public.gift_chains (
  id                 uuid primary key default gen_random_uuid(),
  round_id           uuid not null references public.gift_rounds(id) on delete cascade,
  read_order         integer not null,               -- orden al azar para leer
  giver_id           uuid not null references public.players(id) on delete cascade,
  recipient_id       uuid not null references public.players(id) on delete cascade,
  use_writer_id      uuid not null references public.players(id) on delete cascade,
  reaction_writer_id uuid not null references public.players(id) on delete cascade,
  object_text        text check (object_text is null or char_length(object_text) <= 80),
  use_text           text check (use_text is null or char_length(use_text) <= 80),
  reaction_text      text check (reaction_text is null or char_length(reaction_text) <= 80),
  phrase             text,
  votes              integer not null default 0,
  place              integer,
  tied               boolean not null default false
);
create index if not exists gift_chains_round_idx on public.gift_chains (round_id, read_order);

create table if not exists public.gift_votes (
  round_id  uuid not null references public.gift_rounds(id) on delete cascade,
  voter_id  uuid not null references public.players(id) on delete cascade,
  chain_id  uuid not null references public.gift_chains(id) on delete cascade,
  primary key (round_id, voter_id, chain_id)
);

insert into public.gift_game (event_id) select id from public.events on conflict do nothing;

-- =====================================================================
-- SEGURIDAD
-- =====================================================================
alter table public.gift_game   enable row level security;
alter table public.gift_rounds enable row level security;
alter table public.gift_chains enable row level security;
alter table public.gift_votes  enable row level security;

drop policy if exists "regalo: lectura pública" on public.gift_game;
create policy "regalo: lectura pública" on public.gift_game for select to anon, authenticated using (true);
-- gift_rounds, gift_chains, gift_votes: sin políticas → solo vía funciones

grant select on public.gift_game to anon, authenticated;

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
  return v_event;
end $$;

create or replace function public.pname(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nickname, name) from players where id = p_id
$$;

-- Recalcula el progreso público de escritura
create or replace function public.gift_refresh_progress(p_round uuid)
returns void language sql security definer set search_path = public as $$
  update gift_game set
    parts_done = (select count(object_text) + count(use_text) + count(reaction_text) from gift_chains where round_id = p_round),
    parts_total = (select count(*) * 3 from gift_chains where round_id = p_round),
    voters_done = (select count(distinct voter_id) from gift_votes where round_id = p_round),
    updated_at = now()
  where current_round_id = p_round
$$;

-- Frases (solo cuando ya se pueden mostrar). p_upto: hasta qué número de lectura
create or replace function public.gift_phrases_json(p_round uuid, p_upto integer default null)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', c.id, 'n', c.read_order, 'phrase', c.phrase) order by c.read_order), '[]'::json)
  from gift_chains c
  where c.round_id = p_round and c.phrase is not null and (p_upto is null or c.read_order <= p_upto)
$$;

-- Podio revelado (3.º → 1.º) con sus autores
create or replace function public.gift_podium_json(p_round uuid, p_step integer)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'place', c.place, 'phrase', c.phrase, 'votes', c.votes,
           'authors', json_build_array(pname(c.giver_id), pname(c.use_writer_id), pname(c.reaction_writer_id)))
         order by c.place), '[]'::json)
  from gift_chains c
  where c.round_id = p_round and c.place is not null and c.place <= 3 and c.place >= 4 - p_step and c.votes > 0
$$;

-- =====================================================================
-- RPC: INVITADOS Y PANTALLA
-- =====================================================================

create or replace function public.get_gift_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      gift_game%rowtype;
  v_a      gift_chains%rowtype;
  v_b      gift_chains%rowtype;
  v_c      gift_chains%rowtype;
begin
  select * into v_g from gift_game where event_id = v_event;
  if v_g.status is null or v_g.status = 'none' or v_g.current_round_id is null then
    return json_build_object('status', 'none');
  end if;
  select * into v_a from gift_chains where round_id = v_g.current_round_id and giver_id = v_player;
  select * into v_b from gift_chains where round_id = v_g.current_round_id and use_writer_id = v_player;
  select * into v_c from gift_chains where round_id = v_g.current_round_id and reaction_writer_id = v_player;

  return json_build_object(
    'status', v_g.status,
    'participant', v_a.id is not null,
    'recipient', pname(v_a.recipient_id),
    'my_object', v_a.object_text,
    'my_use', v_b.use_text,
    'my_reaction', v_c.reaction_text,
    'progress', json_build_object('done', v_g.parts_done, 'total', v_g.parts_total),
    'phrases', case when v_g.status in ('voting', 'results') then
                 (select coalesce(json_agg(json_build_object(
                     'id', c.id, 'n', c.read_order, 'phrase', c.phrase,
                     'mine', v_player in (c.giver_id, c.use_writer_id, c.reaction_writer_id)) order by c.read_order), '[]'::json)
                  from gift_chains c where c.round_id = v_g.current_round_id) end,
    'my_votes', (select coalesce(json_agg(chain_id), '[]'::json) from gift_votes
                 where round_id = v_g.current_round_id and voter_id = v_player),
    'podium', case when v_g.status = 'results' then gift_podium_json(v_g.current_round_id, v_g.reveal_step) end
  );
end $$;

-- Guardar una de mis 3 partes: 'object' | 'use' | 'reaction'
create or replace function public.save_gift_part(p_part text, p_text text)
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
    return json_build_object('ok', false, 'error', 'Ya no se puede escribir');
  end if;
  if char_length(coalesce(v_txt, '')) > 80 then return json_build_object('ok', false, 'error', 'Máximo 80 caracteres'); end if;

  if p_part = 'object' then
    update gift_chains set object_text = v_txt where round_id = v_g.current_round_id and giver_id = v_player;
  elsif p_part = 'use' then
    update gift_chains set use_text = v_txt where round_id = v_g.current_round_id and use_writer_id = v_player;
  elsif p_part = 'reaction' then
    update gift_chains set reaction_text = v_txt where round_id = v_g.current_round_id and reaction_writer_id = v_player;
  else
    raise exception 'Parte inválida';
  end if;
  if not found then return json_build_object('ok', false, 'error', 'No participas en esta ronda'); end if;

  perform gift_refresh_progress(v_g.current_round_id);
  return json_build_object('ok', true);
end $$;

-- Votar: hasta 3 frases (no las propias). Reemplaza la selección anterior.
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
    and v_player not in (c.giver_id, c.use_writer_id, c.reaction_writer_id);

  perform gift_refresh_progress(v_g.current_round_id);
  return json_build_object('ok', true);
end $$;

-- Pantalla
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

-- =====================================================================
-- RPC: ADMIN
-- =====================================================================

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
    'settings', json_build_object('p1', coalesce(v_g.pts_1, 10), 'p2', coalesce(v_g.pts_2, 6), 'p3', coalesce(v_g.pts_3, 4)),
    'read_index', v_g.read_index,
    'reveal_step', v_g.reveal_step,
    'progress', json_build_object('done', v_g.parts_done, 'total', v_g.parts_total),
    'voters_done', v_g.voters_done,
    'count', (select count(*) from gift_chains where round_id = v_g.current_round_id),
    -- Quién no ha terminado (sin revelar QUÉ escribió)
    'missing', (select coalesce(json_agg(x.name order by x.name), '[]'::json) from (
                  select distinct pname(p.pid) as name from (
                    select giver_id as pid from gift_chains where round_id = v_g.current_round_id and object_text is null
                    union select use_writer_id from gift_chains where round_id = v_g.current_round_id and use_text is null
                    union select reaction_writer_id from gift_chains where round_id = v_g.current_round_id and reaction_text is null) p) x),
    'current', (select json_build_object('n', c.read_order, 'phrase', c.phrase)
                from gift_chains c where c.round_id = v_g.current_round_id and c.read_order = v_g.read_index),
    'results', (select coalesce(json_agg(json_build_object('place', c.place, 'votes', c.votes, 'tied', c.tied, 'phrase', c.phrase,
                   'authors', json_build_array(pname(c.giver_id), pname(c.use_writer_id), pname(c.reaction_writer_id)))
                   order by c.place), '[]'::json)
                from gift_chains c where c.round_id = v_g.current_round_id and c.place is not null and c.place <= 5)
  );
end $$;

create or replace function public.admin_gift_settings(p1 integer, p2 integer, p3 integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if least(p1, p2, p3) < 0 or greatest(p1, p2, p3) > 500 then raise exception 'Puntos fuera de rango'; end if;
  v_event := ensure_event_rows();
  update gift_game set pts_1 = p1, pts_2 = p2, pts_3 = p3, updated_at = now() where event_id = v_event;
end $$;

-- Empezar: orden al azar p0..pn-1. La cadena i: regala p(i) a p(i+1), el uso lo escribe p(i+2) y la reacción p(i+3).
-- Así cada persona escribe exactamente 1 objeto, 1 uso y 1 reacción, y nunca para su propia cadena.
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
  from players where id = any(p_players) and event_id = v_event and approved;
  v_n := coalesce(cardinality(v_ids), 0);
  if v_n < 4 then raise exception 'Se necesitan al menos 4 jugadores'; end if;

  select coalesce(max(number), 0) + 1 into v_number from gift_rounds where event_id = v_event;
  insert into gift_rounds (event_id, number) values (v_event, v_number) returning id into v_round;

  insert into gift_chains (round_id, read_order, giver_id, recipient_id, use_writer_id, reaction_writer_id)
  select v_round, row_number() over (order by random()),
         v_ids[i], v_ids[(i % v_n) + 1], v_ids[((i + 1) % v_n) + 1], v_ids[((i + 2) % v_n) + 1]
  from generate_series(1, v_n) as i;

  update gift_game
  set status = 'writing', current_round_id = v_round, read_index = 0, reveal_step = 0,
      parts_done = 0, parts_total = v_n * 3, voters_done = 0, updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'gift', updated_at = now() where event_id = v_event;
end $$;

-- Cerrar la escritura: arma las frases (lo que falte se rellena) y pasa a lectura
create or replace function public.admin_gift_close_writing()
returns void language plpgsql security definer set search_path = public as $$
declare v_g gift_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from gift_game where event_id = active_event_id() for update;
  if v_g.status <> 'writing' then raise exception 'No se está escribiendo'; end if;

  update gift_chains c set phrase =
    pname(c.giver_id) || ' le regaló a ' || pname(c.recipient_id) || ' ' ||
    coalesce(c.object_text, (array['un regalo misterioso', 'una caja vacía', 'un calcetín sin par'])[1 + floor(random() * 3)::int]) ||
    ', que sirve para ' ||
    coalesce(c.use_text, (array['nada en absoluto', 'decorar el baño', 'molestar a los vecinos'])[1 + floor(random() * 3)::int]) ||
    ', y al recibirlo exclamó: «' ||
    coalesce(c.reaction_text, (array['…¿gracias?', '¡No puede ser!', '¡Justo lo que necesitaba!'])[1 + floor(random() * 3)::int]) || '»'
  where c.round_id = v_g.current_round_id;

  update gift_game set status = 'reading', read_index = 1, updated_at = now() where event_id = active_event_id();
end $$;

-- Mostrar la frase número p_index en la pantalla
create or replace function public.admin_gift_read(p_index integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_g gift_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from gift_game where event_id = active_event_id();
  if v_g.status <> 'reading' then raise exception 'No se están leyendo frases'; end if;
  update gift_game
  set read_index = greatest(1, least(p_index, (select count(*) from gift_chains where round_id = v_g.current_round_id))),
      updated_at = now()
  where event_id = active_event_id();
end $$;

create or replace function public.admin_gift_open_vote()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  update gift_game set status = 'voting', updated_at = now()
  where event_id = active_event_id() and status = 'reading';
  if not found then raise exception 'Primero cierra la escritura y lee las frases'; end if;
end $$;

-- Cerrar votación: calcula lugares y genera puntos (ocultos hasta revelar el 1.º)
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

  -- Puntos a los 3 autores de cada frase del podio (ocultos hasta revelar el 1.º)
  insert into points_ledger (event_id, player_id, source, points, reason, visible)
  select v_event, a.pid, 'regalo',
         case c.place when 1 then v_g.pts_1 when 2 then v_g.pts_2 else v_g.pts_3 end,
         'Regalo Loco: frase en ' || c.place || '.º lugar', false
  from gift_chains c
  cross join lateral (values (c.giver_id), (c.use_writer_id), (c.reaction_writer_id)) as a(pid)
  where c.round_id = v_g.current_round_id and c.place <= 3 and c.votes > 0
    and (case c.place when 1 then v_g.pts_1 when 2 then v_g.pts_2 else v_g.pts_3 end) <> 0;

  update gift_game set status = 'results', reveal_step = 0, updated_at = now() where event_id = v_event;
  update gift_rounds set status = 'finished' where id = v_g.current_round_id;
end $$;

-- Revelar 3.º (1), 2.º (2), 1.º (3). Al revelar el 1.º se suman los puntos.
create or replace function public.admin_gift_reveal(p_step integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_g gift_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_step not between 0 and 3 then raise exception 'Paso inválido'; end if;
  select * into v_g from gift_game where event_id = active_event_id();
  if v_g.status <> 'results' then raise exception 'Primero cierra la votación'; end if;
  update gift_game set reveal_step = p_step, updated_at = now() where event_id = active_event_id();
  update points_ledger set visible = (p_step = 3)
  where event_id = active_event_id() and source = 'regalo'
    and reason like 'Regalo Loco:%' and created_at >= (select created_at from gift_rounds where id = v_g.current_round_id);
end $$;

-- Cancelar / limpiar (si ya se revelaron puntos, se conservan)
create or replace function public.admin_gift_cancel()
returns void language plpgsql security definer set search_path = public as $$
declare v_g gift_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from gift_game where event_id = active_event_id();
  if v_g.status in ('writing', 'reading', 'voting') then
    update gift_rounds set status = 'cancelled' where id = v_g.current_round_id;
  elsif v_g.status = 'results' and v_g.reveal_step < 3 then
    -- puntos ocultos de una ronda no revelada: se quitan
    delete from points_ledger where event_id = active_event_id() and source = 'regalo' and not visible;
  end if;
  update gift_game
  set status = 'none', current_round_id = null, read_index = 0, reveal_step = 0,
      parts_done = 0, parts_total = 0, voters_done = 0, updated_at = now()
  where event_id = active_event_id();
end $$;

-- =====================================================================
-- PANTALLA Y REINICIO (redefinidos)
-- =====================================================================
create or replace function public.admin_set_dashboard(p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_mode not in ('leaderboard', 'costume_reveal', 'codes', 'persona', 'impostor', 'gift', 'final') then
    raise exception 'Modo inválido';
  end if;
  v_event := ensure_event_rows();
  update dashboard_state set mode = p_mode, updated_at = now() where event_id = v_event;
end $$;

create or replace function public.get_dashboard()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'mode', coalesce((select mode from dashboard_state where event_id = active_event_id()), 'leaderboard'),
    'frozen', (select frozen_at is not null from dashboard_state where event_id = active_event_id()),
    'event_name', (select name from events where id = active_event_id()),
    'wifi', (select case when wifi_ssid is null then null else json_build_object(
               'ssid', wifi_ssid,
               'qr', 'WIFI:T:' || wifi_security || ';S:' || wifi_escape(wifi_ssid) || ';' ||
                     case when wifi_security = 'nopass' then '' else 'P:' || wifi_escape(wifi_password) || ';' end || ';') end
             from events where id = active_event_id()),
    'costume', json_build_object(
      'status',      coalesce((select status from costume_contest where event_id = active_event_id()), 'not_started'),
      'reveal_step', coalesce((select reveal_step from costume_contest where event_id = active_event_id()), 0),
      'podium',      costume_podium_json(),
      'candidates',  (select count(*) from players
                      where event_id = active_event_id() and approved and has_costume)
    )
  )
$$;

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

-- =====================================================================
-- TIEMPO REAL
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'gift_game') then
    alter publication supabase_realtime add table public.gift_game;
  end if;
end $$;

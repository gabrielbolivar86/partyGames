-- =====================================================================
-- Party Games App · Fase 3: Caza de códigos secretos
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1 y 2.
-- =====================================================================

-- =====================================================================
-- TABLAS
-- =====================================================================

-- Configuración y estado del juego (uno por fiesta). Público.
create table if not exists public.code_hunt (
  event_id       uuid primary key references public.events(id) on delete cascade,
  status         text not null default 'not_started' check (status in ('not_started', 'open', 'closed')),
  max_per_player integer not null default 4,   -- 0 = sin límite
  pts_1          integer not null default 10,  -- 1.º en encontrar ese código
  pts_2          integer not null default 8,
  pts_3          integer not null default 6,
  pts_4_6        integer not null default 4,
  pts_rest       integer not null default 2,   -- 7.º en adelante
  updated_at     timestamptz not null default now()
);

-- Códigos escondidos. PRIVADO (contiene los códigos): solo el admin los ve vía funciones.
create table if not exists public.hunt_codes (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  number     integer not null,                                  -- "Código #3"
  pin        text not null check (pin ~ '^[A-Z0-9]{6}$'),       -- código de 6 caracteres, ej. K7PX3M
  label      text check (label is null or char_length(label) <= 80), -- dónde está escondido (solo admin)
  created_at timestamptz not null default now(),
  unique (event_id, pin),
  unique (event_id, number)
);

-- Quién encontró qué y en qué orden. Público (no tiene los códigos) → permite tiempo real.
create table if not exists public.hunt_claims (
  id         bigint generated always as identity primary key,
  event_id   uuid not null references public.events(id) on delete cascade,
  code_id    uuid not null references public.hunt_codes(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  position   integer not null,
  points     integer not null,
  ledger_id  bigint references public.points_ledger(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (code_id, player_id)
);
create index if not exists hunt_claims_event_idx on public.hunt_claims (event_id, created_at desc);

-- Intentos fallidos (para frenar a quien prueba códigos al azar). Privado.
create table if not exists public.hunt_failed (
  id         bigint generated always as identity primary key,
  player_id  uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists hunt_failed_player_idx on public.hunt_failed (player_id, created_at);

insert into public.code_hunt (event_id) select id from public.events on conflict do nothing;

-- =====================================================================
-- SEGURIDAD
-- =====================================================================
alter table public.code_hunt   enable row level security;
alter table public.hunt_codes  enable row level security;
alter table public.hunt_claims enable row level security;
alter table public.hunt_failed enable row level security;

drop policy if exists "hunt: lectura pública" on public.code_hunt;
create policy "hunt: lectura pública" on public.code_hunt for select to anon, authenticated using (true);

drop policy if exists "claims: lectura pública" on public.hunt_claims;
create policy "claims: lectura pública" on public.hunt_claims for select to anon, authenticated using (true);
-- hunt_codes y hunt_failed: sin políticas → nadie los lee directo

grant select on public.code_hunt, public.hunt_claims to anon, authenticated;

-- =====================================================================
-- AUXILIARES (se redefinen para incluir este juego)
-- =====================================================================
create or replace function public.ensure_event_rows()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if v_event is null then raise exception 'No hay una fiesta activa'; end if;
  insert into costume_contest (event_id) values (v_event) on conflict do nothing;
  insert into dashboard_state (event_id) values (v_event) on conflict do nothing;
  insert into code_hunt (event_id) values (v_event) on conflict do nothing;
  return v_event;
end $$;

create or replace function public.hunt_points_for(p_position integer, h public.code_hunt)
returns integer language sql immutable as $$
  select case
    when p_position = 1 then h.pts_1
    when p_position = 2 then h.pts_2
    when p_position = 3 then h.pts_3
    when p_position <= 6 then h.pts_4_6
    else h.pts_rest end
$$;

-- =====================================================================
-- RPC: INVITADOS Y DASHBOARD
-- =====================================================================

-- Registrar un código encontrado (6 caracteres; ignora mayúsculas/minúsculas, espacios y guiones).
-- Devuelve {ok:true,...} o {ok:false,error}
-- (no lanza excepción en errores del jugador para poder guardar los intentos fallidos)
create or replace function public.claim_code(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_pin    text := upper(regexp_replace(coalesce(p_pin, ''), '[^A-Za-z0-9]', '', 'g'));
  v_h      code_hunt%rowtype;
  v_code   hunt_codes%rowtype;
  v_mine   integer;
  v_pos    integer;
  v_pts    integer;
  v_ledger bigint;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;

  select * into v_h from code_hunt where event_id = v_event;
  if v_h.status is distinct from 'open' then
    return json_build_object('ok', false, 'error', 'La caza de códigos no está activa en este momento');
  end if;

  if (select count(*) from hunt_failed
      where player_id = v_player and created_at > now() - interval '1 minute') >= 5 then
    return json_build_object('ok', false, 'error', 'Demasiados intentos fallidos. Espera un minuto ⏳');
  end if;

  -- Bloquea la fila del código: si dos personas lo registran a la vez, se atienden en orden
  select * into v_code from hunt_codes where event_id = v_event and pin = v_pin for update;
  if not found then
    insert into hunt_failed (player_id) values (v_player);
    return json_build_object('ok', false, 'error', 'Ese código no existe. Revisa las letras y números 🔍');
  end if;

  if exists (select 1 from hunt_claims where code_id = v_code.id and player_id = v_player) then
    return json_build_object('ok', false, 'error', 'Ya habías registrado el código #' || v_code.number);
  end if;

  select count(*) into v_mine from hunt_claims where event_id = v_event and player_id = v_player;
  if v_h.max_per_player > 0 and v_mine >= v_h.max_per_player then
    return json_build_object('ok', false,
      'error', 'Ya registraste el máximo de ' || v_h.max_per_player || ' códigos. ¡Deja algo para los demás! 😉');
  end if;

  select count(*) + 1 into v_pos from hunt_claims where code_id = v_code.id;
  v_pts := hunt_points_for(v_pos, v_h);

  if v_pts <> 0 then
    insert into points_ledger (event_id, player_id, source, points, reason, visible)
    values (v_event, v_player, 'codigos', v_pts,
            'Código #' || v_code.number || ' · ' || v_pos || '.º en encontrarlo', true)
    returning id into v_ledger;
  end if;

  insert into hunt_claims (event_id, code_id, player_id, position, points, ledger_id)
  values (v_event, v_code.id, v_player, v_pos, v_pts, v_ledger);

  return json_build_object('ok', true, 'number', v_code.number, 'position', v_pos,
                           'points', v_pts, 'found', v_mine + 1, 'max', v_h.max_per_player);
end $$;

-- Estado del juego para el celular del invitado
create or replace function public.get_hunt_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_h      code_hunt%rowtype;
begin
  select * into v_h from code_hunt where event_id = v_event;
  return json_build_object(
    'status',      coalesce(v_h.status, 'not_started'),
    'max',         coalesce(v_h.max_per_player, 4),
    'points',      json_build_object('p1', v_h.pts_1, 'p2', v_h.pts_2, 'p3', v_h.pts_3, 'p46', v_h.pts_4_6, 'rest', v_h.pts_rest),
    'total_codes', (select count(*) from hunt_codes where event_id = v_event),
    'mine',        (select coalesce(json_agg(json_build_object(
                       'number', c.number, 'position', hc.position, 'points', hc.points) order by hc.created_at), '[]'::json)
                    from hunt_claims hc join hunt_codes c on c.id = hc.code_id
                    where hc.event_id = v_event and hc.player_id = v_player)
  );
end $$;

-- Tablero público para la pantalla (sin los códigos)
create or replace function public.get_hunt_board()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'status', coalesce((select status from code_hunt where event_id = active_event_id()), 'not_started'),
    'codes', (select coalesce(json_agg(json_build_object(
                 'number', c.number,
                 'found', (select count(*) from hunt_claims hc where hc.code_id = c.id),
                 'first', (select coalesce(p.nickname, p.name) from hunt_claims hc join players p on p.id = hc.player_id
                           where hc.code_id = c.id order by hc.position limit 1)
               ) order by c.number), '[]'::json)
              from hunt_codes c where c.event_id = active_event_id()),
    'recent', (select coalesce(json_agg(x order by x.at desc), '[]'::json) from (
                 select coalesce(p.nickname, p.name) as name, c.number, hc.position, hc.points, hc.created_at as at
                 from hunt_claims hc
                 join players p on p.id = hc.player_id
                 join hunt_codes c on c.id = hc.code_id
                 where hc.event_id = active_event_id()
                 order by hc.created_at desc limit 8) x),
    'hunters', (select coalesce(json_agg(y order by y.pts desc, y.n desc), '[]'::json) from (
                  select coalesce(p.nickname, p.name) as name, count(*) as n, sum(hc.points) as pts
                  from hunt_claims hc join players p on p.id = hc.player_id
                  where hc.event_id = active_event_id()
                  group by p.id order by pts desc, n desc limit 5) y)
  )
$$;

-- =====================================================================
-- RPC: ADMIN
-- =====================================================================

create or replace function public.admin_hunt_overview()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_h     code_hunt%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_h from code_hunt where event_id = v_event;
  return json_build_object(
    'status',   coalesce(v_h.status, 'not_started'),
    'settings', json_build_object('max', coalesce(v_h.max_per_player, 4),
                  'p1', coalesce(v_h.pts_1, 10), 'p2', coalesce(v_h.pts_2, 8), 'p3', coalesce(v_h.pts_3, 6),
                  'p46', coalesce(v_h.pts_4_6, 4), 'rest', coalesce(v_h.pts_rest, 2)),
    'claims',   (select count(*) from hunt_claims where event_id = v_event),
    'codes',    (select coalesce(json_agg(json_build_object(
                    'id', c.id, 'number', c.number, 'pin', c.pin, 'label', c.label,
                    'found', (select count(*) from hunt_claims hc where hc.code_id = c.id),
                    'first', (select p.name from hunt_claims hc join players p on p.id = hc.player_id
                              where hc.code_id = c.id order by hc.position limit 1)
                  ) order by c.number), '[]'::json)
                 from hunt_codes c where c.event_id = v_event)
  );
end $$;

create or replace function public.admin_hunt_set_status(p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_status not in ('open', 'closed', 'not_started') then raise exception 'Estado inválido'; end if;
  v_event := ensure_event_rows();
  if p_status = 'open' and not exists (select 1 from hunt_codes where event_id = v_event) then
    raise exception 'Primero crea los códigos';
  end if;
  update code_hunt set status = p_status, updated_at = now() where event_id = v_event;
end $$;

create or replace function public.admin_hunt_settings(
  p_max integer, p1 integer, p2 integer, p3 integer, p46 integer, prest integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if least(p_max, p1, p2, p3, p46, prest) < 0 or greatest(p1, p2, p3, p46, prest) > 1000 or p_max > 100 then
    raise exception 'Valores fuera de rango';
  end if;
  v_event := ensure_event_rows();
  update code_hunt
  set max_per_player = p_max, pts_1 = p1, pts_2 = p2, pts_3 = p3, pts_4_6 = p46, pts_rest = prest, updated_at = now()
  where event_id = v_event;
end $$;

-- Crear N códigos aleatorios de 6 caracteres, sin repetir.
-- Alfabeto sin caracteres que se confunden (0/O, 1/I/L) para que sean fáciles de escribir.
create or replace function public.admin_hunt_create_codes(p_count integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid;
  v_next  integer;
  v_pin   text;
  v_abc   constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  i       integer;
  k       integer;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_count < 1 or p_count > 50 then raise exception 'Entre 1 y 50 códigos a la vez'; end if;
  v_event := ensure_event_rows();
  if (select count(*) from hunt_codes where event_id = v_event) + p_count > 100 then
    raise exception 'Máximo 100 códigos por fiesta';
  end if;
  select coalesce(max(number), 0) into v_next from hunt_codes where event_id = v_event;

  for i in 1..p_count loop
    loop
      v_pin := '';
      for k in 1..6 loop
        v_pin := v_pin || substr(v_abc, 1 + floor(random() * length(v_abc))::int, 1);
      end loop;
      exit when not exists (select 1 from hunt_codes where event_id = v_event and pin = v_pin);
    end loop;
    v_next := v_next + 1;
    insert into hunt_codes (event_id, number, pin) values (v_event, v_next, v_pin);
  end loop;
end $$;

create or replace function public.admin_hunt_update_code(p_code_id uuid, p_label text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  update hunt_codes set label = nullif(trim(p_label), '')
  where id = p_code_id and event_id = active_event_id();
end $$;

-- Eliminar un código: también quita los puntos que dio
create or replace function public.admin_hunt_delete_code(p_code_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  delete from points_ledger where id in (select ledger_id from hunt_claims where code_id = p_code_id);
  delete from hunt_codes where id = p_code_id and event_id = active_event_id();
end $$;

-- Borrar TODOS los códigos (y sus puntos)
create or replace function public.admin_hunt_delete_all(p_confirm text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_confirm is distinct from 'BORRAR' then raise exception 'Confirmación incorrecta'; end if;
  v_event := ensure_event_rows();
  delete from points_ledger where event_id = v_event and source = 'codigos';
  delete from hunt_codes where event_id = v_event;
  update code_hunt set status = 'not_started', updated_at = now() where event_id = v_event;
end $$;

-- Pantalla: se agrega el modo 'codes'
create or replace function public.admin_set_dashboard(p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_mode not in ('leaderboard', 'costume_reveal', 'codes') then raise exception 'Modo inválido'; end if;
  v_event := ensure_event_rows();
  update dashboard_state set mode = p_mode, updated_at = now() where event_id = v_event;
end $$;

-- Reinicio (redefinido para incluir la caza de códigos).
-- Los CÓDIGOS se conservan (puede que ya estén impresos y escondidos); se borran los hallazgos.
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
  -- Caza de códigos
  delete from hunt_claims where event_id = v_event;
  delete from hunt_failed where player_id in (select id from players where event_id = v_event);
  update code_hunt set status = 'not_started', updated_at = now() where event_id = v_event;
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
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'code_hunt') then
    alter publication supabase_realtime add table public.code_hunt;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'hunt_claims') then
    alter publication supabase_realtime add table public.hunt_claims;
  end if;
end $$;

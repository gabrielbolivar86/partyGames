-- =====================================================================
-- Party Games App · Fase 1: registro, aprobación, puntos y dashboard
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- Se puede volver a correr: borra y recrea las tablas de la fase 1.
-- ⚠️ Volver a correrlo BORRA los datos (jugadores y puntos).
-- =====================================================================

-- ---------- Limpieza (para poder re-ejecutar) ----------
drop table if exists public.points_ledger  cascade;
drop table if exists public.player_devices cascade;
drop table if exists public.player_secrets cascade;
drop table if exists public.players        cascade;
drop table if exists public.events         cascade;

-- =====================================================================
-- TABLAS
-- =====================================================================

-- Un "evento" = una fiesta. Todo cuelga de aquí para poder reutilizar la app.
create table public.events (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null,
  name       text not null,
  active     boolean not null default false,
  created_at timestamptz not null default now()
);

-- Invitados (datos públicos: los ve todo el mundo, incluido el dashboard)
create table public.players (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 1 and 40),
  nickname    text check (nickname is null or char_length(nickname) <= 30),
  has_costume boolean not null default false,
  costume     text check (costume is null or char_length(costume) <= 80),
  approved    boolean not null default false,   -- true cuando el admin aprueba su registro
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);
-- No puede haber dos personas con el mismo nombre en la misma fiesta
create unique index players_event_name_uq on public.players (event_id, lower(trim(name)));

-- Datos privados del invitado (dato curioso para el juego "¿Quién es el personaje?")
-- Sin políticas RLS: nadie los puede leer desde la app, solo funciones del servidor.
create table public.player_secrets (
  player_id       uuid primary key references public.players(id) on delete cascade,
  fun_fact        text check (fun_fact is null or char_length(fun_fact) <= 200),
  fun_fact_opt_in boolean not null default false
);

-- Dispositivos (celulares) vinculados a un invitado.
-- Cada celular tiene una sesión anónima de Supabase (auth_user_id).
-- Un invitado puede tener varios dispositivos; cada uno lo aprueba el admin.
create table public.player_devices (
  id           uuid primary key default gen_random_uuid(),
  player_id    uuid not null references public.players(id) on delete cascade,
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'approved')),
  kind         text not null check (kind in ('register', 'link')), -- registro nuevo o "ya tengo perfil"
  created_at   timestamptz not null default now()
);
create index player_devices_player_idx on public.player_devices (player_id);

-- Libro de puntos: cada suma o resta es UNA FILA NUEVA. Nunca se edita el total.
-- Tabla general = SUM(points) por jugador.
create table public.points_ledger (
  id         bigint generated always as identity primary key,
  event_id   uuid not null references public.events(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  source     text not null default 'admin',  -- admin | disfraz | impostor | codigos | regalo | personaje
  points     integer not null check (points between -1000 and 1000 and points <> 0),
  reason     text check (reason is null or char_length(reason) <= 120),
  visible    boolean not null default true,  -- false = puntos ocultos (ej. disfraz hasta la revelación)
  created_by uuid references public.players(id) on delete set null,
  created_at timestamptz not null default now()
);
create index points_ledger_event_player_idx on public.points_ledger (event_id, player_id);

-- Evento inicial
insert into public.events (slug, name, active)
values ('halloween-2026', 'Fiesta de Halloween 🎃', true);

-- =====================================================================
-- FUNCIONES AUXILIARES
-- =====================================================================

create or replace function public.active_event_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from events where active order by created_at desc limit 1
$$;

-- Invitado asociado a ESTE dispositivo (solo si está aprobado)
create or replace function public.current_player_id()
returns uuid language sql stable security definer set search_path = public as $$
  select d.player_id from player_devices d
  where d.auth_user_id = auth.uid() and d.status = 'approved'
  limit 1
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.is_admin from players p where p.id = current_player_id()), false)
$$;

-- =====================================================================
-- SEGURIDAD (Row Level Security)
-- Lectura: lo público. Escritura: SOLO mediante las funciones RPC de abajo.
-- =====================================================================

alter table public.events         enable row level security;
alter table public.players        enable row level security;
alter table public.player_secrets enable row level security;
alter table public.player_devices enable row level security;
alter table public.points_ledger  enable row level security;

create policy "events: lectura pública"  on public.events  for select to anon, authenticated using (true);
create policy "players: lectura pública" on public.players for select to anon, authenticated using (true);

create policy "devices: el propio o admin" on public.player_devices
  for select to authenticated using (auth_user_id = auth.uid() or public.is_admin());

create policy "ledger: puntos visibles (admin ve todo)" on public.points_ledger
  for select to anon, authenticated using (visible or public.is_admin());

grant usage on schema public to anon, authenticated;
grant select on public.events, public.players, public.points_ledger to anon, authenticated;
grant select on public.player_devices to authenticated;

-- =====================================================================
-- RPC: INVITADOS
-- =====================================================================

-- Estado de este dispositivo: none | pending | approved
create or replace function public.my_status()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(
    (select json_build_object(
        'status',    d.status,
        'kind',      d.kind,
        'device_id', d.id,
        'player', json_build_object(
          'id', p.id, 'name', p.name, 'nickname', p.nickname,
          'has_costume', p.has_costume, 'costume', p.costume,
          'is_admin', p.is_admin and d.status = 'approved'))
     from player_devices d
     join players p on p.id = d.player_id
     where d.auth_user_id = auth.uid()
       and p.event_id = active_event_id()),
    json_build_object('status', 'none'))
$$;

-- Registro de un invitado nuevo (queda pendiente de aprobación)
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

  insert into player_devices (player_id, auth_user_id, kind)
  values (v_player, auth.uid(), 'register');

  return my_status();
end $$;

-- "Ya tengo perfil": vincular este dispositivo a un invitado ya aprobado
create or replace function public.request_link(p_player_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No hay sesión en este dispositivo'; end if;
  if exists (select 1 from player_devices where auth_user_id = auth.uid()) then
    raise exception 'Este dispositivo ya está vinculado';
  end if;
  if not exists (select 1 from players
                 where id = p_player_id and approved and event_id = active_event_id()) then
    raise exception 'Perfil no encontrado';
  end if;

  insert into player_devices (player_id, auth_user_id, kind)
  values (p_player_id, auth.uid(), 'link');

  return my_status();
end $$;

-- Cancelar una solicitud pendiente desde el propio celular
create or replace function public.cancel_my_request()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_player uuid;
  v_kind   text;
begin
  delete from player_devices
  where auth_user_id = auth.uid() and status = 'pending'
  returning player_id, kind into v_player, v_kind;

  if v_kind = 'register'
     and not exists (select 1 from player_devices where player_id = v_player) then
    delete from players where id = v_player;
  end if;

  return my_status();
end $$;

-- Tabla general (solo puntos visibles, solo invitados aprobados)
create or replace function public.get_leaderboard()
returns table (player_id uuid, name text, nickname text, has_costume boolean, costume text, points bigint)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.nickname, p.has_costume, p.costume,
         coalesce(sum(l.points) filter (where l.visible), 0)::bigint as pts
  from players p
  left join points_ledger l on l.player_id = p.id
  where p.event_id = active_event_id() and p.approved
  group by p.id
  order by pts desc, p.name
$$;

-- =====================================================================
-- RPC: ADMIN (todas verifican is_admin() en el servidor)
-- =====================================================================

create or replace function public.admin_pending()
returns table (device_id uuid, kind text, requested_at timestamptz, player_id uuid,
               name text, nickname text, has_costume boolean, costume text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  return query
    select d.id, d.kind, d.created_at, p.id, p.name, p.nickname, p.has_costume, p.costume
    from player_devices d
    join players p on p.id = d.player_id
    where d.status = 'pending' and p.event_id = active_event_id()
    order by d.created_at;
end $$;

-- Aprobar o rechazar una solicitud (registro nuevo u otro dispositivo)
create or replace function public.admin_resolve_device(p_device_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_player uuid;
  v_kind   text;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;

  select d.player_id, d.kind into v_player, v_kind
  from player_devices d where d.id = p_device_id and d.status = 'pending';
  if v_player is null then raise exception 'Solicitud no encontrada'; end if;

  if p_approve then
    update player_devices set status = 'approved' where id = p_device_id;
    update players set approved = true where id = v_player;
  else
    delete from player_devices where id = p_device_id;
    if v_kind = 'register'
       and not exists (select 1 from player_devices where player_id = v_player) then
      delete from players where id = v_player;
    end if;
  end if;
end $$;

-- Dar (positivo) o quitar (negativo) puntos
create or replace function public.admin_add_points(p_player_id uuid, p_points integer, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if coalesce(p_points, 0) = 0 then raise exception 'Los puntos no pueden ser 0'; end if;
  if not exists (select 1 from players
                 where id = p_player_id and approved and event_id = active_event_id()) then
    raise exception 'Invitado no encontrado';
  end if;

  insert into points_ledger (event_id, player_id, source, points, reason, created_by)
  values (active_event_id(), p_player_id, 'admin', p_points,
          nullif(trim(p_reason), ''), current_player_id());
end $$;

-- Deshacer un movimiento de puntos
create or replace function public.admin_delete_points(p_entry_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  delete from points_ledger where id = p_entry_id and event_id = active_event_id();
end $$;

-- Últimos movimientos (incluye ocultos)
create or replace function public.admin_ledger(p_limit integer default 30)
returns table (id bigint, player_id uuid, name text, source text, points integer,
               reason text, visible boolean, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  return query
    select l.id, l.player_id, p.name, l.source, l.points, l.reason, l.visible, l.created_at
    from points_ledger l
    join players p on p.id = l.player_id
    where l.event_id = active_event_id()
    order by l.created_at desc
    limit least(coalesce(p_limit, 30), 200);
end $$;

grant execute on all functions in schema public to anon, authenticated;

-- =====================================================================
-- TIEMPO REAL: qué tablas emiten cambios por WebSocket
-- =====================================================================
alter publication supabase_realtime add table public.players, public.points_ledger, public.player_devices;

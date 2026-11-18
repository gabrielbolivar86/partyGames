-- =====================================================================
-- Party Games App · Fase 10: varias fiestas, anfitriones y juegos a elegir
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1 a 9.
--
-- Idea: cada fiesta tiene un "slug" (ej. halloween-2026) que va en la URL
-- (#/p/halloween-2026/...). La app lo manda en cada petición como el header
-- "x-party", y active_event_id() lo usa para saber de qué fiesta se trata.
-- Si no llega el header (tiempo real, enlaces viejos) se usa la fiesta "activa".
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- TABLAS Y COLUMNAS NUEVAS
-- =====================================================================

-- Dueños de la app: pueden crear fiestas y anfitriones (ver 12_hacerme_dueno.sql)
create table if not exists public.app_owners (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now()
);
alter table public.app_owners enable row level security; -- sin políticas: solo funciones del servidor

alter table public.events add column if not exists host_password_hash text;
alter table public.events add column if not exists enabled_games text[] not null
  default array['costume', 'codes', 'persona', 'impostor', 'gift', 'wolf'];
alter table public.events add column if not exists wifi_show boolean not null default false;
alter table public.events add column if not exists created_by uuid;

-- La contraseña del anfitrión y la del wifi NO se pueden leer desde la app
revoke select on public.events from anon, authenticated;
grant select (id, slug, name, active, created_at, enabled_games) on public.events to anon, authenticated;

-- Un mismo celular puede estar en varias fiestas (una vez por fiesta)
alter table public.player_devices drop constraint if exists player_devices_auth_user_id_key;
create unique index if not exists player_devices_user_player_uq
  on public.player_devices (auth_user_id, player_id);
create index if not exists player_devices_user_idx on public.player_devices (auth_user_id);

-- =====================================================================
-- ¿QUÉ FIESTA? (lee el header x-party)
-- =====================================================================

-- Slug que pidió la app en esta petición (null si no vino)
create or replace function public.request_party_slug()
returns text language sql stable as $$
  select nullif(lower(trim(
    coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json ->> 'x-party')), '')
$$;

create or replace function public.active_event_id()
returns uuid language sql stable security definer set search_path = public as $$
  select case
    when request_party_slug() is not null
      then (select id from events where slug = request_party_slug())
    else (select id from events where active order by created_at desc limit 1)
  end
$$;

-- Invitado de ESTE dispositivo en ESTA fiesta (solo si está aprobado)
create or replace function public.current_player_id()
returns uuid language sql stable security definer set search_path = public as $$
  select d.player_id from player_devices d
  join players p on p.id = d.player_id
  where d.auth_user_id = auth.uid() and d.status = 'approved'
    and p.event_id = active_event_id()
  limit 1
$$;

-- ¿Este dispositivo ya tiene perfil (pendiente o aprobado) en esta fiesta?
create or replace function public.device_in_party()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from player_devices d join players p on p.id = d.player_id
                 where d.auth_user_id = auth.uid() and p.event_id = active_event_id())
$$;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from app_owners where auth_user_id = auth.uid())
$$;

create or replace function public.party_json()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'slug', slug, 'name', name, 'games', enabled_games)
  from events where id = active_event_id()
$$;

-- Crea las filas de estado de cada juego para una fiesta concreta
create or replace function public.ensure_rows_for(p_event uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into costume_contest (event_id) values (p_event) on conflict do nothing;
  insert into dashboard_state (event_id) values (p_event) on conflict do nothing;
  insert into code_hunt (event_id) values (p_event) on conflict do nothing;
  insert into persona_game (event_id) values (p_event) on conflict do nothing;
  insert into impostor_game (event_id) values (p_event) on conflict do nothing;
  insert into gift_game (event_id) values (p_event) on conflict do nothing;
  insert into wolf_state (event_id) values (p_event) on conflict do nothing;
end $$;

-- =====================================================================
-- INVITADOS (redefinidas para que todo sea por fiesta)
-- =====================================================================

create or replace function public.my_status()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(
    (select json_build_object(
        'status',    d.status,
        'kind',      d.kind,
        'device_id', d.id,
        'is_owner',  is_owner(),
        'party',     party_json(),
        'player', json_build_object(
          'id', p.id, 'name', p.name, 'nickname', p.nickname,
          'has_costume', p.has_costume, 'costume', p.costume,
          'is_admin', p.is_admin and d.status = 'approved'))
     from player_devices d
     join players p on p.id = d.player_id
     where d.auth_user_id = auth.uid()
       and p.event_id = active_event_id()
     limit 1),
    json_build_object('status', 'none', 'is_owner', is_owner(), 'party', party_json()))
$$;

-- Registro (igual que la fase 4, pero el "ya registrado" es solo en esta fiesta)
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
  if v_event is null then raise exception 'Esta fiesta no existe. Revisa el enlace con tu anfitrión.'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  if coalesce(p_has_costume, false) and coalesce(trim(p_costume), '') = '' then
    raise exception 'Cuéntanos de qué vienes disfrazado';
  end if;
  if char_length(coalesce(p_fun_fact, '')) > 200 then raise exception 'El dato curioso admite máximo 200 caracteres'; end if;
  if device_in_party() then raise exception 'Este dispositivo ya está registrado en esta fiesta'; end if;
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

create or replace function public.request_link(p_player_id uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'No hay sesión en este dispositivo'; end if;
  if device_in_party() then raise exception 'Este dispositivo ya está vinculado en esta fiesta'; end if;
  if not exists (select 1 from players
                 where id = p_player_id and approved and event_id = active_event_id()) then
    raise exception 'Perfil no encontrado';
  end if;

  insert into player_devices (player_id, auth_user_id, kind)
  values (p_player_id, auth.uid(), 'link');

  return my_status();
end $$;

create or replace function public.cancel_my_request()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_player uuid;
  v_kind   text;
begin
  delete from player_devices d
  using players p
  where p.id = d.player_id and p.event_id = active_event_id()
    and d.auth_user_id = auth.uid() and d.status = 'pending'
  returning d.player_id, d.kind into v_player, v_kind;

  if v_kind = 'register'
     and not exists (select 1 from player_devices where player_id = v_player) then
    delete from players where id = v_player;
  end if;

  return my_status();
end $$;

-- Aprobar/rechazar: solo solicitudes de ESTA fiesta
create or replace function public.admin_resolve_device(p_device_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_player uuid;
  v_kind   text;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;

  select d.player_id, d.kind into v_player, v_kind
  from player_devices d join players p on p.id = d.player_id
  where d.id = p_device_id and d.status = 'pending' and p.event_id = active_event_id();
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

-- =====================================================================
-- ANFITRIÓN: entrar con la contraseña de la fiesta
-- =====================================================================
create or replace function public.host_login(p_password text, p_name text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_event  uuid;
  v_hash   text;
  v_player uuid;
begin
  if auth.uid() is null then raise exception 'No hay sesión en este dispositivo'; end if;
  if request_party_slug() is null then raise exception 'Falta la fiesta en el enlace'; end if;
  select id, host_password_hash into v_event, v_hash from events where slug = request_party_slug();
  if v_event is null then raise exception 'Esta fiesta no existe'; end if;
  if v_hash is null or coalesce(p_password, '') = '' or crypt(p_password, v_hash) <> v_hash then
    perform pg_sleep(1); -- frena intentos al azar
    raise exception 'Contraseña incorrecta';
  end if;
  perform ensure_rows_for(v_event);

  -- ¿Este celular ya tiene perfil aquí? Se convierte en anfitrión.
  select d.player_id into v_player
  from player_devices d join players p on p.id = d.player_id
  where d.auth_user_id = auth.uid() and p.event_id = v_event;

  if v_player is null then
    if coalesce(trim(p_name), '') = '' then raise exception 'Escribe tu nombre'; end if;
    select id into v_player from players
    where event_id = v_event and lower(trim(name)) = lower(trim(p_name));
    if v_player is null then
      insert into players (event_id, name, approved, is_admin)
      values (v_event, trim(p_name), true, true)
      returning id into v_player;
      insert into player_secrets (player_id) values (v_player);
    end if;
    insert into player_devices (player_id, auth_user_id, kind, status)
    values (v_player, auth.uid(), 'link', 'approved');
  else
    update player_devices set status = 'approved'
    where auth_user_id = auth.uid() and player_id = v_player;
  end if;

  update players set is_admin = true, approved = true where id = v_player;
  return my_status();
end $$;

-- =====================================================================
-- ANFITRIÓN: juegos de la fiesta y wifi
-- =====================================================================
create or replace function public.admin_set_games(p_games text[])
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if exists (select 1 from unnest(coalesce(p_games, '{}')) g
             where g not in ('costume', 'codes', 'persona', 'impostor', 'gift', 'wolf')) then
    raise exception 'Juego desconocido';
  end if;
  update events set enabled_games = coalesce(p_games, '{}') where id = v_event;
  perform ensure_rows_for(v_event);
  -- Toca la pantalla para que todos (tiempo real) recarguen
  update dashboard_state set updated_at = now() where event_id = v_event;
end $$;

create or replace function public.admin_get_wifi()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  return (select json_build_object('ssid', wifi_ssid, 'password', wifi_password,
                                   'security', wifi_security, 'show', wifi_show)
          from events where id = active_event_id());
end $$;

create or replace function public.admin_set_wifi_show(p_show boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  update events set wifi_show = coalesce(p_show, false) where id = v_event;
  update dashboard_state set updated_at = now() where event_id = v_event;
end $$;

create or replace function public.admin_clear_wifi()
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  update events set wifi_ssid = null, wifi_password = null, wifi_security = 'WPA', wifi_show = false
  where id = v_event;
  update dashboard_state set updated_at = now() where event_id = v_event;
end $$;

-- Pantalla: el wifi solo sale si el anfitrión lo activó. Incluye la fiesta y sus juegos.
create or replace function public.get_dashboard()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'mode', coalesce((select mode from dashboard_state where event_id = active_event_id()), 'leaderboard'),
    'frozen', (select frozen_at is not null from dashboard_state where event_id = active_event_id()),
    'event_name', (select name from events where id = active_event_id()),
    'party', party_json(),
    'games', (select enabled_games from events where id = active_event_id()),
    'wifi', (select case when wifi_ssid is null or not wifi_show then null else json_build_object(
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

-- =====================================================================
-- DUEÑO: crear y administrar fiestas
-- =====================================================================
create or replace function public.owner_list_parties()
returns table (id uuid, slug text, name text, active boolean, created_at timestamptz,
               games text[], players bigint, hosts bigint, has_password boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_owner() then raise exception 'Solo el dueño de la app puede hacer esto'; end if;
  return query
    select e.id, e.slug, e.name, e.active, e.created_at, e.enabled_games,
           (select count(*) from players p where p.event_id = e.id and p.approved),
           (select count(*) from players p where p.event_id = e.id and p.is_admin),
           e.host_password_hash is not null
    from events e
    order by e.created_at desc;
end $$;

create or replace function public.owner_create_party(p_name text, p_slug text, p_password text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_slug  text := lower(trim(p_slug));
  v_event uuid;
begin
  if not is_owner() then raise exception 'Solo el dueño de la app puede hacer esto'; end if;
  if coalesce(trim(p_name), '') = '' or char_length(trim(p_name)) > 60 then
    raise exception 'El nombre de la fiesta es obligatorio (máx. 60)';
  end if;
  if v_slug !~ '^[a-z0-9][a-z0-9-]{2,39}$' then
    raise exception 'El enlace solo admite minúsculas, números y guiones (3 a 40)';
  end if;
  if exists (select 1 from events where slug = v_slug) then raise exception 'Ese enlace ya existe'; end if;
  if char_length(coalesce(p_password, '')) < 6 then raise exception 'La contraseña necesita al menos 6 caracteres'; end if;

  insert into events (slug, name, active, host_password_hash, created_by)
  values (v_slug, trim(p_name), false, crypt(p_password, gen_salt('bf')), auth.uid())
  returning id into v_event;
  perform ensure_rows_for(v_event);

  return json_build_object('id', v_event, 'slug', v_slug);
end $$;

create or replace function public.owner_set_password(p_slug text, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_owner() then raise exception 'Solo el dueño de la app puede hacer esto'; end if;
  if char_length(coalesce(p_password, '')) < 6 then raise exception 'La contraseña necesita al menos 6 caracteres'; end if;
  update events set host_password_hash = crypt(p_password, gen_salt('bf')) where slug = p_slug;
  if not found then raise exception 'Fiesta no encontrada'; end if;
end $$;

create or replace function public.owner_delete_party(p_slug text, p_confirm text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Solo el dueño de la app puede hacer esto'; end if;
  if p_confirm is distinct from p_slug then raise exception 'Escribe el enlace exacto para confirmar'; end if;
  delete from events where slug = p_slug; -- todo lo demás se borra en cascada
  if not found then raise exception 'Fiesta no encontrada'; end if;
end $$;

-- La fiesta original queda con su wifi guardado pero OCULTO de la pantalla
update public.events set wifi_show = false where slug = 'halloween-2026' and wifi_show is distinct from false;

revoke execute on function public.ensure_rows_for(uuid) from public, anon, authenticated;
grant execute on function
  public.request_party_slug(), public.active_event_id(), public.current_player_id(), public.device_in_party(),
  public.is_owner(), public.party_json(), public.my_status(),
  public.register_player(text, text, boolean, text, text, boolean), public.request_link(uuid),
  public.cancel_my_request(), public.admin_resolve_device(uuid, boolean), public.host_login(text, text),
  public.admin_set_games(text[]), public.admin_get_wifi(), public.admin_set_wifi_show(boolean),
  public.admin_clear_wifi(), public.get_dashboard(), public.owner_list_parties(),
  public.owner_create_party(text, text, text), public.owner_set_password(text, text),
  public.owner_delete_party(text, text)
to anon, authenticated;

-- =====================================================================
-- Fase 11: tema visual por fiesta
-- Requiere 11_fase10_multifiesta.sql. Se puede correr más de una vez.
-- =====================================================================

alter table public.events add column if not exists theme text not null default 'fiesta';

alter table public.events drop constraint if exists events_theme_check;
alter table public.events add constraint events_theme_check
  check (theme in ('fiesta', 'halloween', 'navidad', 'baby-nino', 'baby-nina', 'revelacion', 'verde', 'azul'));

-- La fiesta original conserva su look de Halloween
update public.events set theme = 'halloween' where slug = 'halloween-2026' and theme = 'fiesta';

-- Columnas visibles para la app (wifi y contraseña siguen ocultas)
grant select (id, slug, name, active, created_at, enabled_games, theme) on public.events to anon, authenticated;

-- El tema viaja con los datos de la fiesta (my_status y get_dashboard)
create or replace function public.party_json()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'slug', slug, 'name', name, 'games', enabled_games, 'theme', theme)
  from events where id = active_event_id()
$$;

create or replace function public.admin_set_theme(p_theme text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_theme is null or p_theme not in ('fiesta', 'halloween', 'navidad', 'baby-nino', 'baby-nina', 'revelacion', 'verde', 'azul') then
    raise exception 'Tema desconocido';
  end if;
  update events set theme = p_theme where id = v_event;
  -- Toca la pantalla para que todos (tiempo real) recarguen
  update dashboard_state set updated_at = now() where event_id = v_event;
end $$;

-- Crear fiesta con tema (el 4º parámetro es opcional: las llamadas viejas siguen funcionando)
drop function if exists public.owner_create_party(text, text, text);
create or replace function public.owner_create_party(p_name text, p_slug text, p_password text, p_theme text default 'fiesta')
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_slug  text := lower(trim(p_slug));
  v_theme text := coalesce(p_theme, 'fiesta');
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
  if v_theme not in ('fiesta', 'halloween', 'navidad', 'baby-nino', 'baby-nina', 'revelacion', 'verde', 'azul') then
    raise exception 'Tema desconocido';
  end if;

  insert into events (slug, name, active, host_password_hash, created_by, theme)
  values (v_slug, trim(p_name), false, crypt(p_password, gen_salt('bf')), auth.uid(), v_theme)
  returning id into v_event;
  perform ensure_rows_for(v_event);

  return json_build_object('id', v_event, 'slug', v_slug);
end $$;

-- Lista del dueño, ahora con el tema
drop function if exists public.owner_list_parties();
create or replace function public.owner_list_parties()
returns table (id uuid, slug text, name text, active boolean, created_at timestamptz,
               games text[], players bigint, hosts bigint, has_password boolean, theme text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_owner() then raise exception 'Solo el dueño de la app puede hacer esto'; end if;
  return query
    select e.id, e.slug, e.name, e.active, e.created_at, e.enabled_games,
           (select count(*) from players p where p.event_id = e.id and p.approved),
           (select count(*) from players p where p.event_id = e.id and p.is_admin),
           e.host_password_hash is not null,
           e.theme
    from events e
    order by e.created_at desc;
end $$;

revoke execute on function public.owner_create_party(text, text, text, text), public.owner_list_parties(),
  public.admin_set_theme(text) from public;
grant execute on function
  public.party_json(), public.admin_set_theme(text),
  public.owner_create_party(text, text, text, text), public.owner_list_parties()
to anon, authenticated;

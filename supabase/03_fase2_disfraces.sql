-- =====================================================================
-- Party Games App · Fase 2: votación de mejor disfraz, modos del dashboard,
-- gestión de invitados y reinicio (borrar pruebas / nueva fiesta).
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos de la fase 1. Se puede correr varias veces.
-- =====================================================================

-- =====================================================================
-- TABLAS
-- =====================================================================

-- Estado del concurso de disfraces (uno por fiesta). Es público: solo estado y configuración.
create table if not exists public.costume_contest (
  event_id             uuid primary key references public.events(id) on delete cascade,
  status               text not null default 'not_started'
                       check (status in ('not_started', 'open', 'closed')),
  reveal_step          integer not null default 0 check (reveal_step between 0 and 3), -- 0 nada · 1 = 3.º · 2 = 2.º · 3 = 1.º
  points_1             integer not null default 15,
  points_2             integer not null default 10,
  points_3             integer not null default 6,
  points_participation integer not null default 2,
  opened_at            timestamptz,
  closed_at            timestamptz,
  updated_at           timestamptz not null default now()
);

-- Ranking de cada votante (borrador que se guarda en cada cambio)
create table if not exists public.costume_ballots (
  event_id   uuid not null references public.events(id) on delete cascade,
  voter_id   uuid not null references public.players(id) on delete cascade,
  ranking    uuid[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (event_id, voter_id)
);

-- Resultados calculados al cerrar. PRIVADOS: solo se leen mediante funciones.
create table if not exists public.costume_results (
  event_id  uuid not null references public.events(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  place     integer not null,
  score     numeric not null,
  firsts    integer not null,
  seconds   integer not null,
  ballots   integer not null,
  tied      boolean not null default false,
  primary key (event_id, player_id)
);

-- Qué muestra el dashboard (lo cambia el admin)
create table if not exists public.dashboard_state (
  event_id   uuid primary key references public.events(id) on delete cascade,
  mode       text not null default 'leaderboard',
  updated_at timestamptz not null default now()
);

insert into public.costume_contest (event_id) select id from public.events on conflict do nothing;
insert into public.dashboard_state (event_id) select id from public.events on conflict do nothing;

-- =====================================================================
-- SEGURIDAD
-- =====================================================================
alter table public.costume_contest enable row level security;
alter table public.costume_ballots enable row level security;
alter table public.costume_results enable row level security;
alter table public.dashboard_state enable row level security;

drop policy if exists "contest: lectura pública" on public.costume_contest;
create policy "contest: lectura pública" on public.costume_contest
  for select to anon, authenticated using (true);

drop policy if exists "dashboard: lectura pública" on public.dashboard_state;
create policy "dashboard: lectura pública" on public.dashboard_state
  for select to anon, authenticated using (true);

drop policy if exists "ballots: solo el propio" on public.costume_ballots;
create policy "ballots: solo el propio" on public.costume_ballots
  for select to authenticated using (voter_id = public.current_player_id());

-- costume_results: sin políticas → nadie lo lee directo (evita espiar resultados)

grant select on public.costume_contest, public.dashboard_state to anon, authenticated;
grant select on public.costume_ballots to authenticated;

-- =====================================================================
-- AUXILIARES
-- =====================================================================

-- Asegura que existan las filas de estado para la fiesta activa
create or replace function public.ensure_event_rows()
returns uuid language plpgsql security definer set search_path = public as $$
declare v_event uuid := active_event_id();
begin
  if v_event is null then raise exception 'No hay una fiesta activa'; end if;
  insert into costume_contest (event_id) values (v_event) on conflict do nothing;
  insert into dashboard_state (event_id) values (v_event) on conflict do nothing;
  return v_event;
end $$;

-- Podio revelado hasta ahora (nunca muestra lo que falta revelar)
create or replace function public.costume_podium_json()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'place', r.place, 'player_id', p.id, 'name', p.name,
           'nickname', p.nickname, 'costume', p.costume) order by r.place), '[]'::json)
  from costume_results r
  join players p on p.id = r.player_id
  join costume_contest c on c.event_id = r.event_id
  where r.event_id = active_event_id()
    and c.status = 'closed'
    and r.place <= 3
    and r.place >= 4 - c.reveal_step
$$;

-- =====================================================================
-- RPC: INVITADOS Y DASHBOARD
-- =====================================================================

-- Todo lo que necesita el celular del invitado para votar
create or replace function public.get_costume_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_c      costume_contest%rowtype;
begin
  select * into v_c from costume_contest where event_id = v_event;
  return json_build_object(
    'status',      coalesce(v_c.status, 'not_started'),
    'reveal_step', coalesce(v_c.reveal_step, 0),
    'can_vote',    v_player is not null,
    'candidates',  (select coalesce(json_agg(json_build_object(
                       'id', p.id, 'name', p.name, 'nickname', p.nickname, 'costume', p.costume)
                       order by p.created_at), '[]'::json)
                    from players p
                    where p.event_id = v_event and p.approved and p.has_costume
                      and p.id is distinct from v_player),
    'ranking',     (select b.ranking from costume_ballots b
                    where b.event_id = v_event and b.voter_id = v_player),
    'podium',      costume_podium_json()
  );
end $$;

-- Guardar (borrador) el ranking del invitado. Se puede cambiar hasta que cierre.
create or replace function public.save_costume_ballot(p_ranking uuid[])
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_clean  uuid[];
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  if (select status from costume_contest where event_id = v_event) is distinct from 'open' then
    raise exception 'La votación no está abierta';
  end if;
  if coalesce(cardinality(p_ranking), 0) > 300 then raise exception 'Ranking demasiado largo'; end if;

  -- Limpia: solo candidatos válidos, sin repetidos, sin votarse a sí mismo, respetando el orden
  select coalesce(array_agg(x.id order by x.ord), '{}') into v_clean
  from (
    select distinct on (u.id) u.id, u.ord
    from unnest(coalesce(p_ranking, '{}')) with ordinality as u(id, ord)
    join players p on p.id = u.id
    where p.event_id = v_event and p.approved and p.has_costume and p.id <> v_player
    order by u.id, u.ord
  ) x;

  insert into costume_ballots (event_id, voter_id, ranking, updated_at)
  values (v_event, v_player, v_clean, now())
  on conflict (event_id, voter_id) do update set ranking = excluded.ranking, updated_at = now();

  return json_build_object('ranking', v_clean);
end $$;

-- Lo que muestra el dashboard (público)
create or replace function public.get_dashboard()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'mode', coalesce((select mode from dashboard_state where event_id = active_event_id()), 'leaderboard'),
    'event_name', (select name from events where id = active_event_id()),
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
-- RPC: ADMIN · CONCURSO DE DISFRACES
-- =====================================================================

-- Resumen para el panel del admin (incluye resultados completos si ya cerró)
create or replace function public.admin_costume_overview()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_c     costume_contest%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_c from costume_contest where event_id = v_event;
  return json_build_object(
    'status',      coalesce(v_c.status, 'not_started'),
    'reveal_step', coalesce(v_c.reveal_step, 0),
    'points',      json_build_object('p1', coalesce(v_c.points_1, 15), 'p2', coalesce(v_c.points_2, 10),
                                     'p3', coalesce(v_c.points_3, 6), 'pp', coalesce(v_c.points_participation, 2)),
    'candidates',  (select count(*) from players where event_id = v_event and approved and has_costume),
    'voters',      (select count(*) from players where event_id = v_event and approved),
    'ballots',     (select count(*) from costume_ballots b join players p on p.id = b.voter_id
                    where b.event_id = v_event and p.approved and cardinality(b.ranking) > 0),
    'results',     (select coalesce(json_agg(json_build_object(
                       'place', r.place, 'name', p.name, 'costume', p.costume, 'score', r.score,
                       'firsts', r.firsts, 'seconds', r.seconds, 'ballots', r.ballots, 'tied', r.tied)
                       order by r.place), '[]'::json)
                    from costume_results r join players p on p.id = r.player_id
                    where r.event_id = v_event)
  );
end $$;

-- Cambiar los puntos que da el concurso (antes de cerrar)
create or replace function public.admin_costume_settings(p1 integer, p2 integer, p3 integer, pp integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  if (select status from costume_contest where event_id = v_event) = 'closed' then
    raise exception 'La votación ya cerró. Reábrela para cambiar los puntos.';
  end if;
  if least(p1, p2, p3, pp) < 0 or greatest(p1, p2, p3, pp) > 1000 then
    raise exception 'Puntos fuera de rango (0 a 1000)';
  end if;
  update costume_contest
  set points_1 = p1, points_2 = p2, points_3 = p3, points_participation = pp, updated_at = now()
  where event_id = v_event;
end $$;

-- Abrir (o reabrir) la votación. Reabrir borra resultados y puntos del disfraz; los votos se conservan.
create or replace function public.admin_costume_open()
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  delete from costume_results where event_id = v_event;
  delete from points_ledger where event_id = v_event and source = 'disfraz';
  update costume_contest
  set status = 'open', reveal_step = 0, opened_at = coalesce(opened_at, now()), closed_at = null, updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'leaderboard', updated_at = now()
  where event_id = v_event and mode = 'costume_reveal';
end $$;

-- Cerrar la votación: calcula el ranking final y genera los puntos (ocultos hasta revelar el 1.º)
--
-- Método: Borda normalizado.
--   En cada boleta con n candidatos posibles (todos los disfrazados menos el votante),
--   la posición p vale (n - p) / (n - 1): el 1.º vale 1, el último 0.
--   Quien no fue ordenado en esa boleta recibe 0.
--   Puntaje = PROMEDIO de todas las boletas que podían votarlo.
--   Desempates: más 1.os lugares, más 2.os lugares, nombre.
create or replace function public.admin_costume_close()
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  if (select status from costume_contest where event_id = v_event) <> 'open' then
    raise exception 'La votación no está abierta';
  end if;

  delete from costume_results where event_id = v_event;
  delete from points_ledger where event_id = v_event and source = 'disfraz';

  with cands as (
    select id from players where event_id = v_event and approved and has_costume
  ),
  bl as ( -- boletas válidas (votante aprobado y con al menos 1 voto)
    select b.voter_id, b.ranking,
           (select count(*) from cands c where c.id <> b.voter_id) as n
    from costume_ballots b
    join players p on p.id = b.voter_id and p.approved
    where b.event_id = v_event and cardinality(b.ranking) > 0
  ),
  ranked as ( -- posición dentro de cada boleta, solo contando candidatos válidos
    select bl.voter_id, f.id as cand,
           row_number() over (partition by bl.voter_id order by f.ord) as pos
    from bl
    cross join lateral unnest(bl.ranking) with ordinality as f(id, ord)
    join cands c on c.id = f.id
    where f.id <> bl.voter_id
  ),
  pairs as ( -- cada (boleta, candidato) donde el candidato podía ser votado
    select bl.voter_id, c.id as cand, bl.n, r.pos
    from bl
    join cands c on c.id <> bl.voter_id
    left join ranked r on r.voter_id = bl.voter_id and r.cand = c.id
  ),
  scores as (
    select c.id as player_id,
           coalesce(avg(case when pr.voter_id is null then null
                             when pr.pos is null then 0
                             when pr.n <= 1 then 1
                             else (pr.n - pr.pos)::numeric / (pr.n - 1) end), 0) as score,
           count(*) filter (where pr.pos = 1) as firsts,
           count(*) filter (where pr.pos = 2) as seconds,
           count(pr.voter_id) as ballots
    from cands c
    left join pairs pr on pr.cand = c.id
    group by c.id
  )
  insert into costume_results (event_id, player_id, place, score, firsts, seconds, ballots, tied)
  select v_event, s.player_id,
         row_number() over (order by s.score desc, s.firsts desc, s.seconds desc, pl.name),
         round(s.score, 4), s.firsts, s.seconds, s.ballots,
         count(*) over (partition by round(s.score, 6), s.firsts, s.seconds) > 1
  from scores s
  join players pl on pl.id = s.player_id;

  -- Puntos a la tabla general, OCULTOS hasta revelar el 1.º lugar
  insert into points_ledger (event_id, player_id, source, points, reason, visible, created_by)
  select v_event, x.player_id, 'disfraz', x.pts, x.reason, false, current_player_id()
  from (
    select r.player_id,
           case r.place when 1 then c.points_1 when 2 then c.points_2 when 3 then c.points_3
                        else c.points_participation end as pts,
           case when r.place <= 3 then 'Mejor disfraz: ' || r.place || '.º lugar'
                else 'Participó en el concurso de disfraces' end as reason
    from costume_results r
    join costume_contest c on c.event_id = r.event_id
    where r.event_id = v_event
  ) x
  where x.pts <> 0;

  update costume_contest
  set status = 'closed', reveal_step = 0, closed_at = now(), updated_at = now()
  where event_id = v_event;
end $$;

-- Revelar paso a paso: 0 = nada, 1 = 3.º, 2 = 2.º, 3 = 1.º (al revelar el 1.º se suman los puntos)
create or replace function public.admin_costume_reveal(p_step integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  if (select status from costume_contest where event_id = v_event) <> 'closed' then
    raise exception 'Primero cierra la votación';
  end if;
  if p_step not between 0 and 3 then raise exception 'Paso inválido'; end if;

  update costume_contest set reveal_step = p_step, updated_at = now() where event_id = v_event;
  update points_ledger set visible = (p_step = 3)
  where event_id = v_event and source = 'disfraz';
end $$;

-- =====================================================================
-- RPC: ADMIN · PANTALLA, INVITADOS Y REINICIO
-- =====================================================================

create or replace function public.admin_set_dashboard(p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_mode not in ('leaderboard', 'costume_reveal') then raise exception 'Modo inválido'; end if;
  v_event := ensure_event_rows();
  update dashboard_state set mode = p_mode, updated_at = now() where event_id = v_event;
end $$;

-- Lista completa de invitados para el admin
create or replace function public.admin_players()
returns table (player_id uuid, name text, nickname text, has_costume boolean, costume text,
               approved boolean, is_admin boolean, devices bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  return query
    select p.id, p.name, p.nickname, p.has_costume, p.costume, p.approved, p.is_admin,
           (select count(*) from player_devices d where d.player_id = p.id and d.status = 'approved')
    from players p
    where p.event_id = active_event_id() and p.approved
    order by p.name;
end $$;

-- Corregir datos de un invitado (ej. llegó disfrazado pero marcó "no")
create or replace function public.admin_update_player(
  p_player_id uuid, p_name text, p_nickname text, p_has_costume boolean, p_costume text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'El nombre es obligatorio'; end if;
  if p_has_costume and coalesce(trim(p_costume), '') = '' then raise exception 'Escribe el disfraz'; end if;
  if exists (select 1 from players where event_id = active_event_id() and id <> p_player_id
             and lower(trim(name)) = lower(trim(p_name))) then
    raise exception 'Ya hay otro invitado con ese nombre';
  end if;
  update players
  set name = trim(p_name), nickname = nullif(trim(p_nickname), ''),
      has_costume = coalesce(p_has_costume, false),
      costume = case when p_has_costume then nullif(trim(p_costume), '') end
  where id = p_player_id and event_id = active_event_id();
end $$;

-- Eliminar un invitado (sus puntos, votos y dispositivos se borran en cascada)
create or replace function public.admin_delete_player(p_player_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_player_id = current_player_id() then raise exception 'No puedes eliminarte a ti mismo'; end if;
  delete from players where id = p_player_id and event_id = active_event_id();
end $$;

-- Reinicio. p_scope:
--   'points' → borra puntos, votos y resultados (los invitados se quedan)
--   'all'    → además borra a todos los invitados excepto los admins (para una nueva fiesta)
-- p_confirm debe ser exactamente 'BORRAR'. p_event_name (opcional) renombra la fiesta.
-- ⚠️ Cuando se agreguen juegos en fases futuras, sus tablas también se limpian aquí.
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
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'costume_contest') then
    alter publication supabase_realtime add table public.costume_contest;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dashboard_state') then
    alter publication supabase_realtime add table public.dashboard_state;
  end if;
end $$;

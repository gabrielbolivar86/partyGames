-- =====================================================================
-- Party Games App · Fase 5: El Impostor + Resultados finales (congelar tabla)
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere fases 1 a 4.
-- =====================================================================

-- =====================================================================
-- RESULTADOS FINALES: congelar la tabla
-- =====================================================================
-- Si frozen_at tiene fecha, la tabla pública muestra los puntos hasta ese momento.
-- Los puntos posteriores se ven recién en la pantalla de "Resultados de la noche".
alter table public.dashboard_state add column if not exists frozen_at timestamptz;

-- ¿La tabla está congelada para quien pregunta?
create or replace function public.board_frozen_at()
returns timestamptz language sql stable security definer set search_path = public as $$
  select case when d.mode = 'final' or is_admin() then null else d.frozen_at end
  from dashboard_state d where d.event_id = active_event_id()
$$;

-- Tabla general (redefinida): respeta el congelado
create or replace function public.get_leaderboard()
returns table (player_id uuid, name text, nickname text, has_costume boolean, costume text, points bigint)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.nickname, p.has_costume, p.costume,
         coalesce(sum(l.points) filter (
           where l.visible and (board_frozen_at() is null or l.created_at <= board_frozen_at())), 0)::bigint as pts
  from players p
  left join points_ledger l on l.player_id = p.id
  where p.event_id = active_event_id() and p.approved
  group by p.id
  order by pts desc, p.name
$$;

-- Resultados finales: total real + cuánto sumó desde que se congeló.
-- Solo responde cuando la pantalla está en modo 'final' (o al admin).
create or replace function public.get_final_results()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_d      dashboard_state%rowtype;
begin
  select * into v_d from dashboard_state where event_id = v_event;
  if v_d.mode is distinct from 'final' and not is_admin() then
    return json_build_object('available', false);
  end if;
  return json_build_object(
    'available', true,
    'event_name', (select name from events where id = v_event),
    'was_frozen', v_d.frozen_at is not null,
    'players', (select coalesce(json_agg(x order by x.points desc, x.name), '[]'::json) from (
                  select p.id as player_id, p.name, p.nickname, p.has_costume, p.costume,
                         coalesce(sum(l.points) filter (where l.visible), 0) as points,
                         coalesce(sum(l.points) filter (where l.visible and v_d.frozen_at is not null
                                                          and l.created_at > v_d.frozen_at), 0) as late_points
                  from players p
                  left join points_ledger l on l.player_id = p.id
                  where p.event_id = v_event and p.approved
                  group by p.id) x),
    'best_costume', (select json_build_object('name', p.name, 'nickname', p.nickname, 'costume', p.costume)
                     from costume_results r
                     join costume_contest c on c.event_id = r.event_id
                     join players p on p.id = r.player_id
                     where r.event_id = v_event and r.place = 1 and c.status = 'closed' and c.reveal_step = 3)
  );
end $$;

create or replace function public.admin_freeze_board(p_freeze boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  update dashboard_state
  set frozen_at = case when p_freeze then now() else null end, updated_at = now()
  where event_id = v_event;
end $$;

-- =====================================================================
-- EL IMPOSTOR · TABLAS
-- =====================================================================

-- Banco de palabras (palabra + 2 pistas para los impostores; se usa una al azar)
-- Las pistas son GENERALES a propósito (no dicen la categoría y algunas tienen doble sentido)
-- para que el impostor tenga que improvisar.
create table if not exists public.impostor_words (
  id   bigint generated always as identity primary key,
  word text not null unique,
  hint text not null
);
alter table public.impostor_words add column if not exists hint2    text;
alter table public.impostor_words add column if not exists category text;

-- Reemplaza el banco por esta lista (las rondas ya jugadas no se ven afectadas)
delete from public.impostor_words where word <> all (array[
  'Pérez Velasco','Avenida Camacho','Villa Fátima','La Ceja','El Prado','Calle Sagárnaga','Plaza Murillo','Valle de la Luna','Mirador Killi Killi','Sopocachi','San Miguel','El Montículo','Garita de Lima','Calle Jaén','Tembladerani','Achumani','Obrajes','Marraqueta','Salteña','Tucumana','Anticucho','Fricasé','Plato Paceño','Api con pastel','Sultana','Quesuminto','Helado de canela','Pasankalla','Chairo','Teleférico','Pumakatari','Chukuta','Minibús','Trufi','Cebra urbana','Cholita paceña','Ekeko','Alasita','Lustrabotas','Bolivia','Perú','Argentina','Brasil','Chile','Colombia','México','Estados Unidos','España','Francia','Italia','Japón','Egipto','Australia','Mochila','Celular','Espejo','Sombrilla','Reloj','Lámpara','Taza','Zapatillas','Llama','Cóndor','Perro','Gato','Oso de anteojos','Pájaro']);
insert into public.impostor_words (category, word, hint, hint2) values
  ('Lugares de La Paz', 'Pérez Velasco', 'Todos pasan por ahí', 'Ruido'),
  ('Lugares de La Paz', 'Avenida Camacho', 'Algo largo', 'Corbatas'),
  ('Lugares de La Paz', 'Villa Fátima', 'Punto de partida', 'Nombre de persona'),
  ('Lugares de La Paz', 'La Ceja', 'Frío', 'Está arriba de algo'),
  ('Lugares de La Paz', 'El Prado', 'Verde', 'Domingo'),
  ('Lugares de La Paz', 'Calle Sagárnaga', 'Recuerdos', 'Cuesta'),
  ('Lugares de La Paz', 'Plaza Murillo', 'Aves', 'Poder'),
  ('Lugares de La Paz', 'Valle de la Luna', 'Formas raras', 'Otro mundo'),
  ('Lugares de La Paz', 'Mirador Killi Killi', 'Fotos', 'Hay que subir'),
  ('Lugares de La Paz', 'Sopocachi', 'Bohemio', 'De noche'),
  ('Lugares de La Paz', 'San Miguel', 'Moderno', 'Santo'),
  ('Lugares de La Paz', 'El Montículo', 'Romántico', 'Árboles'),
  ('Lugares de La Paz', 'Garita de Lima', 'Puestos', 'Otra ciudad'),
  ('Lugares de La Paz', 'Calle Jaén', 'Historias', 'Piedras'),
  ('Lugares de La Paz', 'Tembladerani', 'Fútbol', 'Temblar'),
  ('Lugares de La Paz', 'Achumani', 'Lejos', 'Más calor'),
  ('Lugares de La Paz', 'Obrajes', 'Números', 'Colegios'),
  ('Comida paceña', 'Marraqueta', 'Crujiente', 'Mañana'),
  ('Comida paceña', 'Salteña', 'Jugoso', 'Hay que saber hacerlo'),
  ('Comida paceña', 'Tucumana', 'Calle', 'Salsas'),
  ('Comida paceña', 'Anticucho', 'Noche', 'Fuego'),
  ('Comida paceña', 'Fricasé', 'Picante', 'Después de la fiesta'),
  ('Comida paceña', 'Plato Paceño', 'Varios en uno', 'Hervido'),
  ('Comida paceña', 'Api con pastel', 'Pareja perfecta', 'Frío afuera'),
  ('Comida paceña', 'Sultana', 'Barato', 'Cáscara'),
  ('Comida paceña', 'Quesuminto', 'Se derrite', 'Hoja'),
  ('Comida paceña', 'Helado de canela', 'Esquina', 'Colores'),
  ('Comida paceña', 'Pasankalla', 'Liviano', 'Bolsa'),
  ('Comida paceña', 'Chairo', 'Cuchara', 'Tiene de todo'),
  ('Cotidiano y cultura', 'Teleférico', 'Colores', 'Vista'),
  ('Cotidiano y cultura', 'Pumakatari', 'Felino', 'Paradas'),
  ('Cotidiano y cultura', 'Chukuta', 'Una palabra', 'Identidad'),
  ('Cotidiano y cultura', 'Minibús', 'Gritos', 'Apretado'),
  ('Cotidiano y cultura', 'Trufi', 'Compartir', 'Ruta'),
  ('Cotidiano y cultura', 'Cebra urbana', 'Rayas', 'Educación'),
  ('Cotidiano y cultura', 'Cholita paceña', 'Elegancia', 'Sombrero'),
  ('Cotidiano y cultura', 'Ekeko', 'Suerte', 'Cargado'),
  ('Cotidiano y cultura', 'Alasita', 'Pequeño', 'Enero'),
  ('Cotidiano y cultura', 'Lustrabotas', 'Brillo', 'Cara cubierta'),
  ('Países', 'Bolivia', 'Casa', 'Le falta algo'),
  ('Países', 'Perú', 'Vecino', 'Historia'),
  ('Países', 'Argentina', 'Carne', 'Pasión'),
  ('Países', 'Brasil', 'Grande', 'Alegría'),
  ('Países', 'Chile', 'Largo', 'Picante'),
  ('Países', 'Colombia', 'Café', 'Ritmo'),
  ('Países', 'México', 'Sombrero', 'Música'),
  ('Países', 'Estados Unidos', 'Películas', 'Estrellas'),
  ('Países', 'España', 'Idioma', 'Antiguo'),
  ('Países', 'Francia', 'Moda', 'Romántico'),
  ('Países', 'Italia', 'Forma', 'Masa'),
  ('Países', 'Japón', 'Tecnología', 'Isla'),
  ('Países', 'Egipto', 'Arena', 'Antiguo'),
  ('Países', 'Australia', 'Lejos', 'Saltar'),
  ('Objetos', 'Mochila', 'Espalda', 'Cargar'),
  ('Objetos', 'Celular', 'Bolsillo', 'Pantalla'),
  ('Objetos', 'Espejo', 'Vanidad', 'Vidrio'),
  ('Objetos', 'Sombrilla', 'Clima', 'Se abre'),
  ('Objetos', 'Reloj', 'Muñeca', 'Números'),
  ('Objetos', 'Lámpara', 'Mesa', 'Ideas'),
  ('Objetos', 'Taza', 'Mañana', 'Oreja'),
  ('Objetos', 'Zapatillas', 'Correr', 'Pares'),
  ('Animales', 'Llama', 'Fuego', 'Lana'),
  ('Animales', 'Cóndor', 'Alto', 'Símbolo'),
  ('Animales', 'Perro', 'Fiel', 'Calle'),
  ('Animales', 'Gato', 'Siete', 'Independiente'),
  ('Animales', 'Oso de anteojos', 'Ver bien', 'Bosque'),
  ('Animales', 'Pájaro', 'Nido', 'Cantar')
on conflict (word) do update set category = excluded.category, hint = excluded.hint, hint2 = excluded.hint2;

-- Estado público del juego (sin secretos). Lo escuchan todos en tiempo real.
create table if not exists public.impostor_game (
  event_id         uuid primary key references public.events(id) on delete cascade,
  status           text not null default 'none' check (status in ('none', 'playing', 'finished')),
  current_round_id uuid,
  vote_no          integer not null default 0,
  vote_kind        text not null default 'defense' check (vote_kind in ('defense', 'elimination')),
  vote_status      text not null default 'none' check (vote_status in ('none', 'open', 'closed')),
  last_result      json,          -- resultado de la última votación cerrada (público)
  pts_crew         integer not null default 5,
  pts_impostor     integer not null default 12,
  updated_at       timestamptz not null default now()
);

-- Rondas (PRIVADO: tiene la palabra)
create table if not exists public.impostor_rounds (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.events(id) on delete cascade,
  number         integer not null,
  word           text not null,
  hint           text not null,
  impostor_count integer not null,
  status         text not null default 'playing' check (status in ('playing', 'finished', 'cancelled')),
  winner         text check (winner in ('crew', 'impostors')),
  win_reason     text,
  created_at     timestamptz not null default now(),
  finished_at    timestamptz
);

-- Participantes (PRIVADO: tiene el rol)
create table if not exists public.impostor_players (
  round_id    uuid not null references public.impostor_rounds(id) on delete cascade,
  player_id   uuid not null references public.players(id) on delete cascade,
  role        text not null check (role in ('crew', 'impostor')),
  speak_order integer not null,
  alive       boolean not null default true,
  guess       text,
  primary key (round_id, player_id)
);

-- Votos (PÚBLICO: la votación es a mano alzada, se muestra en la TV)
create table if not exists public.impostor_votes (
  round_id   uuid not null references public.impostor_rounds(id) on delete cascade,
  vote_no    integer not null,
  voter_id   uuid not null references public.players(id) on delete cascade,
  target_id  uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (round_id, vote_no, voter_id)
);

insert into public.impostor_game (event_id) select id from public.events on conflict do nothing;

-- =====================================================================
-- SEGURIDAD
-- =====================================================================
alter table public.impostor_words   enable row level security;
alter table public.impostor_game    enable row level security;
alter table public.impostor_rounds  enable row level security;
alter table public.impostor_players enable row level security;
alter table public.impostor_votes   enable row level security;

drop policy if exists "impostor: lectura pública" on public.impostor_game;
create policy "impostor: lectura pública" on public.impostor_game for select to anon, authenticated using (true);
drop policy if exists "impostor votos: lectura pública" on public.impostor_votes;
create policy "impostor votos: lectura pública" on public.impostor_votes for select to anon, authenticated using (true);
-- impostor_words, impostor_rounds, impostor_players: sin políticas → solo vía funciones

grant select on public.impostor_game, public.impostor_votes to anon, authenticated;

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
  return v_event;
end $$;

-- Normaliza para comparar palabras (minúsculas, sin tildes ni espacios extra)
create or replace function public.norm_word(p text)
returns text language sql immutable as $$
  select regexp_replace(
           translate(lower(trim(coalesce(p, ''))), 'áéíóúüñ', 'aeiouun'),
           '[^a-z0-9]+', '', 'g')
$$;

-- Lista pública de participantes de una ronda (rol revelado solo si fue eliminado o terminó)
create or replace function public.impostor_players_json(p_round uuid)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
           'id', p.id, 'name', coalesce(p.nickname, p.name), 'order', ip.speak_order, 'alive', ip.alive,
           'role', case when not ip.alive or r.status = 'finished' then ip.role end)
         order by ip.speak_order), '[]'::json)
  from impostor_players ip
  join players p on p.id = ip.player_id
  join impostor_rounds r on r.id = ip.round_id
  where ip.round_id = p_round
$$;

-- Conteo de la votación actual: a quién votó cada uno (público)
create or replace function public.impostor_tally_json(p_round uuid, p_vote_no integer)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(t order by t.votes desc, t.name), '[]'::json) from (
    select coalesce(pt.nickname, pt.name) as name, v.target_id as id, count(*) as votes,
           json_agg(coalesce(pv.nickname, pv.name) order by pv.name) as voters
    from impostor_votes v
    join players pt on pt.id = v.target_id
    join players pv on pv.id = v.voter_id
    where v.round_id = p_round and v.vote_no = p_vote_no
    group by v.target_id, pt.nickname, pt.name
  ) t
$$;

-- Termina la ronda, reparte puntos y deja todo visible
create or replace function public.impostor_finish_round(p_round uuid, p_winner text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     impostor_game%rowtype;
  v_r     impostor_rounds%rowtype;
begin
  select * into v_g from impostor_game where event_id = v_event;
  select * into v_r from impostor_rounds where id = p_round;
  if v_r.status <> 'playing' then return; end if;

  if p_winner = 'crew' and v_g.pts_crew <> 0 then
    insert into points_ledger (event_id, player_id, source, points, reason)
    select v_event, ip.player_id, 'impostor', v_g.pts_crew, 'Tripulación ganó (impostor ronda #' || v_r.number || ')'
    from impostor_players ip where ip.round_id = p_round and ip.role = 'crew';
  elsif p_winner = 'impostors' and v_g.pts_impostor <> 0 then
    insert into points_ledger (event_id, player_id, source, points, reason)
    select v_event, ip.player_id, 'impostor', v_g.pts_impostor, 'Impostor ganador (ronda #' || v_r.number || ')'
    from impostor_players ip where ip.round_id = p_round and ip.role = 'impostor';
  end if;

  update impostor_rounds set status = 'finished', winner = p_winner, win_reason = p_reason, finished_at = now()
  where id = p_round;
  update impostor_game set status = 'finished', vote_status = 'closed', updated_at = now() where event_id = v_event;
end $$;

-- Revisa si alguien ganó tras una eliminación
create or replace function public.impostor_check_win(p_round uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_imp  integer;
  v_crew integer;
begin
  select count(*) filter (where role = 'impostor' and alive), count(*) filter (where role = 'crew' and alive)
  into v_imp, v_crew from impostor_players where round_id = p_round;
  if v_imp = 0 then
    perform impostor_finish_round(p_round, 'crew', '¡Descubrieron a todos los impostores!');
  elsif v_imp >= v_crew then
    perform impostor_finish_round(p_round, 'impostors', 'Los impostores igualaron a la tripulación');
  end if;
end $$;

-- =====================================================================
-- RPC: INVITADOS Y PANTALLA
-- =====================================================================

-- Vista del celular del invitado
create or replace function public.get_impostor_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      impostor_game%rowtype;
  v_r      impostor_rounds%rowtype;
  v_me     impostor_players%rowtype;
begin
  select * into v_g from impostor_game where event_id = v_event;
  if v_g.current_round_id is null or v_g.status = 'none' then
    return json_build_object('status', 'none');
  end if;
  select * into v_r from impostor_rounds where id = v_g.current_round_id;
  if v_r.id is null then return json_build_object('status', 'none'); end if;
  select * into v_me from impostor_players where round_id = v_r.id and player_id = v_player;

  return json_build_object(
    'status', v_g.status,
    'number', v_r.number,
    'impostor_count', v_r.impostor_count,
    'participant', v_me.player_id is not null,
    'role', v_me.role,
    'alive', v_me.alive,
    'word', case when v_me.role = 'crew' or v_r.status = 'finished' then v_r.word end,
    'hint', case when v_me.role = 'impostor' then v_r.hint end,
    'can_guess', v_me.role = 'impostor' and v_me.guess is null and v_r.status = 'playing',
    'my_guess', v_me.guess,
    'players', impostor_players_json(v_r.id),
    'vote', json_build_object('no', v_g.vote_no, 'kind', v_g.vote_kind, 'status', v_g.vote_status,
              'my_vote', (select target_id from impostor_votes
                          where round_id = v_r.id and vote_no = v_g.vote_no and voter_id = v_player)),
    'last_result', v_g.last_result,
    'winner', v_r.winner,
    'win_reason', v_r.win_reason
  );
end $$;

-- Lo que muestra la TV
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
      'eligible', (select count(*) from impostor_players where round_id = v_r.id and alive)),
    'last_result', v_g.last_result,
    'winner', v_r.winner,
    'win_reason', v_r.win_reason,
    'word', case when v_r.status = 'finished' then v_r.word end
  );
end $$;

-- Votar (solo participantes vivos, mientras la votación está abierta; se puede cambiar)
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
  if not exists (select 1 from impostor_players where round_id = v_g.current_round_id and player_id = v_player and alive) then
    return json_build_object('ok', false, 'error', 'Solo votan los jugadores que siguen en la ronda');
  end if;
  if p_target = v_player or not exists (select 1 from impostor_players
                                        where round_id = v_g.current_round_id and player_id = p_target and alive) then
    return json_build_object('ok', false, 'error', 'Elige a otro jugador que siga en la ronda');
  end if;

  insert into impostor_votes (round_id, vote_no, voter_id, target_id)
  values (v_g.current_round_id, v_g.vote_no, v_player, p_target)
  on conflict (round_id, vote_no, voter_id) do update set target_id = excluded.target_id, created_at = now();

  update impostor_game set updated_at = now() where event_id = v_event;
  return json_build_object('ok', true);
end $$;

-- Un impostor (vivo o eliminado) tiene UN intento para adivinar la palabra
create or replace function public.guess_impostor_word(p_guess text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid := active_event_id();
  v_player uuid := current_player_id();
  v_g      impostor_game%rowtype;
  v_r      impostor_rounds%rowtype;
  v_me     impostor_players%rowtype;
  v_ok     boolean;
begin
  if v_player is null then raise exception 'Tu celular no está aprobado'; end if;
  select * into v_g from impostor_game where event_id = v_event;
  select * into v_r from impostor_rounds where id = v_g.current_round_id;
  select * into v_me from impostor_players where round_id = v_r.id and player_id = v_player;
  if v_r.status is distinct from 'playing' or v_me.role is distinct from 'impostor' then
    return json_build_object('ok', false, 'error', 'No puedes adivinar ahora');
  end if;
  if v_me.guess is not null then return json_build_object('ok', false, 'error', 'Ya usaste tu intento'); end if;
  if coalesce(trim(p_guess), '') = '' then return json_build_object('ok', false, 'error', 'Escribe una palabra'); end if;

  v_ok := norm_word(p_guess) = norm_word(v_r.word);
  update impostor_players set guess = left(trim(p_guess), 60) where round_id = v_r.id and player_id = v_player;
  if v_ok then
    update impostor_game
    set last_result = json_build_object('type', 'guess', 'name', (select coalesce(nickname, name) from players where id = v_player),
                                        'guess', trim(p_guess), 'correct', true)
    where event_id = v_event;
    perform impostor_finish_round(v_r.id, 'impostors', '¡Un impostor adivinó la palabra!');
  end if;
  update impostor_game set updated_at = now() where event_id = v_event;
  return json_build_object('ok', true, 'correct', v_ok);
end $$;

-- =====================================================================
-- RPC: ADMIN
-- =====================================================================

create or replace function public.admin_impostor_overview()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_event uuid := active_event_id();
  v_g     impostor_game%rowtype;
  v_r     impostor_rounds%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from impostor_game where event_id = v_event;
  if v_g.current_round_id is not null then
    select * into v_r from impostor_rounds where id = v_g.current_round_id;
  end if;
  return json_build_object(
    'status', coalesce(v_g.status, 'none'),
    'settings', json_build_object('crew', coalesce(v_g.pts_crew, 5), 'impostor', coalesce(v_g.pts_impostor, 12)),
    'words_count', (select count(*) from impostor_words),
    'categories', (select coalesce(json_agg(json_build_object('name', c.category, 'count', c.n) order by c.category), '[]'::json)
                   from (select category, count(*) as n from impostor_words where category is not null group by category) c),
    'rounds_played', (select count(*) from impostor_rounds where event_id = v_event and status = 'finished'),
    'round', case when v_r.id is null then null else json_build_object(
      'number', v_r.number, 'word', v_r.word, 'hint', v_r.hint, 'impostor_count', v_r.impostor_count,
      'status', v_r.status, 'winner', v_r.winner, 'win_reason', v_r.win_reason,
      'impostors', (select json_agg(coalesce(p.nickname, p.name)) from impostor_players ip join players p on p.id = ip.player_id
                    where ip.round_id = v_r.id and ip.role = 'impostor'),
      'guesses', (select coalesce(json_agg(json_build_object('name', coalesce(p.nickname, p.name), 'guess', ip.guess)), '[]'::json)
                  from impostor_players ip join players p on p.id = ip.player_id
                  where ip.round_id = v_r.id and ip.guess is not null),
      'players', impostor_players_json(v_r.id),
      'vote', json_build_object('no', v_g.vote_no, 'kind', v_g.vote_kind, 'status', v_g.vote_status,
                'tally', case when v_g.vote_no > 0 then impostor_tally_json(v_r.id, v_g.vote_no) else '[]'::json end,
                'voted', (select count(*) from impostor_votes where round_id = v_r.id and vote_no = v_g.vote_no),
                'eligible', (select count(*) from impostor_players where round_id = v_r.id and alive)),
      'last_result', v_g.last_result) end
  );
end $$;

create or replace function public.admin_impostor_settings(p_crew integer, p_impostor integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if least(p_crew, p_impostor) < 0 or greatest(p_crew, p_impostor) > 500 then raise exception 'Puntos fuera de rango'; end if;
  v_event := ensure_event_rows();
  update impostor_game set pts_crew = p_crew, pts_impostor = p_impostor, updated_at = now() where event_id = v_event;
end $$;

-- Nueva ronda: jugadores elegidos, N impostores al azar, palabra (propia o al azar del banco)
drop function if exists public.admin_impostor_start(uuid[], integer, text, text);
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
  where id = any(p_players) and event_id = v_event and approved;
  if v_n < 3 then raise exception 'Se necesitan al menos 3 jugadores'; end if;
  if p_impostors < 1 or p_impostors * 2 >= v_n then
    raise exception 'Con % jugadores puede haber entre 1 y % impostores', v_n, greatest(1, (v_n - 1) / 2);
  end if;

  if coalesce(trim(p_word), '') <> '' then
    if coalesce(trim(p_hint), '') = '' then raise exception 'Escribe también la pista para los impostores'; end if;
    v_word := trim(p_word); v_hint := trim(p_hint);
  else
    -- Al azar, preferentemente una palabra que no se haya usado en esta fiesta
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

  -- Orden para hablar al azar; los impostores, al azar entre ellos
  insert into impostor_players (round_id, player_id, role, speak_order)
  select v_round, x.id,
         case when x.imp_rank <= p_impostors then 'impostor' else 'crew' end,
         x.speak
  from (
    select p.id,
           row_number() over (order by random()) as imp_rank,
           row_number() over (order by random()) as speak
    from players p
    where p.id = any(p_players) and p.event_id = v_event and p.approved
  ) x;

  update impostor_game
  set status = 'playing', current_round_id = v_round, vote_no = 0, vote_kind = 'defense', vote_status = 'none',
      last_result = null, updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'impostor', updated_at = now() where event_id = v_event;
end $$;

-- Abrir una votación: 'defense' (nadie sale) o 'elimination'
create or replace function public.admin_impostor_open_vote(p_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_kind not in ('defense', 'elimination') then raise exception 'Tipo inválido'; end if;
  v_event := ensure_event_rows();
  if (select status from impostor_game where event_id = v_event) <> 'playing' then
    raise exception 'No hay una ronda en juego';
  end if;
  update impostor_game
  set vote_no = vote_no + 1, vote_kind = p_kind, vote_status = 'open', updated_at = now()
  where event_id = v_event;
end $$;

-- Cambiar el tipo de la votación abierta (defensa ↔ eliminación)
create or replace function public.admin_impostor_set_vote_kind(p_kind text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_kind not in ('defense', 'elimination') then raise exception 'Tipo inválido'; end if;
  update impostor_game set vote_kind = p_kind, updated_at = now()
  where event_id = active_event_id() and vote_status = 'open';
end $$;

-- Cerrar la votación. Si es de eliminación: sale el más votado (empate = nadie sale)
create or replace function public.admin_impostor_close_vote()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event  uuid;
  v_g      impostor_game%rowtype;
  v_top    uuid;
  v_topn   integer;
  v_ties   integer;
  v_role   text;
  v_name   text;
  v_result json;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  v_event := ensure_event_rows();
  select * into v_g from impostor_game where event_id = v_event for update;
  if v_g.vote_status <> 'open' then raise exception 'No hay una votación abierta'; end if;

  -- Solo cuentan votos de jugadores vivos hacia jugadores vivos
  select v.target_id, count(*) into v_top, v_topn
  from impostor_votes v
  join impostor_players tv on tv.round_id = v.round_id and tv.player_id = v.target_id and tv.alive
  join impostor_players vv on vv.round_id = v.round_id and vv.player_id = v.voter_id and vv.alive
  where v.round_id = v_g.current_round_id and v.vote_no = v_g.vote_no
  group by v.target_id order by count(*) desc limit 1;

  select count(*) into v_ties from (
    select v.target_id
    from impostor_votes v
    join impostor_players tv on tv.round_id = v.round_id and tv.player_id = v.target_id and tv.alive
    join impostor_players vv on vv.round_id = v.round_id and vv.player_id = v.voter_id and vv.alive
    where v.round_id = v_g.current_round_id and v.vote_no = v_g.vote_no
    group by v.target_id having count(*) = v_topn) t;

  if v_top is not null then select coalesce(nickname, name) into v_name from players where id = v_top; end if;

  if v_g.vote_kind = 'defense' then
    v_result := json_build_object('type', 'defense', 'vote_no', v_g.vote_no, 'top', v_name, 'votes', v_topn, 'tie', v_ties > 1);
  elsif v_top is null then
    v_result := json_build_object('type', 'none', 'vote_no', v_g.vote_no);
  elsif v_ties > 1 then
    v_result := json_build_object('type', 'tie', 'vote_no', v_g.vote_no, 'votes', v_topn);
  else
    update impostor_players set alive = false where round_id = v_g.current_round_id and player_id = v_top
    returning role into v_role;
    v_result := json_build_object('type', 'eliminated', 'vote_no', v_g.vote_no, 'name', v_name,
                                  'votes', v_topn, 'was_impostor', v_role = 'impostor');
  end if;

  update impostor_game set vote_status = 'closed', last_result = v_result, updated_at = now() where event_id = v_event;
  if v_result->>'type' = 'eliminated' then perform impostor_check_win(v_g.current_round_id); end if;
end $$;

-- Terminar a mano (ej. se acabó el tiempo y los impostores no fueron descubiertos)
create or replace function public.admin_impostor_finish(p_winner text)
returns void language plpgsql security definer set search_path = public as $$
declare v_g impostor_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_winner not in ('crew', 'impostors') then raise exception 'Ganador inválido'; end if;
  select * into v_g from impostor_game where event_id = active_event_id();
  if v_g.status <> 'playing' then raise exception 'No hay una ronda en juego'; end if;
  perform impostor_finish_round(v_g.current_round_id, p_winner,
    case when p_winner = 'crew' then 'El admin dio la victoria a la tripulación'
         else 'Los impostores no fueron descubiertos' end);
end $$;

-- Cancelar la ronda sin puntos
create or replace function public.admin_impostor_cancel()
returns void language plpgsql security definer set search_path = public as $$
declare v_g impostor_game%rowtype;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  select * into v_g from impostor_game where event_id = active_event_id();
  if v_g.current_round_id is not null then
    update impostor_rounds set status = 'cancelled' where id = v_g.current_round_id and status = 'playing';
  end if;
  update impostor_game
  set status = 'none', current_round_id = null, vote_no = 0, vote_status = 'none', last_result = null, updated_at = now()
  where event_id = active_event_id();
end $$;

-- =====================================================================
-- PANTALLA Y REINICIO (redefinidos con los modos nuevos)
-- =====================================================================
create or replace function public.admin_set_dashboard(p_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_mode not in ('leaderboard', 'costume_reveal', 'codes', 'persona', 'impostor', 'final') then
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
  -- Pantalla (y descongelar)
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
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'impostor_game') then
    alter publication supabase_realtime add table public.impostor_game;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'impostor_votes') then
    alter publication supabase_realtime add table public.impostor_votes;
  end if;
end $$;

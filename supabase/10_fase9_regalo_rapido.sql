-- =====================================================================
-- Party Games App · Fase 9: "El Regalo" más rápido
--
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- ✅ NO borra datos. Se puede correr varias veces. Requiere 09_fase8_ausentes_pestanas.sql.
--
--   • El tiempo es POR PREGUNTA (30 s por defecto): se escribe una pregunta a la vez.
--   • Al cerrar la votación, el podio sale completo en la TV y los puntos se suman al instante
--     (ya no hay revelación 3.º → 2.º → 1.º).
-- =====================================================================

create or replace function public.admin_gift_timer(p_seconds integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  if not is_admin() then raise exception 'Solo el admin puede hacer esto'; end if;
  if p_seconds <> 0 and p_seconds not between 5 and 300 then raise exception 'Entre 5 y 300 segundos por pregunta (0 = sin tiempo)'; end if;
  v_event := ensure_event_rows();
  update gift_game set writing_seconds = p_seconds, updated_at = now() where event_id = v_event;
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
  if v_g.status in ('writing', 'reading', 'voting') then raise exception 'Ya hay un Regalo en curso'; end if;

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
      -- 3 preguntas: cada una con su tiempo (la 1.ª cierra a los N s, la 2.ª a los 2N, la 3.ª a los 3N)
      ends_at = case when writing_seconds > 0 then now() + make_interval(secs => writing_seconds * 3) end,
      updated_at = now()
  where event_id = v_event;
  update dashboard_state set mode = 'gift', updated_at = now() where event_id = v_event;
end $$;

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
    'seconds', v_g.writing_seconds,
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
         'El Regalo: frase en ' || c.place || '.º lugar', true
  from gift_chains c
  cross join lateral (select distinct v.pid from (values (coalesce(c.object_writer_id, c.giver_id)), (c.use_writer_id), (c.reaction_writer_id)) as v(pid)) as a
  where c.round_id = v_g.current_round_id and c.place <= 3 and c.votes > 0
    and (case c.place when 1 then v_g.pts_1 when 2 then v_g.pts_2 else v_g.pts_3 end) <> 0;

  update gift_game set status = 'results', reveal_step = 3, updated_at = now() where event_id = v_event;
  update gift_rounds set status = 'finished' where id = v_g.current_round_id;
end $$;

grant execute on all functions in schema public to anon, authenticated;

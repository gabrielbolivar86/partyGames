-- =====================================================================
-- Fase 12: en El Regalo ya se puede votar por las frases en las que participaste
-- Requiere 09_fase8_ausentes_pestanas.sql. Se puede correr más de una vez.
-- =====================================================================

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
  where c.round_id = v_g.current_round_id and c.id = any(p_chains);

  perform gift_refresh_progress(v_g.current_round_id);
  return json_build_object('ok', true);
end $$;

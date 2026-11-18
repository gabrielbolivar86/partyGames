-- =====================================================================
-- Hacerte DUEÑO de la app (puedes crear fiestas y anfitriones)
-- Correr DESPUÉS de 11_fase10_multifiesta.sql.
-- 1) Cambia 'Gabriel' por el nombre EXACTO con el que te registraste.
-- 2) Supabase → SQL Editor → Run.
-- 3) Abre la app en ese celular/computador y entra a #/owner
-- Todos los dispositivos vinculados a ese invitado quedan como dueños.
-- =====================================================================

insert into public.app_owners (auth_user_id)
select d.auth_user_id
from public.player_devices d
join public.players p on p.id = d.player_id
where lower(p.name) = lower('Gabriel') and d.status = 'approved'
on conflict do nothing;

-- Comprobar:
select o.auth_user_id, o.created_at from public.app_owners o;

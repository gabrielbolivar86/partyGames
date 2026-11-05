-- =====================================================================
-- Hacerte admin (correr DESPUÉS de registrarte en la app desde tu celular)
-- 1) Cambia 'Gabriel' por el nombre EXACTO con el que te registraste.
-- 2) Supabase → SQL Editor → Run.
-- 3) En la app toca "Revisar" o recarga la página.
-- =====================================================================

update public.players
set is_admin = true, approved = true
where lower(name) = lower('Gabriel');

update public.player_devices
set status = 'approved'
where player_id in (select id from public.players where lower(name) = lower('Gabriel'));

-- Comprobar:
select p.name, p.is_admin, p.approved, d.status
from public.players p
left join public.player_devices d on d.player_id = p.id
where lower(p.name) = lower('Gabriel');

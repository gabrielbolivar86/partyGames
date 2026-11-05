import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isConfigured = Boolean(url && key)

// La sesión se guarda en el navegador (localStorage), así el invitado sigue
// dentro aunque cierre la pestaña.
export const supabase = isConfigured
  ? createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } })
  : null

// Convierte errores de Supabase/Postgres en un mensaje legible
export function errorMessage(err) {
  if (!err) return ''
  return err.message || String(err)
}

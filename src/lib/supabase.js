import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isConfigured = Boolean(url && key)

// Fiesta actual (el "slug" de la URL #/p/<slug>/...). Va en cada petición como
// header "x-party" y el servidor (active_event_id) lo usa para separar las fiestas.
let currentParty = null
export const setParty = (slug) => { currentParty = slug || null }
export const getParty = () => currentParty

function partyFetch(input, init = {}) {
  if (!currentParty) return fetch(input, init)
  const headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined))
  headers.set('x-party', currentParty)
  return fetch(input, { ...init, headers })
}

// La sesión se guarda en el navegador (localStorage), así el invitado sigue
// dentro aunque cierre la pestaña.
export const supabase = isConfigured
  ? createClient(url, key, {
      auth: { persistSession: true, autoRefreshToken: true },
      global: { fetch: partyFetch },
    })
  : null

// Convierte errores de Supabase/Postgres en un mensaje legible
export function errorMessage(err) {
  if (!err) return ''
  return err.message || String(err)
}

// Asegura una sesión anónima en este navegador (igual que hace useMe)
export async function ensureSession() {
  const { data: { session } } = await supabase.auth.getSession()
  if (session) return null
  const { error } = await supabase.auth.signInAnonymously()
  return error ? 'No se pudo iniciar sesión: ' + error.message : null
}

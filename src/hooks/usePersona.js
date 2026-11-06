import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useRealtimeRefresh } from './useRealtimeRefresh'

/**
 * Llama a un RPC del juego "¿Quién es el personaje?" y lo refresca en tiempo real
 * (cada voto o cambio de ronda actualiza la tabla pública persona_game).
 * Además calcula la diferencia entre el reloj del servidor y el del celular,
 * para que la cuenta regresiva sea igual en todas las pantallas.
 */
export function usePersonaRpc(rpcName, { enabled = true } = {}) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const [offset, setOffset] = useState(0)

  const refresh = useCallback(async () => {
    const t0 = Date.now()
    const { data, error } = await supabase.rpc(rpcName)
    const t1 = Date.now()
    if (error) { setError(error.message); return }
    setError(null)
    setData(data)
    if (data?.now) setOffset(new Date(data.now).getTime() - (t0 + t1) / 2)
  }, [rpcName])

  useEffect(() => { if (enabled) refresh() }, [refresh, enabled])
  useRealtimeRefresh(['persona_game'], refresh, { enabled, debounceMs: 150 })

  return { data, error, refresh, offset }
}

// Segundos que faltan para endsAt (con el reloj corregido)
export function useCountdown(endsAt, offset) {
  const calc = () => (endsAt ? Math.max(0, Math.ceil((new Date(endsAt).getTime() - (Date.now() + offset)) / 1000)) : 0)
  const [left, setLeft] = useState(calc)
  const ref = useRef()
  ref.current = calc

  useEffect(() => {
    setLeft(ref.current())
    if (!endsAt) return
    const t = setInterval(() => setLeft(ref.current()), 250)
    return () => clearInterval(t)
  }, [endsAt, offset])

  return left
}

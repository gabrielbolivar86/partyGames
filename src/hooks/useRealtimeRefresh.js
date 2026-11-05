import { useEffect, useRef } from 'react'
import { supabase } from '../lib/supabase'

/**
 * Patrón de tiempo real que usamos en toda la app:
 *   1. Nos suscribimos (WebSocket) a cambios en una o varias tablas.
 *   2. Cuando llega un aviso de cambio, NO usamos el dato que viene en el aviso:
 *      volvemos a pedir los datos completos (refetch). Es más simple y nunca se desincroniza.
 *   3. Agrupamos avisos seguidos (debounce) para no pedir 10 veces lo mismo.
 *   4. Red de seguridad: refrescamos al volver a la app (celular desbloqueado)
 *      y cada `fallbackMs` por si se cortó el WebSocket.
 */
export function useRealtimeRefresh(tables, refresh, { fallbackMs = 30000, debounceMs = 250, enabled = true } = {}) {
  const refreshRef = useRef(refresh)
  refreshRef.current = refresh
  const key = tables.join(',')

  useEffect(() => {
    if (!enabled || !supabase) return
    let timer = null
    const schedule = () => {
      clearTimeout(timer)
      timer = setTimeout(() => refreshRef.current(), debounceMs)
    }

    // Nombre único por componente, para no compartir canal por accidente
    const channel = supabase.channel(`rt-${key}-${Math.random().toString(36).slice(2, 8)}`)
    for (const table of tables) {
      channel.on('postgres_changes', { event: '*', schema: 'public', table }, schedule)
    }
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') schedule() // al (re)conectar, ponernos al día
    })

    const onVisible = () => document.visibilityState === 'visible' && schedule()
    document.addEventListener('visibilitychange', onVisible)
    const interval = setInterval(schedule, fallbackMs)

    return () => {
      clearTimeout(timer)
      clearInterval(interval)
      document.removeEventListener('visibilitychange', onVisible)
      supabase.removeChannel(channel)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, enabled, fallbackMs, debounceMs])
}

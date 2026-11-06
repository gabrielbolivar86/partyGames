import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useRealtimeRefresh } from './useRealtimeRefresh'

// Caza de códigos: estado para el invitado (sus códigos, límite, puntos)
export function useHunt() {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_hunt_status')
    if (error) setError(error.message)
    else { setError(null); setData(data) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['code_hunt'], refresh)

  return { data, error, refresh }
}

// Tablero público para la pantalla
export function useHuntBoard() {
  const [data, setData] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_hunt_board')
    if (!error) setData(data)
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['hunt_claims', 'code_hunt'], refresh, { debounceMs: 150 })

  return data
}

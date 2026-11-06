import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useRealtimeRefresh } from './useRealtimeRefresh'

// Estado del concurso de disfraces para el invitado: candidatos, su ranking guardado y el podio revelado.
// Se actualiza solo cuando: llega alguien nuevo (players), o el admin abre/cierra/revela (costume_contest).
export function useCostume() {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_costume_status')
    if (error) setError(error.message)
    else { setError(null); setData(data) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['costume_contest', 'players'], refresh)

  return { data, error, refresh }
}

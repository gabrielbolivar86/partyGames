import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useRealtimeRefresh } from './useRealtimeRefresh'

// Qué debe mostrar la pantalla (modo) + datos del concurso de disfraces revelados.
export function useDashboard() {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_dashboard')
    if (error) setError(error.message)
    else { setError(null); setData(data) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['dashboard_state', 'costume_contest'], refresh, { debounceMs: 100 })

  return { data, error, refresh }
}

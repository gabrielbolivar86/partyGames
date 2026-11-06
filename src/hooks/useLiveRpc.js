import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useRealtimeRefresh } from './useRealtimeRefresh'

// Llama a un RPC y lo vuelve a pedir cada vez que cambian las tablas indicadas (patrón "aviso + volver a pedir")
export function useLiveRpc(rpcName, tables, { debounceMs = 150, enabled = true } = {}) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc(rpcName)
    if (error) setError(error.message)
    else { setError(null); setData(data) }
  }, [rpcName])

  useEffect(() => { if (enabled) refresh() }, [refresh, enabled])
  useRealtimeRefresh(tables, refresh, { debounceMs, enabled })

  return { data, error, refresh }
}

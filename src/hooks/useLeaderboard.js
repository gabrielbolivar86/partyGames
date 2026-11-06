import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useRealtimeRefresh } from './useRealtimeRefresh'

// Tabla general en vivo. La usan el dashboard, el invitado y el admin.
export function useLeaderboard() {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_leaderboard')
    if (error) setError(error.message)
    else {
      setError(null)
      setRows(withRanks(data || []))
    }
    setLoading(false)
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['points_ledger', 'players', 'dashboard_state'], refresh)

  return { rows, loading, error, refresh }
}

// Empates comparten posición: 10, 10, 7 → 1, 1, 3
function withRanks(rows) {
  let lastPoints = null
  let lastRank = 0
  return rows.map((r, i) => {
    const points = Number(r.points)
    const rank = points === lastPoints ? lastRank : i + 1
    lastPoints = points
    lastRank = rank
    return { ...r, points, rank }
  })
}

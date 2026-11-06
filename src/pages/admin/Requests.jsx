import { useCallback, useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useRealtimeRefresh } from '../../hooks/useRealtimeRefresh'

// Solicitudes de acceso (registro nuevo u otro dispositivo)
export function usePendingRequests() {
  const [items, setItems] = useState([])
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('admin_pending')
    if (error) setError(error.message)
    else { setError(null); setItems(data || []) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['player_devices'], refresh, { fallbackMs: 10000 })

  return { items, error, setError, refresh }
}

export default function Requests({ pending }) {
  const { items, error, setError, refresh } = pending
  const [busyId, setBusyId] = useState(null)

  async function resolve(id, approve) {
    setBusyId(id)
    const { error } = await supabase.rpc('admin_resolve_device', { p_device_id: id, p_approve: approve })
    setBusyId(null)
    if (error) setError(errorMessage(error))
    refresh()
  }

  return (
    <section className="card">
      <h3>🚪 Solicitudes {items.length > 0 && <span className="badge">{items.length}</span>}</h3>
      {error && <div className="error">{error}</div>}
      {items.length === 0 && <p className="muted">No hay solicitudes pendientes.</p>}
      <ul className="requests">
        {items.map((r) => (
          <li key={r.device_id}>
            <div>
              <strong>{r.name}</strong>{r.nickname && <span className="muted"> “{r.nickname}”</span>}
              <div className="small muted">
                {r.kind === 'link' ? '📱 Otro dispositivo para este perfil' : (r.has_costume ? `🧛 ${r.costume}` : 'Sin disfraz')}
              </div>
            </div>
            <div className="row">
              <button className="btn small ok" disabled={busyId === r.device_id} onClick={() => resolve(r.device_id, true)}>Aprobar</button>
              <button className="btn small danger" disabled={busyId === r.device_id} onClick={() => resolve(r.device_id, false)}>✕</button>
            </div>
          </li>
        ))}
      </ul>
    </section>
  )
}

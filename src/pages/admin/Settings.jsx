import { useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'

// Reinicio: borrar pruebas o preparar la app para una nueva reunión
export default function Settings() {
  const [scope, setScope] = useState(null) // 'points' | 'all'
  const [confirm, setConfirm] = useState('')
  const [eventName, setEventName] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)

  async function run() {
    setBusy(true)
    setMsg(null)
    const { error } = await supabase.rpc('admin_reset', {
      p_scope: scope, p_confirm: confirm, p_event_name: eventName || null,
    })
    setBusy(false)
    if (error) setMsg({ type: 'error', text: errorMessage(error) })
    else {
      setMsg({ type: 'ok', text: scope === 'all' ? 'Listo: la app quedó vacía para una nueva fiesta.' : 'Listo: puntos y votaciones en cero.' })
      setScope(null)
      setConfirm('')
      setEventName('')
    }
  }

  return (
    <section className="card form danger-zone">
      <h3>🧹 Limpiar y reiniciar</h3>

      <button className={`pick ${scope === 'points' ? 'active' : ''}`} onClick={() => setScope('points')}>
        <strong>Reiniciar puntos y votaciones</strong>
        <div className="small muted">Borra todos los puntos, votos de disfraz y resultados. Los invitados siguen registrados.</div>
      </button>
      <button className={`pick ${scope === 'all' ? 'active' : ''}`} onClick={() => setScope('all')}>
        <strong>Borrar todo (nueva fiesta)</strong>
        <div className="small muted">Además elimina a todos los invitados excepto a los admins. Úsalo para borrar las pruebas o reutilizar la app.</div>
      </button>

      {scope && (
        <>
          {scope === 'all' && (
            <label>Nombre de la fiesta (opcional)
              <input value={eventName} onChange={(e) => setEventName(e.target.value)} placeholder="Ej. Fiesta de Navidad 2026" maxLength={60} />
            </label>
          )}
          <label><span>Escribe <code>BORRAR</code> para confirmar</span>
            <input value={confirm} onChange={(e) => setConfirm(e.target.value)} autoCapitalize="characters" />
          </label>
          <button className="btn danger" disabled={busy || confirm !== 'BORRAR'} onClick={run}>
            {scope === 'all' ? '🗑 Borrar todo' : '↺ Reiniciar puntos y votaciones'}
          </button>
          <p className="hint">⚠️ No se puede deshacer.</p>
        </>
      )}
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
    </section>
  )
}

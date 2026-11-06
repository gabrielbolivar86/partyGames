import { useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { joinUrl, dashboardUrl } from '../../lib/urls'

const MODES = [
  { id: 'leaderboard', label: '🏆 Tabla general' },
  { id: 'costume_reveal', label: '🎭 Revelación de disfraces' },
]

export default function Screen({ dashboardMode }) {
  const [error, setError] = useState(null)

  async function setMode(mode) {
    const { error } = await supabase.rpc('admin_set_dashboard', { p_mode: mode })
    setError(error ? errorMessage(error) : null)
  }

  return (
    <>
      <section className="card">
        <h3>📺 ¿Qué muestra la pantalla?</h3>
        {error && <div className="error">{error}</div>}
        <div className="mode-list">
          {MODES.map((m) => (
            <button key={m.id} className={`pick ${dashboardMode === m.id ? 'active' : ''}`} onClick={() => setMode(m.id)}>
              {m.label} {dashboardMode === m.id && <span className="muted small">· en pantalla</span>}
            </button>
          ))}
        </div>
      </section>
      <section className="card">
        <h3>🔗 Enlaces</h3>
        <p className="small">Dashboard (abrir en la TV): <br /><a href={dashboardUrl()} target="_blank" rel="noreferrer">{dashboardUrl()}</a></p>
        <p className="small">Registro de invitados (el QR del dashboard lleva aquí): <br /><a href={joinUrl()}>{joinUrl()}</a></p>
      </section>
    </>
  )
}

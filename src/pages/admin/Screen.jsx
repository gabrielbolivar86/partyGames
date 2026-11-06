import { useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { joinUrl, dashboardUrl } from '../../lib/urls'

const MODES = [
  { id: 'leaderboard', label: '🏆 Tabla general' },
  { id: 'costume_reveal', label: '🎭 Revelación de disfraces' },
  { id: 'codes', label: '🔍 Caza de códigos' },
  { id: 'persona', label: '🕵️ ¿Quién es el personaje?' },
  { id: 'impostor', label: '🃏 El Impostor' },
  { id: 'final', label: '🏆 Resultados de la noche (final)' },
]

export default function Screen({ dashboardMode, frozen }) {
  const [error, setError] = useState(null)

  async function setMode(mode) {
    if (mode === 'final' && !window.confirm('¿Mostrar los resultados finales en la pantalla? Se verán todos los puntos (también los congelados).')) return
    const { error } = await supabase.rpc('admin_set_dashboard', { p_mode: mode })
    setError(error ? errorMessage(error) : null)
  }

  async function freeze(on) {
    const { error } = await supabase.rpc('admin_freeze_board', { p_freeze: on })
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
        <h3>🔒 Final de la noche</h3>
        <p className="hint">
          <b>Congelar tabla</b>: desde ese momento la pantalla y los celulares muestran los puntos de ese instante; los juegos siguen sumando a escondidas.
          Al mostrar <b>🏆 Resultados de la noche</b> se ve todo, con cuánto sumó cada uno al final.
        </p>
        {frozen
          ? <button className="btn" onClick={() => freeze(false)}>🔓 Descongelar tabla</button>
          : <button className="btn" onClick={() => freeze(true)}>🔒 Congelar tabla ahora</button>}
        <p className="small muted">{frozen ? 'Estado: congelada 🔒 (tú, como admin, ves los puntos reales).' : 'Estado: en vivo.'}</p>
      </section>
      <section className="card">
        <h3>🔗 Enlaces</h3>
        <p className="small">Dashboard (abrir en la TV): <br /><a href={dashboardUrl()} target="_blank" rel="noreferrer">{dashboardUrl()}</a></p>
        <p className="small">Registro de invitados (el QR del dashboard lleva aquí): <br /><a href={joinUrl()}>{joinUrl()}</a></p>
      </section>
    </>
  )
}

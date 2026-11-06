import { useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useLiveRpc } from '../../hooks/useLiveRpc'
import { PHASES } from '../../lib/wolfRoles'

const STATUS = { none: 'Sin partida', lobby: 'Mesa abierta', setup: 'Preparando baraja', playing: 'En juego', finished: 'Terminada' }

// El admin abre la mesa y asigna narrador. No ve roles (por si juega).
export default function WolfAdmin({ players, dashboardMode }) {
  const { data: ov, refresh } = useLiveRpc('admin_wolf_overview', ['wolf_state'])
  const [narrator, setNarrator] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function call(fn, args, confirmText) {
    if (confirmText && !window.confirm(confirmText)) return
    setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    setError(error ? errorMessage(error) : null)
    refresh()
  }

  if (!ov) return <section className="card"><p className="muted">Cargando…</p></section>
  const active = ['lobby', 'setup', 'playing'].includes(ov.status)
  const sorted = [...players].sort((a, b) => a.name.localeCompare(b.name))

  return (
    <>
      <section className="card form">
        <h3>🐺 Hombre Lobo <span className={`status ${active ? 'ok' : ''}`}>{STATUS[ov.status]}</span></h3>
        {error && <div className="error">{error}</div>}

        {!active ? (
          <>
            <p className="hint">Elige a un <b>narrador</b> (no juega: ve todos los roles y avanza las fases desde su celular). Puede ser cualquiera, incluso tú.</p>
            <select value={narrator} onChange={(e) => setNarrator(e.target.value)}>
              <option value="">— Elegir narrador —</option>
              {sorted.map((p) => <option key={p.player_id} value={p.player_id}>{p.nickname || p.name}</option>)}
            </select>
            <button className="btn primary" disabled={busy || !narrator} onClick={() => call('admin_wolf_open', { p_narrator: narrator })}>🚪 Abrir mesa</button>
            {ov.status === 'finished' && <p className="small muted">Última partida: {ov.winner === 'wolves' ? '🐺 ganaron los lobos' : '🏡 ganó la aldea'}</p>}
          </>
        ) : (
          <>
            <p>Narrador: <b>{ov.narrator}</b> · {ov.players.length} jugadores</p>
            {ov.status === 'playing' && <p className="small">Fase: {PHASES[ov.phase]?.emoji} {PHASES[ov.phase]?.label} · noche {ov.night_no} · día {ov.day_no}</p>}
            {ov.players.length > 0 && <p className="small muted">{ov.players.join(', ')}</p>}
            <div className="row nowrap">
              <select value={narrator} onChange={(e) => setNarrator(e.target.value)}>
                <option value="">Cambiar narrador…</option>
                {sorted.map((p) => <option key={p.player_id} value={p.player_id}>{p.nickname || p.name}</option>)}
              </select>
              <button className="btn small" disabled={!narrator || busy} onClick={() => call('admin_wolf_set_narrator', { p_narrator: narrator })}>OK</button>
            </div>
            <p className="hint">🤫 Si juegas, aquí no verás roles: solo el narrador los ve.</p>
            <button className="btn small ghost-btn" onClick={() => call('admin_wolf_cancel', {}, '¿Cancelar la partida? No se dan puntos.')}>✕ Cancelar partida</button>
          </>
        )}

        <div className="row" style={{ marginTop: 10 }}>
          {dashboardMode !== 'wolf'
            ? <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'wolf' })}>📺 Mostrar en pantalla</button>
            : <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'leaderboard' })}>📺 Volver a tabla general</button>}
        </div>
      </section>
      <WolfSettings settings={ov.settings} onSaved={refresh} />
    </>
  )
}

function WolfSettings({ settings, onSaved }) {
  const [s, setS] = useState(settings)
  const [msg, setMsg] = useState(null)
  useEffect(() => { setS(settings) }, [JSON.stringify(settings)]) // eslint-disable-line
  async function save() {
    const { error } = await supabase.rpc('admin_wolf_settings', { p_win: Number(s.win), p_survive: Number(s.survive) })
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Guardado' })
    onSaved()
  }
  return (
    <section className="card form">
      <h3>⚙️ Puntos</h3>
      <div className="pts-grid two">
        <label className="pts-field">🏆 Bando ganador<input type="number" min="0" max="500" value={s.win} onChange={(e) => setS({ ...s, win: e.target.value })} /></label>
        <label className="pts-field">💚 Extra si sobrevive<input type="number" min="0" max="500" value={s.survive} onChange={(e) => setS({ ...s, survive: e.target.value })} /></label>
      </div>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <button className="btn" onClick={save}>Guardar puntos</button>
    </section>
  )
}

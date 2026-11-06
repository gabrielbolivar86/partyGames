import { useCallback, useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useRealtimeRefresh } from '../../hooks/useRealtimeRefresh'

const STATUS = {
  not_started: { label: 'Sin empezar', cls: '' },
  open: { label: 'Votación abierta', cls: 'ok' },
  closed: { label: 'Cerrada', cls: 'warn' },
}
const STEP_LABEL = ['Nada revelado', '3.º revelado', '2.º revelado', '🏆 1.º revelado']

export default function CostumeAdmin({ dashboardMode }) {
  const [ov, setOv] = useState(null)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [showResults, setShowResults] = useState(false)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('admin_costume_overview')
    if (error) setError(error.message)
    else { setError(null); setOv(data) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  // Los votos no emiten tiempo real (privados): refrescamos cada 8 s para ver el conteo
  useRealtimeRefresh(['costume_contest', 'players'], refresh, { fallbackMs: 8000 })

  async function call(fn, args, confirmText) {
    if (confirmText && !window.confirm(confirmText)) return
    setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    if (error) setError(errorMessage(error))
    refresh()
  }

  if (!ov) return <section className="card"><p className="muted">Cargando…</p>{error && <div className="error">{error}</div>}</section>

  const st = STATUS[ov.status]
  const onScreen = dashboardMode === 'costume_reveal'

  return (
    <>
      <section className="card">
        <h3>🎭 Mejor disfraz <span className={`status ${st.cls}`}>{st.label}</span></h3>
        {error && <div className="error">{error}</div>}
        <div className="stats">
          <div><b>{ov.candidates}</b><span>disfrazados</span></div>
          <div><b>{ov.ballots}</b><span>han votado</span></div>
          <div><b>{ov.voters}</b><span>invitados</span></div>
        </div>

        {ov.status === 'not_started' && (
          <button className="btn primary" disabled={busy} onClick={() => call('admin_costume_open', {})}>
            Abrir votación
          </button>
        )}
        {ov.status === 'open' && (
          <>
            <p className="hint">Los invitados ordenan su ranking y se guarda solo. Cuando cierres, se calcula el resultado y los puntos quedan ocultos hasta revelar al 1.º.</p>
            <button className="btn danger wide" disabled={busy}
              onClick={() => call('admin_costume_close', {}, '¿Cerrar la votación y calcular resultados? Ya no se podrá votar.')}>
              Cerrar votación y calcular
            </button>
          </>
        )}
        {ov.status === 'closed' && (
          <button className="btn small ghost-btn" disabled={busy}
            onClick={() => call('admin_costume_open', {}, '¿Reabrir la votación? Se borran los resultados y los puntos del disfraz (los votos se conservan).')}>
            ↺ Reabrir votación
          </button>
        )}
      </section>

      {ov.status === 'closed' && (
        <section className="card">
          <h3>🎬 Revelación en pantalla</h3>
          <p className="small muted">Estado: <b>{STEP_LABEL[ov.reveal_step]}</b> · Pantalla: <b>{onScreen ? 'mostrando revelación' : 'tabla general'}</b></p>
          {!onScreen && (
            <button className="btn primary" disabled={busy} onClick={() => call('admin_set_dashboard', { p_mode: 'costume_reveal' })}>
              📺 Mostrar revelación en la pantalla
            </button>
          )}
          {onScreen && (
            <div className="reveal-controls">
              {ov.reveal_step < 3 && (
                <button className="btn primary" disabled={busy}
                  onClick={() => call('admin_costume_reveal', { p_step: ov.reveal_step + 1 })}>
                  {['Revelar 3.er lugar 🥉', 'Revelar 2.º lugar 🥈', 'Revelar 1.er lugar 🥇'][ov.reveal_step]}
                </button>
              )}
              {ov.reveal_step === 3 && <p className="success">¡Revelado! Los puntos del concurso ya se sumaron a la tabla general.</p>}
              <div className="row">
                <button className="btn small ghost-btn" disabled={busy || ov.reveal_step === 0}
                  onClick={() => call('admin_costume_reveal', { p_step: ov.reveal_step - 1 })}>↩︎ Paso atrás</button>
                <button className="btn small" disabled={busy} onClick={() => call('admin_set_dashboard', { p_mode: 'leaderboard' })}>
                  📺 Volver a tabla general
                </button>
              </div>
            </div>
          )}

          <button className="btn small ghost-btn" onClick={() => setShowResults((s) => !s)}>
            {showResults ? '🙈 Ocultar resultados' : '👀 Ver resultados (spoiler)'}
          </button>
          {showResults && <Results results={ov.results} />}
        </section>
      )}

      <PointsSettings ov={ov} onSaved={refresh} />
    </>
  )
}

function Results({ results }) {
  if (!results.length) return <p className="muted">Nadie estaba disfrazado.</p>
  return (
    <table className="results">
      <thead><tr><th>#</th><th>Invitado</th><th title="Puntaje Borda (0 a 1)">Pts</th><th title="Veces en 1.er lugar">1.º</th><th title="Boletas">Votos</th></tr></thead>
      <tbody>
        {results.map((r) => (
          <tr key={r.place}>
            <td>{r.place}{r.tied && ' ⚠️'}</td>
            <td><b>{r.name}</b><div className="small muted">{r.costume}</div></td>
            <td>{Number(r.score).toFixed(2)}</td>
            <td>{r.firsts}</td>
            <td>{r.ballots}</td>
          </tr>
        ))}
      </tbody>
      {results.some((r) => r.tied) && (
        <caption className="small muted">⚠️ Empate exacto (puntaje, 1.os y 2.os). Se ordenó alfabéticamente: puedes ajustar con puntos manuales.</caption>
      )}
    </table>
  )
}

function PointsSettings({ ov, onSaved }) {
  const [p, setP] = useState(ov.points)
  const [msg, setMsg] = useState(null)
  const locked = ov.status === 'closed'

  useEffect(() => { setP(ov.points) }, [ov.points.p1, ov.points.p2, ov.points.p3, ov.points.pp]) // eslint-disable-line

  async function save() {
    const { error } = await supabase.rpc('admin_costume_settings', {
      p1: Number(p.p1), p2: Number(p.p2), p3: Number(p.p3), pp: Number(p.pp),
    })
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Guardado' })
    onSaved()
  }

  const field = (k, label) => (
    <label className="pts-field">{label}
      <input type="number" min="0" max="1000" value={p[k]} disabled={locked}
        onChange={(e) => setP({ ...p, [k]: e.target.value })} />
    </label>
  )

  return (
    <section className="card form">
      <h3>⚙️ Puntos del concurso</h3>
      <div className="pts-grid">
        {field('p1', '🥇 1.º')}
        {field('p2', '🥈 2.º')}
        {field('p3', '🥉 3.º')}
        {field('pp', '🎃 Resto')}
      </div>
      <p className="hint">"Resto" = puntos por participar para los demás disfrazados. {locked && 'Para cambiarlos, reabre la votación.'}</p>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      {!locked && <button className="btn" onClick={save}>Guardar puntos</button>}
    </section>
  )
}

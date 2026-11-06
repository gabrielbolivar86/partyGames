import { useEffect, useMemo, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useLiveRpc } from '../../hooks/useLiveRpc'
import { GiftTimer } from '../../components/GiftGame'

const STATUS = {
  none: 'Sin empezar', writing: 'Escribiendo', reading: 'Leyendo frases', voting: 'Votando', results: 'Resultados',
}

export default function GiftAdmin({ players, dashboardMode }) {
  const { data: ov, error: loadError, refresh } = useLiveRpc('admin_gift_overview', ['gift_game'])
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [spoil, setSpoil] = useState(false)

  async function call(fn, args, confirmText) {
    if (confirmText && !window.confirm(confirmText)) return
    setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    setError(error ? errorMessage(error) : null)
    refresh()
  }

  if (!ov) return <section className="card"><p className="muted">Cargando…</p>{loadError && <div className="error">{loadError}</div>}</section>
  const s = ov.status

  return (
    <>
      <section className="card">
        <h3>🎁 El Regalo Loco <span className={`status ${s === 'none' ? '' : 'ok'}`}>{STATUS[s]}</span></h3>
        {error && <div className="error">{error}</div>}

        {s === 'writing' && (
          <>
            <GiftTimer data={ov} onExpire={refresh} />
            {ov.ends_at && (
              <div className="row">
                <button className="btn small" disabled={busy} onClick={() => call('admin_gift_add_time', { p_seconds: 15 })}>＋15 s</button>
                <button className="btn small" disabled={busy} onClick={() => call('admin_gift_add_time', { p_seconds: 30 })}>＋30 s</button>
              </div>
            )}
            <div className="stats two">
              <div><b>{ov.progress.done}/{ov.progress.total}</b><span>partes escritas</span></div>
              <div><b>{ov.missing.length}</b><span>personas faltan</span></div>
            </div>
            {ov.missing.length > 0 && <Reassign ov={ov} players={players} busy={busy} call={call} />}
            <button className="btn primary" disabled={busy}
              onClick={() => call('admin_gift_close_writing', {}, ov.missing.length ? `Faltan ${ov.missing.length} personas. Lo que falte se rellena con algo al azar. ¿Cerrar?` : null)}>
              ✅ Cerrar escritura y armar frases
            </button>
            {ov.ends_at && <p className="hint">Al acabarse el tiempo se cierra sola y lo que falte se rellena al azar.</p>}
          </>
        )}

        {s === 'reading' && ov.current && (
          <>
            <blockquote className="persona-fact small-fact">{ov.current.phrase}</blockquote>
            <div className="row nowrap gift-nav">
              <button className="btn" disabled={busy || ov.read_index <= 1} onClick={() => call('admin_gift_read', { p_index: ov.read_index - 1 })}>◀︎</button>
              <b>{ov.read_index} / {ov.count}</b>
              <button className="btn" disabled={busy || ov.read_index >= ov.count} onClick={() => call('admin_gift_read', { p_index: ov.read_index + 1 })}>▶︎</button>
            </div>
            <button className="btn primary" disabled={busy} onClick={() => call('admin_gift_open_vote', {})}>🗳 Abrir votación</button>
            <p className="hint">Lee cada regalo en voz alta (en la TV aparece grande). Cuando terminen, abre la votación.</p>
          </>
        )}

        {s === 'voting' && (
          <>
            <div className="stats two">
              <div><b>{ov.voters_done}</b><span>ya votaron</span></div>
              <div><b>{ov.count}</b><span>frases</span></div>
            </div>
            <button className="btn danger wide" disabled={busy} onClick={() => call('admin_gift_close_vote', {}, '¿Cerrar la votación y calcular ganadores?')}>Cerrar votación y calcular</button>
          </>
        )}

        {s === 'results' && (
          <>
            <p className="small">Revelación: <b>{['nada', '3.º', '2.º', '🏆 1.º'][ov.reveal_step]}</b></p>
            {ov.reveal_step < 3
              ? <button className="btn primary" disabled={busy} onClick={() => call('admin_gift_reveal', { p_step: ov.reveal_step + 1 })}>
                  {['Revelar 3.er lugar 🥉', 'Revelar 2.º lugar 🥈', 'Revelar 1.er lugar 🥇'][ov.reveal_step]}
                </button>
              : <p className="success">¡Revelado! Los puntos se sumaron a los 3 autores de cada frase ganadora.</p>}
            <div className="row" style={{ marginTop: 8 }}>
              <button className="btn small ghost-btn" disabled={busy || ov.reveal_step === 0} onClick={() => call('admin_gift_reveal', { p_step: ov.reveal_step - 1 })}>↩︎ Paso atrás</button>
              <button className="btn small ghost-btn" onClick={() => setSpoil((x) => !x)}>{spoil ? '🙈 Ocultar' : '👀 Ver resultados'}</button>
            </div>
            {spoil && (
              <ol className="gift-admin-results">
                {ov.results.map((r) => (
                  <li key={r.place}><b>{r.place}.º</b> ({r.votes} votos{r.tied ? ' ⚠️ empate' : ''}) {r.phrase} <span className="small muted">· {r.authors.join(', ')}</span></li>
                ))}
              </ol>
            )}
          </>
        )}

        {(s === 'none' || s === 'results') && <Setup players={players} busy={busy} call={call} again={s === 'results'} />}

        <div className="row" style={{ marginTop: 10 }}>
          {dashboardMode !== 'gift'
            ? <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'gift' })}>📺 Mostrar en pantalla</button>
            : <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'leaderboard' })}>📺 Volver a tabla general</button>}
          {s !== 'none' && <button className="btn small ghost-btn" onClick={() => call('admin_gift_cancel', {}, s === 'results' ? '¿Limpiar el Regalo Loco? (si no revelaste el 1.º, sus puntos se quitan)' : '¿Cancelar esta ronda?')}>✕ {s === 'results' ? 'Limpiar' : 'Cancelar'}</button>}
        </div>
      </section>

      <GiftSettings settings={ov.settings} onSaved={refresh} />
    </>
  )
}

function Setup({ players, busy, call, again }) {
  const [selected, setSelected] = useState(() => new Set(players.map((p) => p.player_id)))
  const known = useMemo(() => new Set(), [])
  const ids = players.map((p) => p.player_id).join(',')
  useEffect(() => {
    setSelected((s) => { const c = new Set(s); players.forEach((p) => { if (!known.has(p.player_id)) c.add(p.player_id) }); return c })
    players.forEach((p) => known.add(p.player_id))
  }, [ids]) // eslint-disable-line
  const toggle = (id) => setSelected((s) => { const c = new Set(s); c.has(id) ? c.delete(id) : c.add(id); return c })
  const sorted = [...players].sort((a, b) => a.name.localeCompare(b.name))
  const n = players.filter((p) => selected.has(p.player_id) && !p.away).length

  return (
    <div className="form" style={{ marginTop: 10 }}>
      <div className="row">
        <b>{again ? 'Otra ronda' : 'Jugadores'}: {n}</b>
        <button className="link-btn" onClick={() => setSelected(new Set(players.map((p) => p.player_id)))}>Todos</button>
        <button className="link-btn" onClick={() => setSelected(new Set())}>Ninguno</button>
      </div>
      <div className="check-grid">
        {sorted.map((p) => (
          <label key={p.player_id} className={`check-chip ${selected.has(p.player_id) && !p.away ? 'on' : ''} ${p.away ? 'away' : ''}`} title={p.away ? 'En pausa: entra en la siguiente ronda' : ''}>
            <input type="checkbox" checked={selected.has(p.player_id)} onChange={() => toggle(p.player_id)} />
            {p.away ? '⏸️ ' : ''}{p.nickname || p.name}
          </label>
        ))}
      </div>
      <p className="hint">Cada jugador escribe 3 cosas a ciegas y se arma una frase por jugador. Con muchos jugadores la lectura es larga: con 10–15 queda bien.</p>
      <button className="btn primary" disabled={busy || n < 4}
        onClick={() => call('admin_gift_start', { p_players: [...selected] }, again ? '¿Empezar una nueva ronda?' : null)}>
        ▶︎ Empezar a escribir
      </button>
      {n < 4 && <p className="hint">Se necesitan al menos 4 jugadores presentes.</p>}
      {players.some((p) => p.away) && <p className="small muted">⏸️ Los que están en pausa entran en la siguiente ronda.</p>}
    </div>
  )
}

// Quién falta: se le pueden pasar sus partes a otra persona (ej. tuvo que ir a ver a su hijo)
function Reassign({ ov, players, busy, call }) {
  const [from, setFrom] = useState(null)
  const [to, setTo] = useState('')
  const options = [...players].filter((p) => !p.away && p.player_id !== from).sort((a, b) => a.name.localeCompare(b.name))
  return (
    <div className="reassign">
      <div className="small"><b>Faltan:</b></div>
      <ul className="players-list compact-list">
        {ov.missing.map((m) => (
          <li key={m.id}>
            <span className="grow">{m.name}{m.away && <span className="away-tag"> ⏸️ en pausa</span>} <span className="small muted">· {m.parts} {m.parts === 1 ? 'parte' : 'partes'}</span></span>
            <button className="btn small ghost-btn" onClick={() => { setFrom(from === m.id ? null : m.id); setTo('') }}>{from === m.id ? 'Cancelar' : '↪︎ Pasar a…'}</button>
          </li>
        ))}
      </ul>
      {from && (
        <div className="row nowrap">
          <select value={to} onChange={(e) => setTo(e.target.value)}>
            <option value="">¿Quién las escribe?</option>
            {options.map((p) => <option key={p.player_id} value={p.player_id}>{p.nickname || p.name}</option>)}
          </select>
          <button className="btn small primary" disabled={busy || !to}
            onClick={async () => { await call('admin_gift_reassign', { p_from: from, p_to: to }); setFrom(null); setTo('') }}>OK</button>
        </div>
      )}
    </div>
  )
}

function GiftSettings({ settings, onSaved }) {
  const [s, setS] = useState(settings)
  const [msg, setMsg] = useState(null)
  useEffect(() => { setS(settings) }, [JSON.stringify(settings)]) // eslint-disable-line

  async function save() {
    const r1 = await supabase.rpc('admin_gift_settings', { p1: Number(s.p1), p2: Number(s.p2), p3: Number(s.p3) })
    const r2 = await supabase.rpc('admin_gift_timer', { p_seconds: Number(s.seconds) })
    const error = r1.error || r2.error
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Guardado' })
    onSaved()
  }
  const field = (k, label) => (
    <label className="pts-field">{label}
      <input type="number" min="0" max="500" value={s[k]} onChange={(e) => setS({ ...s, [k]: e.target.value })} />
    </label>
  )
  return (
    <section className="card form">
      <h3>⚙️ Tiempo y puntos</h3>
      <label className="pts-field">⏱ Segundos para escribir (0 = sin tiempo)
        <input type="number" min="0" max="600" value={s.seconds} onChange={(e) => setS({ ...s, seconds: e.target.value })} />
      </label>
      <div className="pts-grid three">{field('p1', '🥇 1.º')}{field('p2', '🥈 2.º')}{field('p3', '🥉 3.º')}</div>
      <p className="hint">Se dan a <b>los 3 autores</b> de cada frase ganadora (quien eligió el objeto, el uso y la reacción). Se suman al revelar el 1.º.</p>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <button className="btn" onClick={save}>Guardar</button>
    </section>
  )
}

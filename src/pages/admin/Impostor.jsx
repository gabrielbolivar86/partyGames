import { useEffect, useMemo, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useLiveRpc } from '../../hooks/useLiveRpc'
import { suggestImpostors, maxImpostors, KIND_LABEL } from '../../lib/impostor'
import { LastResult } from '../../components/ImpostorGame'

export default function ImpostorAdmin({ players, dashboardMode }) {
  const { data: ov, error: loadError, refresh } = useLiveRpc('admin_impostor_overview', ['impostor_game', 'impostor_votes'])
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function call(fn, args, confirmText) {
    if (confirmText && !window.confirm(confirmText)) return false
    setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    setError(error ? errorMessage(error) : null)
    refresh()
    return !error
  }

  if (!ov) return <section className="card"><p className="muted">Cargando…</p>{loadError && <div className="error">{loadError}</div>}</section>
  const playing = ov.status === 'playing'

  return (
    <>
      {error && <section className="card"><div className="error">{error}</div></section>}
      {playing
        ? <RoundControls ov={ov} busy={busy} call={call} />
        : <>
            {ov.round && ov.status === 'finished' && (
              <section className="card">
                <h3>Ronda #{ov.round.number} terminada</h3>
                <p>{ov.round.winner === 'crew' ? '🛡 Ganó la tripulación' : '🕵️ Ganaron los impostores'} · {ov.round.win_reason}</p>
                <p className="small muted">Palabra: <b>{ov.round.word}</b> · Impostores: {(ov.round.impostors || []).join(', ')}</p>
              </section>
            )}
            <Setup ov={ov} players={players} busy={busy} call={call} />
          </>}

      <section className="card">
        <div className="row">
          {dashboardMode !== 'impostor'
            ? <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'impostor' })}>📺 Mostrar en pantalla</button>
            : <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'leaderboard' })}>📺 Volver a tabla general</button>}
          {ov.round && <button className="btn small ghost-btn" onClick={() => call('admin_impostor_cancel', {}, '¿Cancelar/limpiar la ronda? No se dan puntos.')}>✕ Cancelar ronda</button>}
        </div>
      </section>

      <ImpostorSettings settings={ov.settings} onSaved={refresh} />
    </>
  )
}

/* ---------- Preparar ronda ---------- */
function Setup({ ov, players, busy, call }) {
  const [selected, setSelected] = useState(() => new Set(players.map((p) => p.player_id)))
  const n = selected.size
  const sug = suggestImpostors(n)
  const [k, setK] = useState(sug.k)
  const [touchedK, setTouchedK] = useState(false)
  const [source, setSource] = useState('random')
  const [category, setCategory] = useState('')
  const [word, setWord] = useState('')
  const [hint, setHint] = useState('')
  const max = maxImpostors(n)

  // Si cambia el número de jugadores y no tocaste el número de impostores, seguir la sugerencia
  useEffect(() => { if (!touchedK) setK(sug.k) }, [n]) // eslint-disable-line
  // Invitados nuevos aprobados → marcados por defecto
  const knownIds = useMemo(() => new Set(), [])
  const ids = players.map((p) => p.player_id).join(',')
  useEffect(() => {
    setSelected((s) => { const c = new Set(s); players.forEach((p) => { if (!knownIds.has(p.player_id)) c.add(p.player_id) }); return c })
    players.forEach((p) => knownIds.add(p.player_id))
  }, [ids]) // eslint-disable-line

  const toggle = (id) => setSelected((s) => { const c = new Set(s); c.has(id) ? c.delete(id) : c.add(id); return c })
  const sorted = [...players].sort((a, b) => a.name.localeCompare(b.name))

  async function start() {
    await call('admin_impostor_start', {
      p_players: [...selected], p_impostors: Number(k),
      p_word: source === 'custom' ? word : null, p_hint: source === 'custom' ? hint : null,
      p_category: source === 'random' && category ? category : null,
    })
  }

  return (
    <section className="card form">
      <h3>🕵️ Nueva ronda de El Impostor</h3>

      <div className="row">
        <b>Jugadores: {n}</b>
        <button className="link-btn" onClick={() => setSelected(new Set(players.map((p) => p.player_id)))}>Todos</button>
        <button className="link-btn" onClick={() => setSelected(new Set())}>Ninguno</button>
      </div>
      <div className="check-grid">
        {sorted.map((p) => (
          <label key={p.player_id} className={`check-chip ${selected.has(p.player_id) ? 'on' : ''}`}>
            <input type="checkbox" checked={selected.has(p.player_id)} onChange={() => toggle(p.player_id)} />
            {p.nickname || p.name}
          </label>
        ))}
      </div>

      <div className="imp-k">
        <span><b>Impostores</b></span>
        <div className="row nowrap">
          <button className="btn small" onClick={() => { setTouchedK(true); setK(Math.max(1, k - 1)) }} disabled={k <= 1}>−</button>
          <span className="imp-k-n">{k}</span>
          <button className="btn small" onClick={() => { setTouchedK(true); setK(Math.min(max, k + 1)) }} disabled={k >= max}>＋</button>
        </div>
      </div>
      <p className="hint">💡 Sugerido: <b>{sug.k}</b>. {sug.reason} {k !== sug.k && <button className="link-btn" onClick={() => { setK(sug.k); setTouchedK(false) }}>Usar sugerido</button>}</p>

      <div className="seg wide">
        <button type="button" className={source === 'random' ? 'active' : ''} onClick={() => setSource('random')}>🎲 Palabra al azar</button>
        <button type="button" className={source === 'custom' ? 'active' : ''} onClick={() => setSource('custom')}>✍️ Escribir la mía</button>
      </div>
      {source === 'random' ? (
        <label>Categoría
          <select value={category} onChange={(e) => setCategory(e.target.value)}>
            <option value="">Cualquiera ({ov.words_count} palabras)</option>
            {(ov.categories || []).map((c) => <option key={c.name} value={c.name}>{c.name} ({c.count})</option>)}
          </select>
        </label>
      ) : (
        <>
          <input value={word} onChange={(e) => setWord(e.target.value)} placeholder="Palabra (ej. Teleférico)" maxLength={40} />
          <input value={hint} onChange={(e) => setHint(e.target.value)} placeholder="Pista para el impostor (general, ej. Colores)" maxLength={40} />
          <p className="hint">Tip: la pista debe ser general o de doble sentido, que no delate la categoría.</p>
        </>
      )}

      <button className="btn primary" disabled={busy || n < 3 || (source === 'custom' && (!word.trim() || !hint.trim()))} onClick={start}>
        ▶︎ Repartir y empezar
      </button>
      {n < 3 && <p className="hint">Se necesitan al menos 3 jugadores.</p>}
    </section>
  )
}

/* ---------- Durante la ronda ---------- */
function RoundControls({ ov, busy, call }) {
  const r = ov.round
  const v = r.vote
  const [spoiler, setSpoiler] = useState(false)
  const open = v.status === 'open'

  return (
    <>
      <section className="card">
        <h3>Ronda #{r.number} <span className="status ok">En juego</span></h3>
        <button className="link-btn" onClick={() => setSpoiler((s) => !s)}>
          {spoiler ? <>🙈 Palabra: <b>{r.word}</b> · Pista: <b>{r.hint}</b> · Impostores: <b>{(r.impostors || []).join(', ')}</b></> : '👀 Ver palabra e impostores (spoiler)'}
        </button>
        <div className="stats two" style={{ marginTop: 10 }}>
          <div><b>{r.players.filter((p) => p.alive).length}</b><span>siguen en juego</span></div>
          <div><b>{r.players.filter((p) => !p.alive).length}</b><span>eliminados</span></div>
        </div>
        {r.last_result && !open && <LastResult r={r.last_result} />}
      </section>

      <section className="card">
        <h3>🗳 Votación {v.no > 0 && <span className="muted small">#{v.no}</span>}</h3>
        {!open ? (
          <div className="imp-open">
            <button className="btn" disabled={busy} onClick={() => call('admin_impostor_open_vote', { p_kind: 'defense' })}>🗣 Abrir votación de defensa</button>
            <button className="btn danger" disabled={busy} onClick={() => call('admin_impostor_open_vote', { p_kind: 'elimination' })}>☠️ Abrir votación de eliminación</button>
            <p className="hint">Defensa: se ve quién va ganando y el más votado se defiende, pero nadie sale. Eliminación: al cerrar, sale el más votado (empate = nadie).</p>
          </div>
        ) : (
          <>
            <div className="seg wide">
              <button type="button" className={v.kind === 'defense' ? 'active' : ''} onClick={() => call('admin_impostor_set_vote_kind', { p_kind: 'defense' })}>🗣 Defensa</button>
              <button type="button" className={v.kind === 'elimination' ? 'active danger' : ''} onClick={() => call('admin_impostor_set_vote_kind', { p_kind: 'elimination' })}>☠️ Eliminación</button>
            </div>
            <p className="small">{v.voted} de {v.eligible} votaron</p>
            <ul className="ledger">
              {v.tally.map((t) => (
                <li key={t.id}><span className="delta pos">{t.votes}</span><span className="grow"><b>{t.name}</b> <span className="small muted">← {t.voters.join(', ')}</span></span></li>
              ))}
            </ul>
            <button className={`btn ${v.kind === 'elimination' ? 'danger' : 'primary'}`} disabled={busy}
              onClick={() => call('admin_impostor_close_vote', {}, v.kind === 'elimination' ? '¿Cerrar y ELIMINAR al más votado?' : null)}>
              {v.kind === 'elimination' ? '☠️ Cerrar y eliminar al más votado' : '🗣 Cerrar votación de defensa'}
            </button>
            <p className="hint">Tipo actual: {KIND_LABEL[v.kind].long}. Puedes cambiarlo antes de cerrar.</p>
          </>
        )}
      </section>

      {r.guesses?.length > 0 && (
        <section className="card">
          <h3>🎯 Intentos de adivinar</h3>
          <ul className="ledger">{r.guesses.map((g) => <li key={g.name}><b>{g.name}</b>: “{g.guess}” ❌</li>)}</ul>
        </section>
      )}

      <section className="card">
        <h3>🏁 Terminar a mano</h3>
        <p className="hint">Si se acaba el tiempo o quieres cerrar la ronda: elige quién ganó (reparte los puntos).</p>
        <div className="row">
          <button className="btn small" disabled={busy} onClick={() => call('admin_impostor_finish', { p_winner: 'crew' }, '¿Dar la victoria a la tripulación?')}>🛡 Ganó la tripulación</button>
          <button className="btn small" disabled={busy} onClick={() => call('admin_impostor_finish', { p_winner: 'impostors' }, '¿Dar la victoria a los impostores?')}>🕵️ Ganaron los impostores</button>
        </div>
      </section>
    </>
  )
}

function ImpostorSettings({ settings, onSaved }) {
  const [s, setS] = useState(settings)
  const [msg, setMsg] = useState(null)
  useEffect(() => { setS(settings) }, [JSON.stringify(settings)]) // eslint-disable-line

  async function save() {
    const { error } = await supabase.rpc('admin_impostor_settings', { p_crew: Number(s.crew), p_impostor: Number(s.impostor) })
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Guardado' })
    onSaved()
  }

  return (
    <section className="card form">
      <h3>⚙️ Puntos</h3>
      <div className="pts-grid two">
        <label className="pts-field">🛡 Tripulación gana
          <input type="number" min="0" max="500" value={s.crew} onChange={(e) => setS({ ...s, crew: e.target.value })} />
        </label>
        <label className="pts-field">🕵️ Impostor gana
          <input type="number" min="0" max="500" value={s.impostor} onChange={(e) => setS({ ...s, impostor: e.target.value })} />
        </label>
      </div>
      <p className="hint">Tripulación: a cada tripulante (incluso eliminados) cuando no queda ningún impostor. Impostores: a cada impostor si igualan en número a la tripulación, si adivinan la palabra o si les das la victoria.</p>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <button className="btn" onClick={save}>Guardar puntos</button>
    </section>
  )
}

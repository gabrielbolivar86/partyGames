import { useEffect, useMemo, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLiveRpc } from '../hooks/useLiveRpc'
import { useCountdown } from '../hooks/usePersona'
import { ROLES, SPECIAL_ORDER, roleOf, suggestDeck, analyzeDeck, PHASES, narratorScript } from '../lib/wolfRoles'
import { WolfResult } from './WolfPlay'

/** Panel del narrador: ve todos los roles, controla las fases y lee el guion. */
export default function WolfNarrator() {
  const { data: v, error: loadErr, refresh } = useLiveRpc('wolf_narrator_view', ['wolf_state'], { debounceMs: 120 })
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

  if (!v) return <section className="card"><p className="muted">Cargando panel del narrador…</p>{loadErr && <div className="error">{loadErr}</div>}</section>

  return (
    <section className="card wolf narrator">
      <div className="costume-head">
        <h3>🐺 Panel del narrador</h3>
        <span className="save-badge">{v.seats.length} jugadores</span>
      </div>
      <p className="small muted">🤫 Solo tú ves esto. No juegas: narras y controlas el ritmo.</p>
      {error && <div className="error">{error}</div>}

      {v.status === 'lobby' && <NarratorLobby v={v} busy={busy} call={call} />}
      {v.status === 'setup' && <DeckEditor v={v} busy={busy} call={call} />}
      {v.status === 'playing' && <NarratorGame v={v} busy={busy} call={call} />}
      {v.status === 'finished' && (
        <>
          <div className="imp-final crew"><div className="imp-winner">{v.winner === 'wolves' ? '🐺 Ganaron los lobos' : '🏡 Ganó la aldea'}</div></div>
          <SeatList v={v} />
          <p className="hint">Para otra partida, el admin abre una mesa nueva (🐺 Lobo).</p>
        </>
      )}
    </section>
  )
}

function NarratorLobby({ v, busy, call }) {
  return (
    <>
      <p className="hint">Ya están todos los presentes. Saca con ✕ o suma abajo.</p>
      <ul className="players-list compact-list lobby-list">
        {v.seats.map((s) => (
          <li key={s.id}><span className="grow">{s.name}</span>
            <button className="btn small ghost-btn" title="Sacar de esta partida" onClick={() => call('wolf_kick', { p_player: s.id })}>✕</button></li>
        ))}
        {v.seats.length === 0 && <p className="muted">No hay nadie presente…</p>}
      </ul>
      <Bench v={v} call={call} />
      <button className="btn primary" disabled={busy || v.seats.length < 4} onClick={() => call('wolf_close_table', {},
        v.seats.length < 6 ? `Solo hay ${v.seats.length} jugadores (lo ideal es 6+). ¿Cerrar igual?` : null)}>
        🔒 Cerrar mesa ({v.seats.length})
      </button>
    </>
  )
}

// Quiénes no están en la mesa (ausentes o sacados): se pueden volver a sumar antes de repartir
export function Bench({ v, call }) {
  if (!v.benched?.length) return null
  return (
    <div className="bench">
      <div className="small"><b>Fuera de la mesa ({v.benched.length})</b></div>
      <ul className="players-list">
        {v.benched.map((b) => (
          <li key={b.id}>
            <span className="grow">{b.name} <span className="small muted">{b.away ? '⏸️ en pausa' : '✕ sacado'}</span></span>
            <button className="btn small" onClick={() => call('wolf_unkick', { p_player: b.id })}>＋ Sumar</button>
          </li>
        ))}
      </ul>
    </div>
  )
}

function DeckEditor({ v, busy, call }) {
  const n = v.seats.length
  const sug = useMemo(() => suggestDeck(n), [n])
  const [deck, setDeck] = useState(sug.deck)
  const a = analyzeDeck(deck, n)
  const cfg = v.config || {}
  const [debate, setDebate] = useState(Math.round((cfg.debate || 240) / 60))
  const [mayor, setMayor] = useState(cfg.mayor ?? n >= 12)
  const [pub, setPub] = useState(cfg.public_deck ?? true)
  useEffect(() => { setDeck(sug.deck) }, [n]) // eslint-disable-line

  const inc = (k, d) => setDeck((x) => ({ ...x, [k]: Math.max(0, (x[k] || 0) + d) }))

  async function deal() {
    await call('wolf_set_config', { p_config: { debate: Number(debate) * 60, mayor, public_deck: pub } })
    await call('wolf_deal', { p_deck: deck }, `¿Repartir ${n} cartas? (${Object.entries(a.full).filter(([, c]) => c).map(([k, c]) => `${c} ${roleOf(k).name}`).join(', ')})`)
  }

  return (
    <>
      <h4>🃏 Baraja para {n} jugadores</h4>
      <div className="wolf-reasons">
        <b>💡 Sugerencia</b>
        <ul>{sug.reasons.map((r) => <li key={r}>{r}</li>)}</ul>
      </div>

      <div className="deck-editor">
        {SPECIAL_ORDER.map((k) => (
          <div key={k} className="deck-row">
            <span>{ROLES[k].emoji} {ROLES[k].name}</span>
            <div className="row nowrap">
              <button className="btn small" onClick={() => inc(k, -1)} disabled={!deck[k]}>−</button>
              <b className="deck-n">{deck[k] || 0}</b>
              <button className="btn small" onClick={() => inc(k, 1)}>＋</button>
            </div>
          </div>
        ))}
        <div className="deck-row muted"><span>{ROLES.aldeano.emoji} Aldeanos (automático)</span><b className="deck-n">{a.aldeanos}</b></div>
      </div>

      <div className={`balance ${a.level}`}>⚖️ {a.text} <span className="small">({a.score > 0 ? '+' : ''}{a.score})</span></div>
      {a.warnings.map((w) => <div key={w} className="small fact-warn">⚠️ {w}</div>)}
      <button className="link-btn" onClick={() => setDeck(sug.deck)}>↺ Restablecer sugerida</button>

      <div className="wolf-opts">
        <label className="check"><input type="checkbox" checked={mayor} onChange={(e) => setMayor(e.target.checked)} /> 🎖️ Elegir alcalde el día 1 (voto doble)</label>
        <label className="check"><input type="checkbox" checked={pub} onChange={(e) => setPub(e.target.checked)} /> 👁 Baraja pública (todos ven qué roles hay)</label>
        <label className="pts-field">🗣 Minutos de debate
          <input type="number" min="1" max="15" value={debate} onChange={(e) => setDebate(e.target.value)} />
        </label>
      </div>

      <Bench v={v} call={call} />
      <button className="btn primary" disabled={busy || !a.ok} onClick={deal}>🃏 Repartir cartas</button>
      <button className="btn small ghost-btn" onClick={() => call('wolf_reopen_table', {})}>↩︎ Reabrir mesa</button>
    </>
  )
}

function NarratorGame({ v, busy, call }) {
  const p = PHASES[v.phase] || {}
  const offset = useMemo(() => (v.now ? new Date(v.now).getTime() - Date.now() : 0), [v.now])
  const left = useCountdown(v.ends_at, offset)
  const seen = v.seats.filter((s) => s.seen).length
  const alive = v.seats.filter((s) => s.alive)

  // Quién debe actuar en esta fase
  const needs = (s) => {
    if (s.away) return false
    if (v.phase === 'night') return s.alive
    if (v.phase === 'night_witch') return s.alive && s.role === 'bruja'
    if (v.phase === 'mayor' || v.phase === 'vote') return s.alive
    if (v.phase === 'duty') return s.duty_hunter || s.duty_mayor
    return false
  }
  const waiting = v.seats.filter(needs)
  const done = waiting.filter((s) => s.acted).length

  return (
    <>
      <div className="narr-phase">
        <div className="narr-phase-title">{p.emoji} {p.label} {v.phase === 'night' || v.phase === 'night_witch' ? v.night_no : v.day_no ? `· día ${v.day_no}` : ''}</div>
        {v.ends_at && <div className="timer-pill">{left > 0 ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}` : '⏰ tiempo'}</div>}
      </div>
      <blockquote className="narr-script">{narratorScript(v.phase, v)}</blockquote>

      {v.phase === 'dealt' && <p className="small">👁 {seen}/{v.seats.length} ya vieron su carta</p>}
      {waiting.length > 0 && <p className="small">✍️ Respondieron: <b>{done}/{waiting.length}</b></p>}
      {(v.phase === 'night' || v.phase === 'night_witch') && (
        <p className="small">🐺 Víctima de la manada: <b>{v.victim || 'aún nadie'}</b>
          {v.phase === 'night_witch' && v.witch_actions?.length > 0 && <> · 🧪 {v.witch_actions.map((w) => `${w.kind === 'heal' ? 'salva a' : 'envenena a'} ${w.target}`).join(', ')}</>}
        </p>
      )}
      {['dawn', 'verdict', 'debate', 'mayor'].includes(v.phase) && v.last_result && <WolfResult r={v.last_result} />}
      {(v.phase === 'mayor' || v.phase === 'vote' || v.phase === 'night') && v.actions.length > 0 && (
        <details className="small"><summary>Ver respuestas ({v.actions.length})</summary>
          <ul>{v.actions.map((a, i) => <li key={i}>{a.actor} → {a.target} <span className="muted">({a.kind})</span></li>)}</ul>
        </details>
      )}

      <button className="btn primary" disabled={busy} onClick={() => call('wolf_advance', {},
        waiting.length && done < waiting.length ? `Faltan ${waiting.length - done} por responder. Quien no actuó pierde su acción. ¿Avanzar?` : null)}>
        ▶︎ Siguiente fase
      </button>

      <SeatList v={v} call={call} />
      <p className="small muted">Vivos: {alive.length} · 🐺 lobos vivos: {alive.filter((s) => s.role === 'lobo').length}</p>

      <details className="small">
        <summary>🏁 Terminar a mano</summary>
        <div className="row" style={{ marginTop: 6 }}>
          <button className="btn small" onClick={() => call('wolf_declare_winner', { p_winner: 'village' }, '¿Declarar ganadora a la aldea?')}>🏡 Ganó la aldea</button>
          <button className="btn small" onClick={() => call('wolf_declare_winner', { p_winner: 'wolves' }, '¿Declarar ganadores a los lobos?')}>🐺 Ganaron los lobos</button>
        </div>
      </details>
    </>
  )
}

function SeatList({ v, call }) {
  const away = v.seats.filter((s) => s.alive && s.away)
  return (
    <>
      {call && away.length > 0 && (
        <div className="away-note small">⏸️ En pausa: <b>{away.map((s) => s.name).join(', ')}</b>. Si no vuelve, 🚪 lo da por muerto.</div>
      )}
      <ul className="narr-seats">
        {v.seats.map((s) => {
          const r = roleOf(s.role)
          return (
            <li key={s.id} className={`${s.alive ? '' : 'dead'} ${s.alive && s.away ? 'away' : ''}`}>
              <span className="seat-n">{s.seat}</span>
              <span className="grow"><b>{s.name}</b>{s.mayor ? ' 🎖️' : ''}{s.alive && s.away ? ' ⏸️' : ''} <span className="small muted">{r.emoji} {r.name}{s.role === 'bruja' ? ` (${s.heal_left ? '💚' : '·'}${s.kill_left ? '☠️' : '·'})` : ''}</span></span>
              {s.alive && (s.acted ? <span title="respondió">✅</span> : null)}
              {call && s.alive && (s.away
                ? <>
                    <button className="btn small ghost-btn" title="Volvió" onClick={() => call('admin_set_away', { p_player: s.id, p_away: false })}>▶︎</button>
                    <button className="btn small ghost-btn" title="Se fue: darlo por muerto" onClick={() => call('wolf_kill_away', { p_player: s.id }, `¿${s.name} no vuelve? Se da por muerto y se revela su carta.`)}>🚪</button>
                  </>
                : <button className="btn small ghost-btn" title="Poner en pausa" onClick={() => call('admin_set_away', { p_player: s.id, p_away: true })}>⏸️</button>)}
              {call && (s.alive
                ? <button className="btn small ghost-btn" title="Matar" onClick={() => call('wolf_override', { p_player: s.id, p_alive: false }, `¿Matar a ${s.name}?`)}>💀</button>
                : <button className="btn small ghost-btn" title="Revivir" onClick={() => call('wolf_override', { p_player: s.id, p_alive: true }, `¿Revivir a ${s.name}?`)}>💚</button>)}
            </li>
          )
        })}
      </ul>
    </>
  )
}

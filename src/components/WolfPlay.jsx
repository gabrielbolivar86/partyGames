import { useMemo, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLiveRpc } from '../hooks/useLiveRpc'
import { useCountdown } from '../hooks/usePersona'
import { ROLES, roleOf, PHASES } from '../lib/wolfRoles'
import WolfNarrator from './WolfNarrator'

/**
 * Hombre Lobo en el celular. Si este invitado es el narrador, muestra su panel.
 * Los datos vienen de wolf_my_view(): el servidor solo manda lo que esta persona puede saber.
 */
export default function WolfPlay() {
  const { data: v, refresh } = useLiveRpc('wolf_my_view', ['wolf_state'], { debounceMs: 120 })
  if (!v || v.status === 'none') return null
  if (v.is_narrator) return <WolfNarrator />

  return (
    <section className="card wolf live-wolf">
      <div className="costume-head">
        <h3>🐺 Hombre Lobo</h3>
        {v.status === 'playing' && <PhasePill v={v} />}
      </div>
      {v.status === 'lobby' && <Lobby v={v} />}
      {v.status === 'setup' && (v.joined
        ? <p className="hint">🃏 El narrador está preparando la baraja… en un momento te llega tu carta.</p>
        : <NotSeated v={v} />)}
      {(v.status === 'playing' || v.status === 'finished') && (v.joined ? <Playing v={v} onDone={refresh} /> : <p className="hint">👀 Esta partida ya empezó: entras automáticamente en la siguiente. ¡Mírala en la pantalla! Narra {v.narrator}.</p>)}
    </section>
  )
}

function PhasePill({ v }) {
  const offset = useMemo(() => (v.now ? new Date(v.now).getTime() - Date.now() : 0), [v.now])
  const left = useCountdown(v.ends_at, offset)
  const p = PHASES[v.phase] || {}
  return <span className="timer-pill wolf-pill">{p.emoji} {v.phase === 'night' || v.phase === 'night_witch' ? `Noche ${v.night_no}` : v.phase === 'finished' ? 'Fin' : `Día ${v.day_no || 1}`}{v.ends_at && left > 0 ? ` · ${fmt(left)}` : ''}</span>
}

const fmt = (s) => (s >= 60 ? `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}` : `${s}s`)

function Lobby({ v }) {
  if (!v.joined) return <NotSeated v={v} />
  return (
    <>
      <p className="hint">Se abrió una mesa de <b>Hombre Lobo</b>. Narra <b>{v.narrator}</b>. Juegan <b>{v.joined_count}</b> personas.</p>
      <div className="success">✅ Ya estás en la mesa (entran todos automáticamente). Espera a que el narrador reparta las cartas.</div>
    </>
  )
}

function NotSeated({ v }) {
  return v.away
    ? <p className="away-note">⏸️ Estás ausente, así que no entras en esta partida. Toca <b>“Ya volví”</b> antes de que repartan para entrar.</p>
    : <p className="hint">El narrador te dejó fuera de esta partida. Si quieres jugar, avísale a <b>{v.narrator}</b>.</p>
}

function Playing({ v, onDone }) {
  const role = roleOf(v.role)
  const p = PHASES[v.phase] || {}

  if (v.status === 'finished' || v.phase === 'finished') {
    const won = (v.winner === 'wolves') === (role.team === 'wolves')
    return (
      <div className={`imp-final ${won ? 'crew' : 'impostors'}`}>
        <div className="imp-winner">{v.winner === 'wolves' ? '🐺 ¡Ganaron los lobos!' : '🏡 ¡Ganó la aldea!'}</div>
        <div>Eras <b>{role.emoji} {role.name}</b>{won ? ' · ¡ganaste! 🎉' : ''}</div>
      </div>
    )
  }

  // Muerto: solo su estado (y su deber si es cazador/alcalde)
  if (!v.alive) {
    return (
      <>
        <div className="wolf-dead">💀 <b>Estás muerto</b> · Eras {role.emoji} <b>{role.name}</b><div className="small muted">{v.death_text}</div></div>
        {(v.action === 'shoot' || v.action === 'successor') && <ActionBox v={v} onDone={onDone} />}
        {!v.action && <p className="hint">Ya no puedes hablar ni votar. ¡Disfruta viendo cómo sigue la partida! 🤐</p>}
      </>
    )
  }

  return (
    <>
      {v.away && <p className="away-note">⏸️ Estás ausente: tu carta se guarda, pero no actúas ni te pueden elegir. Toca <b>“Ya volví”</b> para seguir.</p>}
      <WolfCard v={v} />
      {v.neighbors && <p className="small muted">🪑 Siéntate entre <b>{v.neighbors[0]}</b> y <b>{v.neighbors[1]}</b>{v.is_mayor ? ' · 🎖️ Eres el alcalde' : ''}</p>}
      <p className="hint">{p.emoji} {p.player}</p>
      {v.last_result && ['dawn', 'verdict', 'debate'].includes(v.phase) && <WolfResult r={v.last_result} />}
      {v.action && <ActionBox v={v} onDone={onDone} />}
    </>
  )
}

// Carta: mantener presionado para verla
function WolfCard({ v }) {
  const [show, setShow] = useState(false)
  const role = roleOf(v.role)
  const on = () => { setShow(true); if (!v.card_seen) supabase.rpc('wolf_mark_seen') }
  const off = () => setShow(false)
  return (
    <div className={`secret-card wolf-card ${show ? 'open' : ''} ${show && role.team === 'wolves' ? 'imp' : ''}`}
      onPointerDown={on} onPointerUp={off} onPointerLeave={off} onPointerCancel={off} onContextMenu={(e) => e.preventDefault()}>
      {show ? (
        <>
          <div className="wolf-emoji">{role.emoji}</div>
          <div className="secret-role" style={{ color: role.team === 'wolves' ? 'var(--red)' : 'var(--green)' }}>{role.name.toUpperCase()}</div>
          <div className="small">{role.does}</div>
          <div className="small muted">{role.wins}</div>
          {v.extra?.pack?.length > 0 && <div className="small">🐺 Tu manada: <b>{v.extra.pack.map((x) => x.name + (x.alive ? '' : ' 💀')).join(', ')}</b></div>}
          {v.extra?.potions && <div className="small">🧪 Pociones: salvar {v.extra.potions.heal ? '✅' : '❌'} · veneno {v.extra.potions.kill ? '✅' : '❌'}</div>}
        </>
      ) : (
        <>
          <div className="secret-q">🂠</div>
          <div><b>Mantén presionado</b> para ver tu carta</div>
          <div className="small muted">Suelta para ocultarla</div>
        </>
      )}
    </div>
  )
}

function ActionBox({ v, onDone }) {
  const [msg, setMsg] = useState(null)
  const [busy, setBusy] = useState(false)
  const choice = v.my_choice || {}
  const alive = (v.players || []).filter((p) => p.alive && !p.away)
  const others = alive.filter((p) => p.id !== v.me)

  async function act(kind, target) {
    setBusy(true)
    setMsg(null)
    const { data, error } = await supabase.rpc('wolf_act', { p_kind: kind, p_target: target })
    setBusy(false)
    if (error || !data.ok) setMsg(error ? errorMessage(error) : data.error)
    else if (data.seen_role) setMsg(`🔮 Viste su carta: es ${data.seen_role}`)
    onDone()
  }

  const Picker = ({ kind, options, title }) => (
    <>
      <div className="wolf-q">{title}</div>
      <div className="vote-grid">
        {options.map((p) => (
          <button key={p.id} type="button" disabled={busy} className={`vote-btn ${choice[kind] === p.id ? 'active' : ''}`}
            onClick={() => act(kind, choice[kind] === p.id ? null : p.id)}>
            {p.name}{p.mayor ? ' 🎖️' : ''}
          </button>
        ))}
      </div>
    </>
  )

  const packNames = new Set((v.extra?.pack || []).map((x) => x.name))

  let body = null
  switch (v.action) {
    case 'wolf':
      body = (
        <>
          <Picker kind="wolf" title="🐺 ¿A quién atacan esta noche?" options={others.filter((p) => !packNames.has(p.name))} />
          {v.extra?.pack?.length > 0 && (
            <div className="small muted">Tu manada eligió: {v.extra.pack.filter((x) => x.alive).map((x) => `${x.name} → ${x.choice || '…'}`).join(' · ')}</div>
          )}
          <p className="hint">Gana la mayoría de la manada. Pónganse de acuerdo con la mirada 👀</p>
        </>
      )
      break
    case 'seer': {
      const seen = choice.seer
      body = seen
        ? <div className="success">🔮 {v.extra?.visions?.length ? `${v.extra.visions[v.extra.visions.length - 1].name} es ${v.extra.visions[v.extra.visions.length - 1].role}` : 'Visión usada'}</div>
        : <Picker kind="seer" title="🔮 ¿De quién quieres ver la carta? (no se puede cambiar)" options={others} />
      break
    }
    case 'suspect':
      body = <Picker kind="suspect" title="🤔 ¿De quién sospechas? (todos responden para que nadie se delate)" options={others} />
      break
    case 'witch': {
      const w = v.extra?.witch || {}
      body = (
        <>
          <div className="wolf-q">🧪 Esta noche los lobos atacaron a: <b>{w.victim || 'nadie'}</b></div>
          {w.heal_left && w.victim_id && (
            <button className={`btn ${choice.heal ? 'ok' : ''}`} disabled={busy} onClick={() => act('heal', choice.heal ? null : w.victim_id)}>
              {choice.heal ? '✅ Lo salvarás (tocar para deshacer)' : `💚 Usar poción de vida en ${w.victim}`}
            </button>
          )}
          {!w.heal_left && <p className="small muted">Ya usaste la poción de vida.</p>}
          {w.kill_left
            ? <Picker kind="poison" title="☠️ ¿Envenenar a alguien? (opcional)" options={others} />
            : <p className="small muted">Ya usaste el veneno.</p>}
          <p className="hint">Si no haces nada, no gastas pociones.</p>
        </>
      )
      break
    }
    case 'mayor':
      body = <Picker kind="mayor" title="🎖️ ¿Quién debe ser alcalde?" options={alive} />
      break
    case 'vote':
      body = <Picker kind="vote" title={`🗳 ¿A quién linchar?${v.is_mayor ? ' (tu voto vale doble)' : ''}`} options={others} />
      break
    case 'shoot':
      body = <Picker kind="shoot" title="🏹 Eres el cazador: ¿a quién disparas antes de morir?" options={others} />
      break
    case 'successor':
      body = <Picker kind="successor" title="🎖️ Eras alcalde: ¿quién te sucede?" options={others} />
      break
    default:
      body = null
  }
  return <div className="wolf-action">{body}{msg && <div className={msg.startsWith('🔮') ? 'success' : 'error'}>{msg}</div>}</div>
}

export function WolfResult({ r, big = false }) {
  if (!r) return null
  let content = null
  if (r.type === 'left') {
    content = r.deaths.map((d) => <div key={d.name}>🚪 <b>{d.name}</b> se retiró de la partida. Era <b>{d.role}</b>.</div>)
  } else if (r.type === 'night' || r.type === 'shot') {
    content = r.deaths?.length
      ? r.deaths.map((d) => <div key={d.name}>☠️ <b>{d.name}</b> murió. Era <b>{d.role}</b>.</div>)
      : <div>🌅 La aldea despierta sin bajas.</div>
  } else if (r.type === 'mayor') {
    content = r.name ? <div>🎖️ <b>{r.name}</b> es el alcalde.</div> : <div>Nadie fue elegido alcalde.</div>
  } else if (r.type === 'vote') {
    content = (
      <>
        {r.lynched ? <div>⚖️ La aldea linchó a <b>{r.lynched.name}</b>. Era <b>{r.lynched.role}</b>.</div>
          : <div>⚖️ {r.tie ? 'Empate:' : 'Sin votos:'} nadie fue linchado.</div>}
        {r.votes?.length > 0 && (
          <div className="wolf-votes">
            {r.votes.map((x) => <div key={x.target}><b>{x.target}</b> ({x.votes}) ← {x.voters.join(', ')}</div>)}
          </div>
        )}
      </>
    )
  }
  return <div className={`imp-result ${big ? 'big' : ''}`}>{content}</div>
}

export { ROLES }

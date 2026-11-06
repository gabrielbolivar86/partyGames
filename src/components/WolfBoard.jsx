import { useMemo } from 'react'
import { useLiveRpc } from '../hooks/useLiveRpc'
import { useCountdown } from '../hooks/usePersona'
import { ROLES, roleOf, PHASES } from '../lib/wolfRoles'
import { WolfResult } from './WolfPlay'

const ORDER = ['lobo', 'vidente', 'bruja', 'cazador', 'aldeano']

// Pantalla del Hombre Lobo: fase, mesa en círculo, baraja con cartas tachadas, resultados
export default function WolfBoard() {
  const { data: v } = useLiveRpc('wolf_public_view', ['wolf_state'], { debounceMs: 150 })
  const offset = useMemo(() => (v?.now ? new Date(v.now).getTime() - Date.now() : 0), [v?.now])
  const left = useCountdown(v?.ends_at, offset)

  if (!v) return <div className="reveal"><p className="muted">Cargando…</p></div>
  if (v.status === 'none') return <div className="reveal"><h1 className="spooky reveal-title">🐺 Hombre Lobo</h1><p className="reveal-sub">Muy pronto…</p></div>

  if (v.status === 'lobby' || v.status === 'setup') {
    return (
      <div className="reveal">
        <h1 className="spooky reveal-title">🐺 Hombre Lobo</h1>
        <p className="reveal-sub">{v.status === 'lobby' ? <>¡Únete desde tu celular! Narra <b>{v.narrator}</b></> : '🃏 El narrador está preparando la baraja…'}</p>
        <div className="wolf-lobby">{v.players.map((p) => <span key={p.id} className="check-chip on">{p.name}</span>)}</div>
        <div className="reveal-sub">{v.players.length} jugadores</div>
      </div>
    )
  }

  const p = PHASES[v.phase] || {}
  const finished = v.status === 'finished'
  const isNight = v.phase === 'night' || v.phase === 'night_witch'

  return (
    <div className={`wolf-screen ${isNight ? 'night' : ''}`}>
      <div className="wolf-banner">
        <span className="wolf-banner-emoji">{p.emoji}</span>
        <div>
          <div className="wolf-banner-title">
            {finished ? (v.winner === 'wolves' ? '🐺 ¡Ganaron los lobos!' : '🏡 ¡Ganó la aldea!')
              : `${p.label}${isNight ? ` ${v.night_no}` : v.day_no ? ` · día ${v.day_no}` : ''}`}
          </div>
          {!finished && <div className="wolf-banner-sub">{p.tv}</div>}
        </div>
        {!finished && v.ends_at && <div className="wolf-clock">{left > 0 ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}` : '⏰'}</div>}
      </div>

      <div className="wolf-body">
        <Circle players={v.players} showVotes={v.phase === 'vote' || v.phase === 'mayor'} />
        <aside className="wolf-side">
          {v.phase === 'dealt' && v.deck && <Explain deck={v.deck} />}
          {v.last_result && ['dawn', 'verdict', 'mayor', 'debate', 'duty', 'finished'].includes(v.phase) && <WolfResult r={v.last_result} big />}
          {v.deck && v.phase !== 'dealt' && <DeckProgress deck={v.deck} players={v.players} />}
          {(v.phase === 'vote' || v.phase === 'mayor') && (
            <div className="reveal-sub">🗳 {v.players.filter((x) => x.voted).length} de {v.players.filter((x) => x.alive).length} votaron</div>
          )}
        </aside>
      </div>
    </div>
  )
}

function Circle({ players, showVotes }) {
  const n = players.length || 1
  return (
    <div className="wolf-circle">
      <div className="wolf-campfire">🔥</div>
      {players.map((pl, i) => {
        const ang = (i / n) * 2 * Math.PI - Math.PI / 2
        const r = roleOf(pl.role)
        return (
          <div key={pl.id} className={`wolf-seat ${pl.alive ? '' : 'dead'}`}
            style={{ left: `${50 + 42 * Math.cos(ang)}%`, top: `${50 + 42 * Math.sin(ang)}%` }}>
            <div className="seat-name">{pl.mayor ? '🎖️ ' : ''}{pl.name}</div>
            {!pl.alive && <div className="seat-role">💀 {r.emoji} {r.name}</div>}
            {pl.alive && pl.role && <div className="seat-role">{r.emoji} {r.name}</div>}
            {pl.alive && pl.away && <div className="seat-role">⏸️ en pausa</div>}
            {showVotes && pl.alive && !pl.away && <div className="seat-vote">{pl.voted ? '✅' : '⏳'}</div>}
          </div>
        )
      })}
    </div>
  )
}

// Baraja con cartas tachadas a medida que muere cada rol (no revela nada nuevo: los muertos ya son públicos)
function DeckProgress({ deck, players }) {
  const dead = {}
  players.filter((p) => !p.alive && p.role).forEach((p) => { dead[p.role] = (dead[p.role] || 0) + 1 })
  return (
    <div className="deck-progress">
      <h3>🃏 Baraja en juego</h3>
      {ORDER.filter((k) => deck[k]).map((k) => (
        <div key={k} className="deck-line">
          <span className="deck-name">{ROLES[k].name}</span>
          <span>{Array.from({ length: deck[k] }, (_, i) => (
            <span key={i} className={`deck-card ${i < (dead[k] || 0) ? 'gone' : ''}`}>{ROLES[k].emoji}</span>
          ))}</span>
        </div>
      ))}
      <div className="small muted">Vivos: {players.filter((p) => p.alive).length} · Muertos: {players.filter((p) => !p.alive).length}</div>
    </div>
  )
}

function Explain({ deck }) {
  return (
    <div className="wolf-explain">
      <h3>📜 Roles en esta partida</h3>
      {ORDER.filter((k) => deck[k]).map((k) => (
        <div key={k} className="explain-role">
          <span className="explain-emoji">{ROLES[k].emoji}</span>
          <div><b>{ROLES[k].name} ×{deck[k]}</b><div className="small">{ROLES[k].does}</div></div>
        </div>
      ))}
      <div className="small muted">Mantén presionada tu carta para verla · De día se vota en el celular · Los muertos no hablan</div>
    </div>
  )
}

import { useLiveRpc } from '../hooks/useLiveRpc'

const MEDALS = ['🥇', '🥈', '🥉']

// Pantalla final: todos con sus puntos, el podio y el mejor disfraz.
// Si la tabla estuvo congelada, muestra cuánto sumó cada uno al final (la sorpresa).
export default function FinalResults() {
  const { data } = useLiveRpc('get_final_results', ['points_ledger', 'dashboard_state', 'players'], { debounceMs: 300 })
  if (!data || !data.available) return <div className="reveal"><p className="muted">Cargando resultados…</p></div>

  const list = data.players
  const podium = list.slice(0, 3)
  const rest = list.slice(3)
  const n = list.length

  return (
    <div className="final">
      <h1 className="spooky final-title">🏆 Resultados de la noche</h1>
      {data.was_frozen && <p className="reveal-sub">Con los puntos de último momento incluidos 👀</p>}

      <div className="final-podium">
        {[1, 0, 2].map((i) => podium[i] && (
          <div key={podium[i].player_id} className={`final-pod p${i + 1}`} style={{ animationDelay: `${(n + (2 - i)) * 0.08 + 0.6}s` }}>
            <div className="medal">{MEDALS[i]}</div>
            <div className="pname">{podium[i].nickname || podium[i].name}</div>
            <div className="ppts">{podium[i].points}<small> pts</small></div>
            {podium[i].late_points !== 0 && <div className="late">+{podium[i].late_points} al final</div>}
          </div>
        ))}
      </div>

      {data.best_costume && (
        <div className="final-costume">🎭 Mejor disfraz: <b>{data.best_costume.nickname || data.best_costume.name}</b> · {data.best_costume.costume}</div>
      )}

      <ol className="final-list" start={4}>
        {rest.map((p, idx) => (
          <li key={p.player_id} style={{ animationDelay: `${(rest.length - idx) * 0.08}s` }}>
            <span className="pos">{idx + 4}</span>
            <span className="who">{p.nickname || p.name}</span>
            {p.late_points !== 0 && <span className="late">+{p.late_points}</span>}
            <span className="pts">{p.points}</span>
          </li>
        ))}
      </ol>
      <Confetti />
    </div>
  )
}

function Confetti() {
  const emojis = ['🎃', '🏆', '✨', '👻', '🍬', '🦇']
  return (
    <div className="confetti" aria-hidden="true">
      {Array.from({ length: 30 }, (_, i) => (
        <span key={i} style={{ left: `${(i * 41) % 100}%`, animationDelay: `${2 + (i % 10) * 0.4}s`, animationDuration: `${5 + (i % 4)}s`, fontSize: `${1.4 + (i % 3) * 0.6}rem` }}>
          {emojis[i % emojis.length]}
        </span>
      ))}
    </div>
  )
}

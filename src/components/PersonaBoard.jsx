import { usePersonaRpc, useCountdown } from '../hooks/usePersona'

// Pantalla del juego "¿Quién es el personaje?"
export default function PersonaBoard() {
  const { data, offset } = usePersonaRpc('get_persona_board')
  if (!data) return <div className="reveal"><p className="muted">Cargando…</p></div>

  const round = data.round
  if (!round) {
    return (
      <div className="reveal">
        <h1 className="spooky reveal-title">🕵️ ¿Quién es el personaje?</h1>
        <p className="reveal-sub">Preparando la siguiente ronda… {data.rounds_done > 0 && `(${data.rounds_done} jugadas)`}</p>
      </div>
    )
  }
  return round.status === 'revealed' ? <Result round={round} /> : <Voting round={round} offset={offset} />
}

function Voting({ round, offset }) {
  const left = useCountdown(round.ends_at, offset)
  const timeUp = left === 0
  return (
    <div className="reveal persona-screen">
      <div className="persona-round">Ronda #{round.number} · ¿Quién es el personaje?</div>
      <blockquote className="persona-big-fact">“{round.fact}”</blockquote>
      <div className={`persona-clock ${left <= 5 ? 'hot' : ''} ${timeUp ? 'up' : ''}`} key={timeUp ? 'up' : 'run'}>
        {timeUp ? '¡Tiempo!' : left}
      </div>
      <div className="reveal-sub">🗳 {round.votes} {round.votes === 1 ? 'voto' : 'votos'} · ¡vota desde tu celular!</div>
    </div>
  )
}

function Result({ round }) {
  const r = round.result
  const max = Math.max(1, ...r.distribution.map((d) => d.votes))
  const pct = r.total ? Math.round((r.correct / r.total) * 100) : 0
  return (
    <div className="reveal persona-screen">
      <div className="persona-round">Ronda #{round.number}</div>
      <blockquote className="persona-mid-fact">“{round.fact}”</blockquote>
      <div className="persona-era">Era…</div>
      <div className="persona-owner">{r.owner.nickname || r.owner.name}</div>
      {r.owner.costume && <div className="reveal-costume">{r.owner.costume}</div>}
      <div className={`caught-banner ${r.caught ? 'caught' : 'free'}`}>
        {r.caught ? `🎯 ¡Atrapado! +${r.owner_points} por participar` : `😎 ¡No lo atraparon! Puntos x2: +${r.owner_points}`}
      </div>

      <div className="persona-bars">
        {r.distribution.map((d) => (
          <div key={d.name} className={`pbar ${d.correct ? 'ok' : ''}`}>
            <span className="pbar-name">{d.correct && '✅ '}{d.name}</span>
            <span className="pbar-track"><span className="pbar-fill" style={{ width: `${(d.votes / max) * 100}%` }} /></span>
            <span className="pbar-n">{d.votes}</span>
          </div>
        ))}
        {r.total === 0 && <p className="muted">Nadie votó 😶</p>}
      </div>
      <div className="reveal-sub">{r.correct} de {r.total} acertaron ({pct}%)</div>
    </div>
  )
}

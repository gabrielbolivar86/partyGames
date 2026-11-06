import { useLiveRpc } from '../hooks/useLiveRpc'
import { KIND_LABEL } from '../lib/impostor'
import { LastResult } from './ImpostorGame'

// Pantalla de El Impostor: orden para hablar, votación en vivo (quién votó a quién) y resultados
export default function ImpostorBoard() {
  const { data } = useLiveRpc('get_impostor_board', ['impostor_game', 'impostor_votes'])
  if (!data) return <div className="reveal"><p className="muted">Cargando…</p></div>
  if (data.status === 'none') {
    return (
      <div className="reveal">
        <h1 className="spooky reveal-title">🕵️ El Impostor</h1>
        <p className="reveal-sub">Preparando la siguiente ronda…</p>
      </div>
    )
  }

  const finished = data.status === 'finished'
  const vote = data.vote
  const maxVotes = Math.max(1, ...vote.tally.map((t) => t.votes))

  return (
    <div className="imp-screen">
      <header className="dash-head">
        <h1 className="spooky">🕵️ El Impostor</h1>
        <div className="dash-meta">Ronda #{data.number} · {data.impostor_count} {data.impostor_count === 1 ? 'impostor' : 'impostores'}</div>
      </header>

      {finished && (
        <div className={`imp-final big ${data.winner}`}>
          <div className="imp-winner">{data.winner === 'crew' ? '🛡 ¡Ganó la tripulación!' : '🕵️ ¡Ganaron los impostores!'}</div>
          <div>{data.win_reason}</div>
          <div className="imp-word">La palabra era <b>{data.word}</b></div>
        </div>
      )}

      <div className="imp-body">
        <section>
          <h2>{finished ? 'Jugadores' : '🎤 Orden para hablar'}</h2>
          <ol className="imp-order">
            {data.players.map((p) => (
              <li key={p.id} className={`${p.alive ? '' : 'dead'} ${p.role === 'impostor' ? 'is-imp' : ''}`}>
                <span className="ord">{p.order}</span>
                <span className="who">{p.name}</span>
                {p.role && <span className="role-tag">{p.role === 'impostor' ? '🕵️ Impostor' : '🛡 Tripulante'}</span>}
                {!p.alive && <span className="skull">☠️</span>}
                {p.alive && p.away && <span className="away-tag">⏸️ ausente</span>}
              </li>
            ))}
          </ol>
        </section>

        <section>
          {!finished && vote.status === 'none' && (
            <div className="imp-wait">Cada uno dice <b>una palabra</b> relacionada, en orden.<br />Luego se vota quién es el impostor 👀</div>
          )}
          {vote.no > 0 && (
            <>
              <h2>
                {vote.status === 'open' ? '🗳 Votando · ' : 'Resultado · '}
                <span className={`kind-badge ${vote.kind}`}>{KIND_LABEL[vote.kind].long}</span>
              </h2>
              {vote.status === 'open' && <div className="reveal-sub">{vote.voted} de {vote.eligible} votaron · ¡vota en tu celular!</div>}
              <div className="imp-tally">
                {vote.tally.map((t) => (
                  <div key={t.id} className="imp-tally-row">
                    <div className="imp-tally-head">
                      <span className="pbar-name">{t.name}</span>
                      <span className="pbar-track"><span className="pbar-fill" style={{ width: `${(t.votes / maxVotes) * 100}%` }} /></span>
                      <span className="pbar-n">{t.votes}</span>
                    </div>
                    <div className="imp-voters">← {t.voters.join(', ')}</div>
                  </div>
                ))}
                {vote.tally.length === 0 && <p className="muted">Aún no hay votos…</p>}
              </div>
            </>
          )}
          {data.last_result && vote.status !== 'open' && !finished && <LastResult r={data.last_result} big />}
        </section>
      </div>
    </div>
  )
}

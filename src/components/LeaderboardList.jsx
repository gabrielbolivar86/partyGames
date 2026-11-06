const MEDALS = { 1: '🥇', 2: '🥈', 3: '🥉' }

export default function LeaderboardList({ rows, highlightId, compact = false }) {
  if (!rows.length) return <p className="muted center-text">Aún no hay invitados aprobados.</p>
  return (
    <ol className={`board ${compact ? 'compact' : ''}`}>
      {rows.map((r) => (
        <li key={r.player_id} className={`${r.player_id === highlightId ? 'me' : ''} rank-${r.rank}`}>
          <span className="pos">{MEDALS[r.rank] || r.rank}</span>
          <span className="who">
            <strong>{r.name}</strong>
            {r.nickname && <span className="muted"> “{r.nickname}”</span>}
            {r.away && <span className="away-tag" title="En pausa"> ⏸️</span>}
          </span>
          <span className="pts">{r.points}</span>
        </li>
      ))}
    </ol>
  )
}

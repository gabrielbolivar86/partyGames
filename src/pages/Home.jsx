import { useLeaderboard } from '../hooks/useLeaderboard'
import LeaderboardList from '../components/LeaderboardList'
import CostumeVote from '../components/CostumeVote'
import CodeHunt from '../components/CodeHunt'
import PersonaGame, { MyFactCard } from '../components/PersonaGame'
import ImpostorGame from '../components/ImpostorGame'
import { useDashboard } from '../hooks/useDashboard'

export default function Home({ me }) {
  const { rows, loading } = useLeaderboard()
  const dash = useDashboard()
  const frozen = dash.data?.frozen && dash.data?.mode !== 'final'
  const mine = rows.find((r) => r.player_id === me.player.id)

  return (
    <main className="content">
      <section className="card me-card">
        <div>
          <h2>{me.player.nickname || me.player.name}</h2>
          <p className="muted">{me.player.has_costume ? `🧛 ${me.player.costume}` : 'Sin disfraz'}</p>
        </div>
        <div className="me-score">
          <div className="big">{mine ? mine.points : 0}</div>
          <div className="muted small">{mine ? `puntos · #${mine.rank}` : 'puntos'}</div>
        </div>
      </section>

      <ImpostorGame myId={me.player.id} />
      <PersonaGame />
      <CodeHunt />
      <CostumeVote />

      <section className="card">
        <h3>🏆 Tabla general</h3>
        {frozen && <p className="frozen-note">🔒 Tabla congelada: los últimos puntos se revelan al final de la noche.</p>}
        {loading ? <p className="muted">Cargando…</p> : <LeaderboardList rows={rows} highlightId={me.player.id} compact />}
      </section>

      <MyFactCard />
    </main>
  )
}

import { useEffect, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { useMyGames } from '../hooks/useMyGames'
import { useDashboard } from '../hooks/useDashboard'
import LeaderboardList from '../components/LeaderboardList'
import CostumeVote from '../components/CostumeVote'
import CodeHunt from '../components/CodeHunt'
import PersonaGame, { MyFactCard } from '../components/PersonaGame'
import ImpostorGame from '../components/ImpostorGame'
import GiftGame from '../components/GiftGame'
import WolfPlay from '../components/WolfPlay'

// Juegos que pueden aparecer como pestaña
const GAMES = {
  wolf: { emoji: '🐺', name: 'Hombre Lobo', short: 'Lobo' },
  gift: { emoji: '🎁', name: 'El Regalo Loco', short: 'Regalo' },
  impostor: { emoji: '🃏', name: 'El Impostor', short: 'Impostor' },
  persona: { emoji: '🕵️', name: '¿Quién es el personaje?', short: 'Personaje', newRound: true },
}
// Caza de códigos y voto de disfraz duran toda la noche: van en el menú, no como pestaña

const OPEN_KEY = 'pg-open-game'
const SEEN_KEY = 'pg-seen-games'
const readSeen = () => { try { return JSON.parse(localStorage.getItem(SEEN_KEY) || '[]') } catch { return [] } }
const writeSeen = (list) => { try { localStorage.setItem(SEEN_KEY, JSON.stringify(list.slice(-60))) } catch { /* sin storage */ } }

const label = (g) => (g.id === 'wolf' && g.narrator ? 'Narrar' : GAMES[g.id].short)

export default function Home({ me }) {
  const { data: mg, refresh: refreshGames } = useMyGames()
  const all = mg?.games || []
  const games = all.filter((g) => GAMES[g.id])
  const onMenu = { codes: all.some((g) => g.id === 'codes'), costume: all.some((g) => g.id === 'costume') }
  const away = !!mg?.away
  const [open, setOpenState] = useState(() => { try { return sessionStorage.getItem(OPEN_KEY) } catch { return null } })
  const [seen, setSeen] = useState(readSeen)

  const markSeen = (key) => setSeen((s) => { if (s.includes(key)) return s; const n = [...s, key]; writeSeen(n); return n })
  const setOpen = (id) => {
    setOpenState(id)
    try { id ? sessionStorage.setItem(OPEN_KEY, id) : sessionStorage.removeItem(OPEN_KEY) } catch { /* sin storage */ }
    const g = games.find((x) => x.id === id)
    if (g) markSeen(g.key)
    window.scrollTo(0, 0)
  }

  // Si el juego abierto terminó/desapareció, volver al menú
  const current = games.find((g) => g.id === open)
  useEffect(() => { if (mg && open && !current) setOpen(null) }, [mg, open, current]) // eslint-disable-line
  // Lo que ya estoy viendo no necesita aviso
  useEffect(() => { if (current && !seen.includes(current.key)) markSeen(current.key) }, [current?.key]) // eslint-disable-line

  // Aviso grande: el juego nuevo (o ronda nueva) que todavía no viste
  const fresh = games.find((g) => g.live && !seen.includes(g.key) && g.id !== open)

  return (
    <>
      {fresh && <StartBanner g={fresh} onEnter={() => setOpen(fresh.id)} onLater={() => markSeen(fresh.key)} />}
      {current ? (
        <div className="game-screen">
          <GameTabs games={games} open={open} setOpen={setOpen} />
          {away && <AwayBar onChange={refreshGames} />}
          <main className="content game-content">
            <GameView id={current.id} me={me} />
          </main>
        </div>
      ) : (
        <Menu me={me} games={games} onMenu={onMenu} away={away} setOpen={setOpen} refreshGames={refreshGames} />
      )}
    </>
  )
}

function GameView({ id, me }) {
  switch (id) {
    case 'wolf': return <WolfPlay />
    case 'gift': return <GiftGame />
    case 'impostor': return <ImpostorGame myId={me.player.id} />
    case 'persona': return <PersonaGame />
    default: return null
  }
}

function GameTabs({ games, open, setOpen }) {
  return (
    <nav className="game-tabs">
      <button className={`game-tab home ${!open ? 'active' : ''}`} onClick={() => setOpen(null)}>
        {open ? '← Menú' : '🏠 Menú'}
      </button>
      {games.map((g) => (
        <button key={g.id} className={`game-tab ${open === g.id ? 'active' : ''}`} onClick={() => setOpen(g.id)}>
          {GAMES[g.id].emoji} {label(g)}
          {g.attention && open !== g.id && <i className="dot" title="Te toca" />}
        </button>
      ))}
    </nav>
  )
}

function StartBanner({ g, onEnter, onLater }) {
  const info = GAMES[g.id]
  const title = g.id === 'wolf' && g.narrator ? '¡Te toca narrar el Hombre Lobo!'
    : info.newRound && g.status === 'voting' ? `¡Nueva ronda de ${info.name}!` : `¡Empezó ${info.name}!`
  return (
    <div className="start-banner" role="dialog">
      <div className="start-card">
        <div className="start-emoji">{info.emoji}</div>
        <div className="start-title spooky">{title}</div>
        <button className="btn primary big-btn" onClick={onEnter}>Entrar →</button>
        <button className="link-btn" onClick={onLater}>Ahora no</button>
      </div>
    </div>
  )
}

function Menu({ me, games, onMenu, away, setOpen, refreshGames }) {
  const { rows, loading } = useLeaderboard()
  const dash = useDashboard()
  const frozen = dash.data?.frozen && dash.data?.mode !== 'final'
  const mine = rows.find((r) => r.player_id === me.player.id)

  return (
    <main className="content">
      {away && <AwayBar onChange={refreshGames} />}
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

      <section className="card">
        <h3>🎮 Juegos</h3>
        {games.length === 0
          ? <p className="muted">Nada por ahora. ¡Atento a la pantalla! 📺</p>
          : (
            <div className="game-list">
              {games.map((g) => (
                <button key={g.id} className={`game-btn ${g.attention ? 'attention' : ''}`} onClick={() => setOpen(g.id)}>
                  <span className="game-btn-emoji">{GAMES[g.id].emoji}</span>
                  <span className="grow">
                    <b>{g.id === 'wolf' && g.narrator ? 'Hombre Lobo · narrar' : GAMES[g.id].name}</b>
                    <span className="small muted">{g.attention ? '👉 ¡Te toca!' : g.live ? 'En curso' : 'Ver resultado'}</span>
                  </span>
                  <span className="game-btn-go">Entrar →</span>
                </button>
              ))}
            </div>
          )}
      </section>

      {onMenu.costume && <CostumeVote />}
      {onMenu.codes && <CodeHunt />}

      <section className="card">
        <h3>🏆 Tabla general</h3>
        {frozen && <p className="frozen-note">🔒 Tabla congelada: los últimos puntos se revelan al final de la noche.</p>}
        {loading ? <p className="muted">Cargando…</p> : <LeaderboardList rows={rows} highlightId={me.player.id} compact />}
      </section>

      <MyFactCard />
      {!away && <AwayButton onChange={refreshGames} />}
    </main>
  )
}

async function setAway(value, onChange, setErr) {
  const { error } = await supabase.rpc('set_my_away', { p_away: value })
  if (error) setErr?.(errorMessage(error))
  onChange()
}

function AwayButton({ onChange }) {
  const [err, setErr] = useState(null)
  return (
    <div className="away-box">
      <span className="small muted">¿Necesitas hacer algo o ausentarte? Ponte en pausa.</span>
      <button className="btn small ghost-btn" onClick={() => {
        if (window.confirm('¿Ponerte en pausa? No jugarás hasta que vuelvas.')) setAway(true, onChange, setErr)
      }}>⏸️ Ponerme en pausa</button>
      {err && <div className="error">{err}</div>}
    </div>
  )
}

function AwayBar({ onChange }) {
  const [busy, setBusy] = useState(false)
  return (
    <div className="away-bar">
      <span>⏸️ <b>Estás en pausa</b></span>
      <button className="btn small primary" disabled={busy} onClick={async () => { setBusy(true); await setAway(false, onChange); setBusy(false) }}>▶︎ Ya volví</button>
    </div>
  )
}

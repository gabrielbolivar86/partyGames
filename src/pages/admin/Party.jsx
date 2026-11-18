import { useEffect, useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { supabase, errorMessage } from '../../lib/supabase'
import { joinUrl, dashboardUrl, hostUrl } from '../../lib/urls'
import { GAME_CATALOG, ALL_GAME_IDS } from '../../lib/games'
import { CopyLine } from '../Owner'
import WifiSettings from './Wifi'
import ThemePicker from '../../components/ThemePicker'

// "Mi fiesta": enlaces para invitados y TV, juegos de la noche y wifi (opcional)
export default function PartyAdmin({ party, games, theme, onGamesChanged }) {
  return (
    <>
      <section className="card form">
        <h3>🔗 Enlaces de {party?.name || 'la fiesta'}</h3>
        <div className="party-links">
          <div className="qr-box"><QRCodeSVG value={joinUrl()} size={150} bgColor="#ffffff" fgColor="#18181B" /></div>
          <div className="grow">
            <CopyLine label="👻 Invitados: mándales este enlace (o que escaneen el QR)" value={joinUrl()} />
            <CopyLine label="📺 Pantalla: ábrelo en la TV o en el computador conectado a ella" value={dashboardUrl()} />
          </div>
        </div>
        <div className="row">
          <a className="btn small" href={dashboardUrl()} target="_blank" rel="noreferrer">📺 Abrir pantalla aquí</a>
        </div>
        <p className="small muted">¿Otro anfitrión? Que entre en {hostUrl()} con la misma contraseña.</p>
      </section>
      <ThemeSection theme={theme} onChanged={onGamesChanged} />
      <GamesPicker games={games} onChanged={onGamesChanged} />
      <WifiSettings />
    </>
  )
}

function ThemeSection({ theme, onChanged }) {
  const [value, setValue] = useState(theme || 'fiesta')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => { if (theme) setValue(theme) }, [theme])

  async function choose(id) {
    const prev = value
    setValue(id)
    setBusy(true)
    const { error } = await supabase.rpc('admin_set_theme', { p_theme: id })
    setBusy(false)
    if (error) { setValue(prev); setError(errorMessage(error)) }
    else { setError(null); onChanged?.() }
  }

  return (
    <section className="card">
      <h3>Tema de la fiesta</h3>
      <p className="hint">Cambia los colores en tu panel, en la TV y en los celulares de todos, al momento.</p>
      {error && <div className="error">{error}</div>}
      <ThemePicker value={value} onChange={choose} busy={busy} />
    </section>
  )
}

function GamesPicker({ games, onChanged }) {
  const [on, setOn] = useState(() => new Set(games || ALL_GAME_IDS))
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => { if (games) setOn(new Set(games)) }, [games?.join(',')]) // eslint-disable-line

  async function toggle(id) {
    const next = new Set(on)
    next.has(id) ? next.delete(id) : next.add(id)
    setOn(next)
    setBusy(true)
    const { error } = await supabase.rpc('admin_set_games', { p_games: ALL_GAME_IDS.filter((g) => next.has(g)) })
    setBusy(false)
    if (error) { setError(errorMessage(error)); setOn(on) }
    else { setError(null); onChanged?.() }
  }

  return (
    <section className="card">
      <h3>🎮 Juegos de esta fiesta</h3>
      <p className="hint">Los que apagues desaparecen del panel, de la pantalla y de los celulares. Puedes cambiarlo cuando quieras.</p>
      {error && <div className="error">{error}</div>}
      <div className="game-picker">
        {GAME_CATALOG.map((g) => (
          <label key={g.id} className={`game-option ${on.has(g.id) ? 'active' : ''}`}>
            <input type="checkbox" checked={on.has(g.id)} disabled={busy} onChange={() => toggle(g.id)} />
            <span className="game-option-emoji">{g.emoji}</span>
            <span className="grow">
              <b>{g.name}</b>
              <span className="small">{g.description}</span>
              <span className="small muted">👥 {g.players} · ⏱ {g.duration}</span>
            </span>
          </label>
        ))}
      </div>
    </section>
  )
}

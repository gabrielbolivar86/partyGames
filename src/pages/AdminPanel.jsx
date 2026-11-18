import { useState } from 'react'
import { Icon } from '../components/Icon'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { useDashboard } from '../hooks/useDashboard'
import Requests, { usePendingRequests } from './admin/Requests'
import Players from './admin/Players'
import { PointsForm, LedgerList } from './admin/Points'
import CostumeAdmin from './admin/Costume'
import CodesAdmin from './admin/Codes'
import PersonaAdmin from './admin/Persona'
import ImpostorAdmin from './admin/Impostor'
import GiftAdmin from './admin/Gift'
import WolfAdmin from './admin/Wolf'
import Screen from './admin/Screen'
import Settings from './admin/Settings'
import PartyAdmin from './admin/Party'
import { tabEnabled } from '../lib/games'

const TABS = [
  { id: 'party', icon: 'IconHome', label: 'Mi fiesta' },
  { id: 'guests', icon: 'IconUsers', label: 'Invitados' },
  { id: 'points', icon: 'IconSparkles', label: 'Puntos' },
  { id: 'costume', icon: 'IconMasksTheater', label: 'Disfraces' },
  { id: 'codes', icon: 'IconSearch', label: 'Códigos' },
  { id: 'persona', icon: 'IconUserQuestion', label: 'Personaje' },
  { id: 'impostor', icon: 'IconSpy', label: 'Impostor' },
  { id: 'gift', icon: 'IconGift', label: 'Regalo' },
  { id: 'wolf', icon: 'IconMoon', label: 'Lobo' },
  { id: 'screen', icon: 'IconDeviceTv', label: 'Pantalla' },
  { id: 'settings', icon: 'IconSettings', label: 'Ajustes' },
]
const TAB_KEY = 'pg-admin-tab'

export default function AdminPanel({ me }) {
  const [tab, setTab] = useState(() => {
    try { return localStorage.getItem(TAB_KEY) || 'party' } catch { return 'party' }
  })
  const board = useLeaderboard()
  const pending = usePendingRequests() // siempre activo: muestra el contador en la pestaña
  const dashboard = useDashboard()
  const dashboardMode = dashboard.data?.mode
  const games = dashboard.data?.games
  const tabs = TABS.filter((t) => tabEnabled(games, t.id))
  // Si la pestaña guardada es de un juego apagado, volver a "Mi fiesta"
  const current = tabs.some((t) => t.id === tab) ? tab : 'party'

  const choose = (id) => {
    setTab(id)
    try { localStorage.setItem(TAB_KEY, id) } catch { /* sin storage */ }
  }

  return (
    <main className="content">
      <nav className="admin-tabs">
        {tabs.map((t) => (
          <button key={t.id} className={current === t.id ? 'active' : ''} onClick={() => choose(t.id)}>
            <Icon name={t.icon} size={18} />{t.label}
            {t.id === 'guests' && pending.items.length > 0 && <span className="badge">{pending.items.length}</span>}
          </button>
        ))}
      </nav>

      {current === 'party' && <PartyAdmin party={me.party} games={games} theme={dashboard.data?.party?.theme} onGamesChanged={dashboard.refresh} />}
      {current === 'guests' && (<><Requests pending={pending} /><Players myId={me.player.id} /></>)}
      {current === 'points' && (<><PointsForm players={board.rows} /><LedgerList /></>)}
      {current === 'costume' && <CostumeAdmin dashboardMode={dashboardMode} />}
      {current === 'codes' && <CodesAdmin dashboardMode={dashboardMode} />}
      {current === 'persona' && <PersonaAdmin dashboardMode={dashboardMode} />}
      {current === 'impostor' && <ImpostorAdmin players={board.rows} dashboardMode={dashboardMode} />}
      {current === 'gift' && <GiftAdmin players={board.rows} dashboardMode={dashboardMode} />}
      {current === 'wolf' && <WolfAdmin players={board.rows} dashboardMode={dashboardMode} />}
      {current === 'screen' && <Screen dashboardMode={dashboardMode} frozen={dashboard.data?.frozen} games={games} />}
      {current === 'settings' && <Settings />}
    </main>
  )
}

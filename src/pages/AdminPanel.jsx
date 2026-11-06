import { useState } from 'react'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { useDashboard } from '../hooks/useDashboard'
import Requests, { usePendingRequests } from './admin/Requests'
import Players from './admin/Players'
import { PointsForm, LedgerList } from './admin/Points'
import CostumeAdmin from './admin/Costume'
import CodesAdmin from './admin/Codes'
import PersonaAdmin from './admin/Persona'
import Screen from './admin/Screen'
import Settings from './admin/Settings'

const TABS = [
  { id: 'guests', label: '👥 Invitados' },
  { id: 'points', label: '✨ Puntos' },
  { id: 'costume', label: '🎭 Disfraces' },
  { id: 'codes', label: '🔍 Códigos' },
  { id: 'persona', label: '🕵️ Personaje' },
  { id: 'screen', label: '📺 Pantalla' },
  { id: 'settings', label: '🧹 Ajustes' },
]
const TAB_KEY = 'pg-admin-tab'

export default function AdminPanel({ me }) {
  const [tab, setTab] = useState(() => {
    try { return localStorage.getItem(TAB_KEY) || 'guests' } catch { return 'guests' }
  })
  const board = useLeaderboard()
  const pending = usePendingRequests() // siempre activo: muestra el contador en la pestaña
  const dashboard = useDashboard()
  const dashboardMode = dashboard.data?.mode

  const choose = (id) => {
    setTab(id)
    try { localStorage.setItem(TAB_KEY, id) } catch { /* sin storage */ }
  }

  return (
    <main className="content">
      <nav className="admin-tabs">
        {TABS.map((t) => (
          <button key={t.id} className={tab === t.id ? 'active' : ''} onClick={() => choose(t.id)}>
            {t.label}
            {t.id === 'guests' && pending.items.length > 0 && <span className="badge">{pending.items.length}</span>}
          </button>
        ))}
      </nav>

      {tab === 'guests' && (<><Requests pending={pending} /><Players myId={me.player.id} /></>)}
      {tab === 'points' && (<><PointsForm players={board.rows} /><LedgerList /></>)}
      {tab === 'costume' && <CostumeAdmin dashboardMode={dashboardMode} />}
      {tab === 'codes' && <CodesAdmin dashboardMode={dashboardMode} />}
      {tab === 'persona' && <PersonaAdmin dashboardMode={dashboardMode} />}
      {tab === 'screen' && <Screen dashboardMode={dashboardMode} />}
      {tab === 'settings' && <Settings />}
    </main>
  )
}

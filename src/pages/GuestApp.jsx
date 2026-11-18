import { useEffect, useState } from 'react'
import { Icon, ThemeIcon } from '../components/Icon'
import { useMe } from '../hooks/useMe'
import Join from './Join'
import Waiting from './Waiting'
import Home from './Home'
import AdminPanel from './AdminPanel'
import Spinner from '../components/Spinner'

const MODE_KEY = 'pg-admin-mode'

export default function GuestApp() {
  const { me, setMe, loading, error, notice, clearNotice, refresh } = useMe()
  const [adminMode, setAdminMode] = useState(() => readMode())

  useEffect(() => { saveMode(adminMode) }, [adminMode])

  if (loading) return <div className="screen center"><Spinner /></div>

  if (error && !me) {
    return (
      <div className="screen center">
        <div className="card">
          <h2>Algo salió mal</h2>
          <p>{error}</p>
          <button className="btn" onClick={() => window.location.reload()}>Reintentar</button>
        </div>
      </div>
    )
  }

  // Fase 10: el servidor dice null si el enlace apunta a una fiesta que no existe
  if (me && 'party' in me && !me.party) return <PartyNotFound isOwner={me.is_owner} />

  if (!me || me.status === 'none') {
    return <Join party={me?.party} notice={notice} clearNotice={clearNotice} onDone={(status) => setMe(status)} />
  }

  if (me.status === 'pending') {
    return <Waiting me={me} onChange={(status) => setMe(status)} onCheck={refresh} />
  }

  const isAdmin = me.player.is_admin
  const showAdmin = isAdmin && adminMode

  return (
    <div className="screen">
      <header className="topbar">
        <div className="brand"><ThemeIcon size={26} /><span>{me.party?.name || 'Juegos de fiesta'}</span></div>
        {me.is_owner && <a className="btn small" href="#/owner" title="Panel del dueño" aria-label="Panel del dueño"><Icon name="IconCrown" /></a>}
        {isAdmin && (
          <label className="switch" title="Cambiar entre modo invitado y modo admin">
            <span>{showAdmin ? 'Admin' : 'Invitado'}</span>
            <input type="checkbox" checked={showAdmin} onChange={(e) => setAdminMode(e.target.checked)} />
            <i />
          </label>
        )}
      </header>
      {showAdmin ? <AdminPanel me={me} /> : <Home me={me} />}
    </div>
  )
}

function PartyNotFound({ isOwner }) {
  return (
    <div className="screen center">
      <div className="card">
        <h2>Esta fiesta no existe</h2>
        <p>Revisa el enlace que te mandó tu anfitrión: puede tener un error o la fiesta ya fue borrada.</p>
        {isOwner && <a className="btn" href="#/owner"><Icon name="IconCrown" />Ir al panel del dueño</a>}
      </div>
    </div>
  )
}

function readMode() {
  try { return localStorage.getItem(MODE_KEY) === '1' } catch { return false }
}
function saveMode(on) {
  try { localStorage.setItem(MODE_KEY, on ? '1' : '0') } catch { /* sin storage */ }
}

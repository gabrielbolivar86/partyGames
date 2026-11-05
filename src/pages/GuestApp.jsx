import { useEffect, useState } from 'react'
import { useMe } from '../hooks/useMe'
import Join from './Join'
import Waiting from './Waiting'
import Home from './Home'
import AdminPanel from './AdminPanel'

const MODE_KEY = 'pg-admin-mode'

export default function GuestApp() {
  const { me, setMe, loading, error, notice, clearNotice, refresh } = useMe()
  const [adminMode, setAdminMode] = useState(() => readMode())

  useEffect(() => { saveMode(adminMode) }, [adminMode])

  if (loading) return <div className="screen center"><div className="spinner">🎃</div></div>

  if (error && !me) {
    return (
      <div className="screen center">
        <div className="card">
          <h2>😵 Algo salió mal</h2>
          <p>{error}</p>
          <button className="btn" onClick={() => window.location.reload()}>Reintentar</button>
        </div>
      </div>
    )
  }

  if (!me || me.status === 'none') {
    return <Join notice={notice} clearNotice={clearNotice} onDone={(status) => setMe(status)} />
  }

  if (me.status === 'pending') {
    return <Waiting me={me} onChange={(status) => setMe(status)} onCheck={refresh} />
  }

  const isAdmin = me.player.is_admin
  const showAdmin = isAdmin && adminMode

  return (
    <div className="screen">
      <header className="topbar">
        <div className="brand">🎃 <span>Halloween</span></div>
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

function readMode() {
  try { return localStorage.getItem(MODE_KEY) === '1' } catch { return false }
}
function saveMode(on) {
  try { localStorage.setItem(MODE_KEY, on ? '1' : '0') } catch { /* sin storage */ }
}

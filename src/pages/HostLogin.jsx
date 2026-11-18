import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase, errorMessage, ensureSession, getParty } from '../lib/supabase'

const MODE_KEY = 'pg-admin-mode'

// Entrada del anfitrión: enlace #/p/<fiesta>/anfitrion + contraseña que le dio el dueño
export default function HostLogin() {
  const navigate = useNavigate()
  const [status, setStatus] = useState(null) // respuesta de my_status()
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    (async () => {
      const err = await ensureSession()
      if (err) { setError(err); return }
      const { data, error } = await supabase.rpc('my_status')
      if (error) setError(errorMessage(error))
      else setStatus(data)
    })()
  }, [])

  const party = status?.party
  const already = status?.status === 'approved' && status.player?.is_admin
  const hasProfile = status && status.status !== 'none'

  function goToPanel() {
    try { localStorage.setItem(MODE_KEY, '1'); localStorage.setItem('pg-admin-tab', 'party') } catch { /* sin storage */ }
    navigate(`/p/${getParty()}/`)
  }

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { error } = await supabase.rpc('host_login', { p_password: password, p_name: name })
    setBusy(false)
    if (error) setError(errorMessage(error))
    else goToPanel()
  }

  if (!status && !error) return <div className="screen center"><div className="spinner">🎃</div></div>

  if (status && !party) {
    return (
      <div className="screen center">
        <div className="card"><h2>🦇 Esta fiesta no existe</h2><p>Revisa el enlace que te mandaron.</p></div>
      </div>
    )
  }

  return (
    <div className="screen join">
      <div className="hero">
        <div className="hero-emoji">🎃🔑</div>
        <h1 className="spooky">{party?.name || 'Anfitrión'}</h1>
        <p className="muted">Entrada para el anfitrión de la fiesta</p>
      </div>

      {already ? (
        <div className="card form">
          <p>Ya eres anfitrión de esta fiesta en este dispositivo, <b>{status.player.name}</b>.</p>
          <button className="btn primary" onClick={goToPanel}>Ir a mi panel →</button>
        </div>
      ) : (
        <form className="card form" onSubmit={submit}>
          {hasProfile
            ? <p className="hint">Este dispositivo ya está registrado como <b>{status.player.name}</b>. Con la contraseña lo conviertes en anfitrión.</p>
            : (
              <label>Tu nombre
                <input value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="Como te conocen en la fiesta" required />
              </label>
            )}
          <label>Contraseña de anfitrión
            <div className="row nowrap">
              <input type={show ? 'text' : 'password'} value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="off" required />
              <button className="btn small ghost-btn" type="button" onClick={() => setShow((s) => !s)}>{show ? '🙈' : '👁'}</button>
            </div>
          </label>
          {error && <div className="error">{error}</div>}
          <button className="btn primary" disabled={busy}>{busy ? 'Entrando…' : 'Entrar como anfitrión'}</button>
          <p className="small muted">¿Eres invitado? <a href={`#/p/${getParty()}/`}>Regístrate aquí</a>.</p>
        </form>
      )}
    </div>
  )
}

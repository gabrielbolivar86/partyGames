import { useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'

// Wifi (opcional): solo aparece en la pantalla si el anfitrión lo activa.
// Se guarda en Supabase (no en el código) y nadie puede leer la contraseña desde la app.
export default function WifiSettings() {
  const [f, setF] = useState({ ssid: '', password: '', security: 'WPA' })
  const [enabled, setEnabled] = useState(false)
  const [saved, setSaved] = useState(false)
  const [reveal, setReveal] = useState(false)
  const [msg, setMsg] = useState(null)

  useEffect(() => {
    supabase.rpc('admin_get_wifi').then(({ data }) => {
      if (!data) return
      setF({ ssid: data.ssid || '', password: data.password || '', security: data.security || 'WPA' })
      setEnabled(!!data.show)
      setSaved(!!data.ssid)
    })
  }, [])

  async function setShow(on) {
    setEnabled(on)
    if (!on && saved) {
      const { error } = await supabase.rpc('admin_set_wifi_show', { p_show: false })
      setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Wifi oculto de la pantalla' })
    }
  }

  async function save() {
    const { error } = await supabase.rpc('admin_set_wifi', { p_ssid: f.ssid, p_password: f.password, p_security: f.security })
    const show = error ? null : await supabase.rpc('admin_set_wifi_show', { p_show: true })
    const err = error || show?.error
    if (!err) setSaved(!!f.ssid)
    setMsg(err ? { type: 'error', text: errorMessage(err) } : { type: 'ok', text: 'Guardado: el QR ya aparece en la pantalla 📶' })
  }

  async function clear() {
    if (!window.confirm('¿Borrar los datos del wifi de esta fiesta?')) return
    const { error } = await supabase.rpc('admin_clear_wifi')
    if (!error) { setF({ ssid: '', password: '', security: 'WPA' }); setEnabled(false); setSaved(false) }
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Datos del wifi borrados' })
  }

  return (
    <section className="card form">
      <h3>📶 Wifi en la pantalla (opcional)</h3>
      <label className="check">
        <input type="checkbox" checked={enabled} onChange={(e) => setShow(e.target.checked)} />
        <span>Mostrar un QR del wifi en la pantalla</span>
      </label>
      {!enabled && <p className="hint">Apagado: la pantalla no muestra ningún dato del wifi. Útil solo si la fiesta es en tu casa.</p>}
      {enabled && (
        <>
          <input value={f.ssid} onChange={(e) => setF({ ...f, ssid: e.target.value })} placeholder="Nombre de la red (exacto, con mayúsculas)" />
          <div className="row nowrap">
            <input type={reveal ? 'text' : 'password'} value={f.password} disabled={f.security === 'nopass'}
              onChange={(e) => setF({ ...f, password: e.target.value })} placeholder="Contraseña" autoComplete="off" />
            <button className="btn small ghost-btn" type="button" onClick={() => setReveal((s) => !s)}>{reveal ? '🙈' : '👁'}</button>
          </div>
          <select value={f.security} onChange={(e) => setF({ ...f, security: e.target.value })}>
            <option value="WPA">WPA / WPA2 / WPA3 (lo normal)</option>
            <option value="WEP">WEP (routers muy antiguos)</option>
            <option value="nopass">Sin contraseña</option>
          </select>
          <button className="btn ok" disabled={!f.ssid.trim()} onClick={save}>Guardar y mostrar</button>
          <p className="small muted">Tip: escanea el QR de la pantalla con tu celular para confirmar que conecta.</p>
        </>
      )}
      {saved && <button className="btn small ghost-btn" onClick={clear}>🗑 Borrar datos del wifi</button>}
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
    </section>
  )
}

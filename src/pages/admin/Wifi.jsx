import { useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'

// Datos del wifi de la casa: se guardan en Supabase (no en GitHub) y la pantalla muestra el QR
export default function WifiSettings() {
  const [f, setF] = useState({ ssid: '', password: '', security: 'WPA' })
  const [show, setShow] = useState(false)
  const [msg, setMsg] = useState(null)

  useEffect(() => {
    supabase.rpc('admin_get_wifi').then(({ data }) => {
      if (data) setF({ ssid: data.ssid || '', password: data.password || '', security: data.security || 'WPA' })
    })
  }, [])

  async function save() {
    const { error } = await supabase.rpc('admin_set_wifi', { p_ssid: f.ssid, p_password: f.password, p_security: f.security })
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: f.ssid ? 'Guardado: el QR ya aparece en la pantalla 📶' : 'Wifi quitado de la pantalla' })
  }

  return (
    <section className="card form">
      <h3>📶 Wifi de la casa</h3>
      <p className="hint">La pantalla general mostrará un QR para conectarse. Se guarda en tu base de datos, no en el código.</p>
      <input value={f.ssid} onChange={(e) => setF({ ...f, ssid: e.target.value })} placeholder="Nombre de la red (exacto, con mayúsculas)" />
      <div className="row nowrap">
        <input type={show ? 'text' : 'password'} value={f.password} disabled={f.security === 'nopass'}
          onChange={(e) => setF({ ...f, password: e.target.value })} placeholder="Contraseña" autoComplete="off" />
        <button className="btn small ghost-btn" type="button" onClick={() => setShow((s) => !s)}>{show ? '🙈' : '👁'}</button>
      </div>
      <select value={f.security} onChange={(e) => setF({ ...f, security: e.target.value })}>
        <option value="WPA">WPA / WPA2 / WPA3 (lo normal)</option>
        <option value="WEP">WEP (routers muy antiguos)</option>
        <option value="nopass">Sin contraseña</option>
      </select>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <div className="row">
        <button className="btn ok" onClick={save}>Guardar wifi</button>
        {f.ssid && <button className="btn small ghost-btn" onClick={() => { setF({ ssid: '', password: '', security: 'WPA' }) }}>Vaciar</button>}
      </div>
      <p className="small muted">Tip: prueba escanear el QR de la pantalla con tu celular para confirmar que conecta.</p>
    </section>
  )
}

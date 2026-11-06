import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

// Hoja para imprimir los códigos (solo admin). Cada tarjeta muestra el código en grande para recortar y esconder.
export default function PrintCodes() {
  const [codes, setCodes] = useState(null)
  const [error, setError] = useState(null)
  const [showLabels, setShowLabels] = useState(true)

  useEffect(() => {
    supabase.rpc('admin_hunt_overview').then(({ data, error }) => {
      if (error) setError(error.message)
      else setCodes(data.codes)
    })
  }, [])

  if (error) {
    return (
      <div className="screen center">
        <div className="card">
          <h2>🔒 Solo el admin</h2>
          <p>{error}</p>
          <p className="muted small">Abre esta página en un dispositivo vinculado a tu perfil de admin (usa "Ya tengo perfil" en esta computadora y apruébalo).</p>
        </div>
      </div>
    )
  }
  if (!codes) return <div className="screen center"><div className="spinner">🎃</div></div>

  return (
    <div className="print-page">
      <div className="print-toolbar no-print">
        <button className="btn primary" onClick={() => window.print()}>🖨 Imprimir</button>
        <label className="check"><input type="checkbox" checked={showLabels} onChange={(e) => setShowLabels(e.target.checked)} /> Imprimir ubicación (pequeño)</label>
        <span className="muted small">{codes.length} códigos · recórtalos y escóndelos</span>
      </div>
      <div className="print-grid">
        {codes.map((c) => (
          <div key={c.id} className="print-card">
            <div className="print-title">🔍 Código secreto <b>#{c.number}</b></div>
            <div className="print-pin">{c.pin}</div>
            <div className="print-help">Escribe este código en la app 🎃 ¡Rápido, antes que los demás!</div>
            {showLabels && c.label && <div className="print-label">📍 {c.label}</div>}
          </div>
        ))}
      </div>
    </div>
  )
}

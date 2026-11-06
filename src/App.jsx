import { HashRouter, Routes, Route } from 'react-router-dom'
import { isConfigured } from './lib/supabase'
import GuestApp from './pages/GuestApp'
import Dashboard from './pages/Dashboard'
import PrintCodes from './pages/PrintCodes'

// HashRouter (#/dashboard) funciona igual en Vercel y en GitHub Pages sin configuración extra.
export default function App() {
  if (!isConfigured) {
    return (
      <div className="screen center">
        <div className="card">
          <h2>⚙️ Falta configurar Supabase</h2>
          <p>Crea el archivo <code>.env</code> (copia <code>.env.example</code>) con
            <code> VITE_SUPABASE_URL</code> y <code>VITE_SUPABASE_ANON_KEY</code>, y reinicia <code>npm run dev</code>.</p>
          <p className="muted">En Vercel o GitHub Pages se configuran como variables de entorno.</p>
        </div>
      </div>
    )
  }

  return (
    <HashRouter>
      <Routes>
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/imprimir-codigos" element={<PrintCodes />} />
        <Route path="/*" element={<GuestApp />} />
      </Routes>
    </HashRouter>
  )
}

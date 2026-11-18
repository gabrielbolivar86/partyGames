import { HashRouter, Routes, Route, Navigate, useParams } from 'react-router-dom'
import { isConfigured, setParty } from './lib/supabase'
import { DEFAULT_PARTY, readLastParty, saveLastParty } from './lib/urls'
import GuestApp from './pages/GuestApp'
import Dashboard from './pages/Dashboard'
import PrintCodes from './pages/PrintCodes'
import HostLogin from './pages/HostLogin'
import Owner from './pages/Owner'

// HashRouter (#/p/<fiesta>/dashboard) funciona igual en Vercel y en GitHub Pages sin configuración extra.
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
        <Route path="/owner" element={<NoParty><Owner /></NoParty>} />
        <Route path="/p/:slug/*" element={<PartyScope />} />
        {/* Enlaces viejos (antes de la fase 10) → la fiesta original */}
        <Route path="/dashboard" element={<Navigate to={`/p/${DEFAULT_PARTY}/dashboard`} replace />} />
        <Route path="/imprimir-codigos" element={<Navigate to={`/p/${DEFAULT_PARTY}/imprimir-codigos`} replace />} />
        <Route path="*" element={<Navigate to={`/p/${readLastParty() || DEFAULT_PARTY}/`} replace />} />
      </Routes>
    </HashRouter>
  )
}

function NoParty({ children }) {
  setParty(null)
  return children
}

// Todo lo que está dentro de /p/<slug>/ habla con el servidor sobre ESA fiesta
function PartyScope() {
  const { slug: raw } = useParams()
  const slug = raw.toLowerCase()
  // Se fija antes de que los hijos pidan datos (sus efectos corren después del render)
  setParty(slug)
  saveLastParty(slug)

  return (
    <Routes key={slug}>
      <Route path="dashboard" element={<Dashboard />} />
      <Route path="imprimir-codigos" element={<PrintCodes />} />
      <Route path="anfitrion" element={<HostLogin />} />
      <Route path="*" element={<GuestApp />} />
    </Routes>
  )
}

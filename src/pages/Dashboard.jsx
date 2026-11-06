import { useEffect, useRef, useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { useLeaderboard } from '../hooks/useLeaderboard'
import { useDashboard } from '../hooks/useDashboard'
import { joinUrl } from '../lib/urls'
import CostumeReveal from '../components/CostumeReveal'
import HuntBoard from '../components/HuntBoard'
import PersonaBoard from '../components/PersonaBoard'
import ImpostorBoard from '../components/ImpostorBoard'
import FinalResults from '../components/FinalResults'

/**
 * Pantalla para la TV/proyector. No necesita login (solo lectura).
 * Cambia de "modo" según lo que active el admin (tabla general, revelación de disfraces…).
 * Añade ?noqr al final de la URL para ocultar el QR: #/dashboard?noqr
 */
export default function Dashboard() {
  const { data } = useDashboard()
  useWakeLock()

  if (data?.mode === 'costume_reveal') {
    return <div className="dash"><CostumeReveal costume={data.costume} /></div>
  }
  if (data?.mode === 'codes') {
    return <div className="dash"><HuntBoard /></div>
  }
  if (data?.mode === 'persona') {
    return <div className="dash"><PersonaBoard /></div>
  }
  if (data?.mode === 'impostor') {
    return <div className="dash"><ImpostorBoard /></div>
  }
  if (data?.mode === 'final') {
    return <div className="dash"><FinalResults /></div>
  }
  return <LeaderboardScreen eventName={data?.event_name} frozen={data?.frozen} />
}

function LeaderboardScreen({ eventName, frozen }) {
  const { rows, loading, error } = useLeaderboard()
  const deltas = useDeltas(rows)
  const showQr = !window.location.hash.includes('noqr')

  const podium = rows.slice(0, 3)
  const rest = rows.slice(3)

  return (
    <div className="dash">
      <header className="dash-head">
        <h1 className="spooky">🎃 Tabla de la noche</h1>
        <div className="dash-meta">{eventName ? `${eventName} · ` : ''}{rows.length} invitados</div>
      </header>

      {frozen && <div className="frozen-banner">🔒 Tabla congelada · los últimos puntos se revelan al final</div>}
      {error && <div className="error">{error}</div>}
      {loading && <div className="center-text muted">Cargando…</div>}

      <div className={`dash-body ${showQr ? '' : 'no-qr'}`}>
        <section className="dash-board">
          <div className="podium">
            {podium.map((r) => (
              <div key={r.player_id} className={`podium-card p${r.rank}`}>
                <div className="medal">{['🥇', '🥈', '🥉'][r.rank - 1] || r.rank}</div>
                <div className="pname">{r.nickname || r.name}</div>
                {r.has_costume && <div className="pcostume">{r.costume}</div>}
                <div className="ppts">{r.points}<small> pts</small></div>
                {deltas[r.player_id] && <Delta value={deltas[r.player_id]} />}
              </div>
            ))}
          </div>

          <ol className="dash-list" start={4}>
            {rest.map((r) => (
              <li key={r.player_id}>
                <span className="pos">{r.rank}</span>
                <span className="who">{r.nickname || r.name}</span>
                <span className="pts">{r.points}</span>
                {deltas[r.player_id] && <Delta value={deltas[r.player_id]} />}
              </li>
            ))}
          </ol>
        </section>

        {showQr && (
          <aside className="dash-qr">
            <div className="qr-box"><QRCodeSVG value={joinUrl()} size={220} bgColor="#ffffff" fgColor="#0d0a14" /></div>
            <h2>¿Acabas de llegar?</h2>
            <p>Escanea y regístrate 👻</p>
          </aside>
        )}
      </div>
    </div>
  )
}

function Delta({ value }) {
  return <span className={`delta-pop ${value > 0 ? 'pos' : 'neg'}`}>{value > 0 ? '+' : ''}{value}</span>
}

// Detecta quién cambió de puntos para mostrar "+5" durante unos segundos
function useDeltas(rows) {
  const prev = useRef(null)
  const timers = useRef({})
  const [deltas, setDeltas] = useState({})

  useEffect(() => {
    const current = Object.fromEntries(rows.map((r) => [r.player_id, r.points]))
    if (prev.current) {
      for (const [id, pts] of Object.entries(current)) {
        const before = prev.current[id]
        if (before === undefined || before === pts) continue
        setDeltas((d) => ({ ...d, [id]: pts - before }))
        clearTimeout(timers.current[id])
        timers.current[id] = setTimeout(() => {
          setDeltas((d) => {
            const copy = { ...d }
            delete copy[id]
            return copy
          })
        }, 4000)
      }
    }
    prev.current = current
  }, [rows])

  useEffect(() => () => Object.values(timers.current).forEach(clearTimeout), [])

  return deltas
}

// Evita que la pantalla se apague (en navegadores que lo soportan)
function useWakeLock() {
  useEffect(() => {
    let lock = null
    const request = async () => {
      try { lock = await navigator.wakeLock?.request('screen') } catch { /* no soportado */ }
    }
    request()
    const onVisible = () => document.visibilityState === 'visible' && request()
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      document.removeEventListener('visibilitychange', onVisible)
      lock?.release?.()
    }
  }, [])
}

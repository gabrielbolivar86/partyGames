import { useEffect, useRef, useState } from 'react'
import { useHuntBoard } from '../hooks/useHunt'

// Pantalla de la caza de códigos: qué códigos se encontraron, últimos hallazgos y top cazadores
export default function HuntBoard() {
  const data = useHuntBoard()
  const flash = useNewFinds(data?.recent)

  if (!data) return <div className="reveal"><p className="muted">Cargando…</p></div>

  const total = data.codes.length
  const foundCodes = data.codes.filter((c) => c.found > 0).length

  return (
    <div className="hunt-screen">
      <header className="dash-head">
        <h1 className="spooky">🔍 Caza de códigos</h1>
        <div className="dash-meta">
          {data.status === 'open' ? `${foundCodes} de ${total} códigos descubiertos` : data.status === 'closed' ? '¡La caza terminó!' : 'Muy pronto…'}
        </div>
      </header>

      <div className="hunt-body">
        <section className="hunt-grid">
          {data.codes.map((c) => (
            <div key={c.number} className={`hunt-tile ${c.found ? 'found' : ''} ${flash.has(c.number) ? 'flash' : ''}`}>
              <div className="hunt-num">#{c.number}</div>
              {c.found
                ? (<><div className="hunt-first">🥇 {c.first}</div><div className="hunt-count">{c.found} {c.found === 1 ? 'lo encontró' : 'lo encontraron'}</div></>)
                : (<><div className="hunt-q">?</div><div className="hunt-count">¡Nadie aún!</div></>)}
            </div>
          ))}
        </section>

        <aside className="hunt-side">
          <h2>⚡ Últimos hallazgos</h2>
          <ul className="hunt-feed">
            {data.recent.length === 0 && <li className="muted">Todavía nadie encontró un código 👀</li>}
            {data.recent.map((r) => (
              <li key={`${r.name}-${r.number}-${r.at}`}>
                <b>{r.name}</b> encontró el <b>#{r.number}</b>
                <span className="feed-pts">+{r.points}</span>
              </li>
            ))}
          </ul>
          {data.hunters.length > 0 && (
            <>
              <h2>🏹 Top cazadores</h2>
              <ol className="hunt-top">
                {data.hunters.map((h, i) => (
                  <li key={h.name}><span>{['🥇', '🥈', '🥉'][i] || `${i + 1}.`} {h.name}</span><b>{h.pts} pts · {h.n} 🔑</b></li>
                ))}
              </ol>
            </>
          )}
        </aside>
      </div>
    </div>
  )
}

// Resalta los códigos recién encontrados durante unos segundos
function useNewFinds(recent) {
  const seen = useRef(null)
  const [flash, setFlash] = useState(new Set())

  useEffect(() => {
    if (!recent) return
    const keys = recent.map((r) => `${r.name}-${r.number}-${r.at}`)
    if (seen.current) {
      const fresh = recent.filter((r) => !seen.current.has(`${r.name}-${r.number}-${r.at}`)).map((r) => r.number)
      if (fresh.length) {
        setFlash(new Set(fresh))
        const t = setTimeout(() => setFlash(new Set()), 3000)
        seen.current = new Set(keys)
        return () => clearTimeout(t)
      }
    }
    seen.current = new Set(keys)
  }, [recent])

  return flash
}

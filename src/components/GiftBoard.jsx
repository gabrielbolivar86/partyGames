import { useEffect, useRef, useState } from 'react'
import { useLiveRpc } from '../hooks/useLiveRpc'

const MEDALS = { 1: '🥇', 2: '🥈', 3: '🥉' }

// Pantalla de El Regalo Loco: progreso de escritura → lectura de frases → votación → podio
export default function GiftBoard() {
  const { data } = useLiveRpc('get_gift_board', ['gift_game'])
  if (!data) return <div className="reveal"><p className="muted">Cargando…</p></div>
  if (data.status === 'none') {
    return <div className="reveal"><h1 className="spooky reveal-title">🎁 El Regalo Loco</h1><p className="reveal-sub">Muy pronto…</p></div>
  }

  if (data.status === 'writing') {
    const pct = data.progress.total ? Math.round((data.progress.done / data.progress.total) * 100) : 0
    return (
      <div className="reveal">
        <h1 className="spooky reveal-title">🎁 El Regalo Loco</h1>
        <p className="reveal-sub">Escriban en su celular: <b>un regalo</b>, <b>para qué sirve</b> y <b>una reacción</b>… ¡a ciegas! 🙈</p>
        <div className="gift-bar"><span style={{ width: `${pct}%` }} /></div>
        <div className="reveal-sub">{pct}% listo · {data.players} participantes</div>
      </div>
    )
  }

  if (data.status === 'reading' && data.current) {
    return (
      <div className="reveal gift-read">
        <div className="persona-round">Regalo {data.current.n} de {data.players}</div>
        <Phrase key={data.current.n} text={data.current.phrase} />
      </div>
    )
  }

  if (data.status === 'voting') {
    return (
      <div className="gift-screen">
        <header className="dash-head">
          <h1 className="spooky">🎁 ¡Voten sus 3 favoritos!</h1>
          <div className="dash-meta">{data.voters_done} ya votaron · en su celular</div>
        </header>
        <ol className="gift-all">
          {data.phrases.map((p) => <li key={p.id}><span className="gift-n">{p.n}</span><span>{p.phrase}</span></li>)}
        </ol>
      </div>
    )
  }

  return <GiftPodium data={data} />
}

function Phrase({ text }) {
  return <blockquote className="gift-phrase">🎁 {text}</blockquote>
}

function GiftPodium({ data }) {
  const step = data.reveal_step
  const [shown, setShown] = useState(step)
  const [count, setCount] = useState(null)
  const prev = useRef(step)

  useEffect(() => {
    const before = prev.current
    prev.current = step
    if (step <= before) { setShown(step); setCount(null); return }
    let n = 3
    setCount(n)
    const t = setInterval(() => {
      n -= 1
      if (n <= 0) { clearInterval(t); setCount(null); setShown(step) } else setCount(n)
    }, 1000)
    return () => clearInterval(t)
  }, [step])

  const visible = (data.podium || []).filter((p) => p.place >= 4 - shown).sort((a, b) => a.place - b.place)

  return (
    <div className="reveal gift-results">
      <h1 className="spooky reveal-title">🎁 Los regalos más locos</h1>
      {visible.length === 0 && !count && <p className="reveal-sub">🥁 Y los ganadores son…</p>}
      <div className="gift-winners">
        {visible.map((p) => (
          <div key={p.place} className={`gift-win p${p.place}`}>
            <div className="gift-win-medal">{MEDALS[p.place]}</div>
            <div className="gift-win-text">{p.phrase}</div>
            <div className="gift-win-authors">✍️ {p.authors.join(' · ')} · {p.votes} votos</div>
          </div>
        ))}
      </div>
      {count !== null && <div className="countdown" key={count}><span>{count}</span></div>}
    </div>
  )
}

import { useEffect, useRef, useState } from 'react'

const MEDALS = { 1: '🥇', 2: '🥈', 3: '🥉' }
const LABEL = { 1: '1.er lugar', 2: '2.º lugar', 3: '3.er lugar' }
const COUNTDOWN_FROM = 3

/**
 * Revelación del mejor disfraz en la TV.
 * Cada vez que el admin avanza un paso, hay una cuenta regresiva 3-2-1 y luego aparece el lugar.
 * Orden visual del podio: 2.º · 1.º · 3.º
 */
export default function CostumeReveal({ costume }) {
  const step = costume.reveal_step
  const [shownStep, setShownStep] = useState(step)
  const [count, setCount] = useState(null)
  const prevStep = useRef(step)

  useEffect(() => {
    const prev = prevStep.current
    prevStep.current = step
    if (step <= prev) { setShownStep(step); setCount(null); return }

    // Avanzó: cuenta regresiva y luego mostrar
    let n = COUNTDOWN_FROM
    setCount(n)
    const t = setInterval(() => {
      n -= 1
      if (n <= 0) {
        clearInterval(t)
        setCount(null)
        setShownStep(step)
      } else setCount(n)
    }, 1000)
    return () => clearInterval(t)
  }, [step])

  const byPlace = Object.fromEntries((costume.podium || []).map((p) => [p.place, p]))
  const isShown = (place) => place >= 4 - shownStep && byPlace[place]
  const winnerShown = shownStep === 3 && byPlace[1]

  if (costume.status !== 'closed') {
    return (
      <div className="reveal">
        <h1 className="spooky reveal-title">🎭 Mejor disfraz</h1>
        <p className="reveal-sub">La votación sigue abierta… ¡vota desde tu celular! 👻</p>
      </div>
    )
  }

  const nextPlace = 3 - shownStep // lugar que se revelará a continuación

  return (
    <div className="reveal">
      <h1 className="spooky reveal-title">🎭 Mejor disfraz</h1>
      <p className="reveal-sub">
        {winnerShown ? '¡Felicidades a los ganadores! 🎉' : `${costume.candidates} disfrazados compitieron esta noche`}
      </p>

      <div className="reveal-podium">
        {[2, 1, 3].map((place) => (
          <div key={place} className={`reveal-slot s${place} ${isShown(place) ? 'shown' : ''} ${count && place === nextPlace ? 'next' : ''}`}>
            {isShown(place) ? (
              <div className="reveal-card">
                <div className="reveal-medal">{MEDALS[place]}</div>
                <div className="reveal-name">{byPlace[place].nickname || byPlace[place].name}</div>
                <div className="reveal-costume">{byPlace[place].costume}</div>
              </div>
            ) : (
              <div className="reveal-card hidden">
                <div className="reveal-q">?</div>
                <div className="reveal-place">{LABEL[place]}</div>
              </div>
            )}
            <div className="reveal-base">{place}</div>
          </div>
        ))}
      </div>

      {count !== null && (
        <div className="countdown" key={count}>
          <span>{count}</span>
        </div>
      )}

      {winnerShown && <Confetti />}
    </div>
  )
}

function Confetti() {
  const items = Array.from({ length: 40 }, (_, i) => i)
  const emojis = ['🎃', '🦇', '👻', '🍬', '✨', '🕸️']
  return (
    <div className="confetti" aria-hidden="true">
      {items.map((i) => (
        <span key={i} style={{
          left: `${(i * 37) % 100}%`,
          animationDelay: `${(i % 10) * 0.35}s`,
          animationDuration: `${4 + (i % 5)}s`,
          fontSize: `${1.5 + (i % 4) * 0.6}rem`,
        }}>{emojis[i % emojis.length]}</span>
      ))}
    </div>
  )
}

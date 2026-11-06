import { useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useHunt } from '../hooks/useHunt'

/**
 * Caza de códigos (vista del invitado).
 * Hay códigos de 6 caracteres escondidos (ej. K7PX3M). Al encontrar uno, se escribe aquí.
 * Mientras antes lo encuentres (antes que los demás), más puntos.
 */
export default function CodeHunt() {
  const { data, error, refresh } = useHunt()
  const [pin, setPin] = useState('')
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState(null) // {ok, text}

  async function claim(code) {
    const clean = normalize(code)
    if (clean.length !== 6) { setResult({ ok: false, text: 'El código tiene 6 caracteres' }); return }
    setBusy(true)
    setResult(null)
    const { data: res, error } = await supabase.rpc('claim_code', { p_pin: clean })
    setBusy(false)
    if (error) { setResult({ ok: false, text: errorMessage(error) }); return }
    if (!res.ok) { setResult({ ok: false, text: res.error }); return }
    setPin('')
    setResult({
      ok: true,
      text: `¡Código #${res.number}! Fuiste el ${res.position}.º en encontrarlo`,
      points: res.points,
    })
    refresh()
  }

  if (error) return <section className="card"><div className="error">{error}</div></section>
  if (!data) return null

  if (data.status === 'not_started') {
    return (
      <section className="card soon">
        <h3>🔍 Caza de códigos</h3>
        <p className="muted">Pronto habrá códigos secretos escondidos por la casa…</p>
        {result && <div className={result.ok ? 'success' : 'error'}>{result.text}</div>}
      </section>
    )
  }

  const found = data.mine.length
  const limitReached = data.max > 0 && found >= data.max
  const total = data.mine.reduce((s, m) => s + m.points, 0)

  return (
    <section className="card hunt">
      <div className="costume-head">
        <h3>🔍 Caza de códigos</h3>
        <span className="save-badge">{data.max > 0 ? `${found}/${data.max}` : found} códigos</span>
      </div>

      {data.status === 'open' && !limitReached && (
        <>
          <p className="hint">Encuentra los códigos escondidos. ¡Los primeros ganan más!</p>
          <form className="pin-row" onSubmit={(e) => { e.preventDefault(); claim(pin) }}>
            <input
              className="pin-input" autoCapitalize="characters" autoCorrect="off" spellCheck={false} autoComplete="off"
              value={pin} onChange={(e) => setPin(normalize(e.target.value).slice(0, 6))}
              placeholder="ABC123" aria-label="Código de 6 caracteres"
            />
            <button className="btn primary" disabled={busy || pin.length !== 6}>{busy ? '…' : 'Registrar'}</button>
          </form>
        </>
      )}
      {data.status === 'open' && limitReached && (
        <p className="hint">¡Llegaste al máximo de {data.max} códigos! 🎉</p>
      )}
      {data.status === 'closed' && <p className="hint">La caza de códigos terminó.</p>}

      {result && (
        <div className={`hunt-result ${result.ok ? 'ok' : 'err'}`}>
          {result.ok && <div className="hunt-pts">+{result.points}</div>}
          <div>{result.text}</div>
        </div>
      )}

      {found > 0 && (
        <ul className="hunt-mine">
          {data.mine.map((m) => (
            <li key={m.number}>
              <span>🔑 Código #{m.number}</span>
              <span className="muted small">{m.position}.º</span>
              <b>+{m.points}</b>
            </li>
          ))}
          <li className="total"><span>Total</span><span /><b>{total} pts</b></li>
        </ul>
      )}
    </section>
  )
}

// Mayúsculas y solo letras/números (acepta "k7p-x3m" → "K7PX3M")
function normalize(v) {
  return String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLiveRpc } from '../hooks/useLiveRpc'
import { useCountdown } from '../hooks/usePersona'

const MEDALS = { 1: '🥇', 2: '🥈', 3: '🥉' }

/**
 * El Regalo (vista del invitado). Aparece solo cuando hay una ronda.
 * Escritura: 3 partes a ciegas (objeto para alguien, un uso, una reacción).
 * Votación: hasta 3 frases favoritas (no las propias).
 */
export default function GiftGame() {
  const { data, refresh } = useLiveRpc('get_gift_status', ['gift_game'])
  if (!data || data.status === 'none') return null

  return (
    <section className="card gift live-gift">
      <h3>🎁 El Regalo</h3>
      {data.status === 'writing' && (data.tasks?.length
        ? <Writing data={data} onSaved={refresh} />
        : <><GiftTimer data={data} onExpire={refresh} /><p className="hint">{data.participant ? '✅ ¡Listo! Espera a los demás.' : '👀 Esta ronda no juegas. ¡Mira la pantalla!'}</p></>)}
      {data.status === 'reading' && <p className="hint">📺 ¡Mira la pantalla! Luego votas tus 3 favoritos.</p>}
      {data.status === 'voting' && <Voting data={data} onVoted={refresh} />}
      {data.status === 'results' && (
        data.podium?.length
          ? <ol className="gift-podium-mini">{data.podium.map((p) => <li key={p.place}><b>{MEDALS[p.place]}</b> {p.phrase}</li>)}</ol>
          : <p className="hint">🥁 ¡Resultados en la pantalla!</p>
      )}
    </section>
  )
}

const PART_INFO = {
  object: { emoji: '🎁', placeholder: 'ej. un pato de hule gigante' },
  use: { emoji: '🔧', placeholder: 'ej. espantar a los vecinos' },
  reaction: { emoji: '😲', placeholder: 'ej. ¡Justo lo que necesitaba!' },
}

const taskKey = (t) => `${t.chain}-${t.part}`

// Escritura paso a paso: una pregunta a la vez, cada una con su tiempo.
// La 1.ª cierra a los N s, la 2.ª a los 2N y la 3.ª a los 3N (N = segundos por pregunta), igual para todos.
function Writing({ data, onSaved }) {
  const tasks = data.tasks || []
  const [passed, setPassed] = useState(() => new Set())
  const idx = tasks.findIndex((t) => !t.text && !passed.has(taskKey(t)))
  const pass = (t) => setPassed((s) => new Set(s).add(taskKey(t)))

  if (idx === -1) {
    return (
      <>
        <GiftTimer data={data} onExpire={onSaved} hidden />
        <div className="success">✅ ¡Listo! Espera a los demás.</div>
      </>
    )
  }
  const sec = data.seconds || 0
  const deadline = data.ends_at && sec > 0
    ? new Date(new Date(data.ends_at).getTime() - Math.max(0, 2 - idx) * sec * 1000).toISOString()
    : null
  return (
    <>
      <GiftTimer data={data} onExpire={onSaved} hidden />
      <GiftStep key={taskKey(tasks[idx])} task={tasks[idx]} n={idx + 1} total={tasks.length}
        deadline={deadline} now={data.now} onDone={() => { pass(tasks[idx]); onSaved() }} />
    </>
  )
}

function GiftStep({ task, n, total, deadline, now, onDone }) {
  const info = PART_INFO[task.part]
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)
  const offset = useMemo(() => (now ? new Date(now).getTime() - Date.now() : 0), [now]) // eslint-disable-line
  const left = useCountdown(deadline, offset)
  const textRef = useRef(text)
  textRef.current = text
  const doneRef = useRef(false)

  async function next() {
    if (doneRef.current) return
    doneRef.current = true
    setBusy(true)
    const t = textRef.current.trim()
    if (t) {
      const { data, error } = await supabase.rpc('save_gift_text', { p_chain: task.chain, p_part: task.part, p_text: t })
      if ((error || !data?.ok) && !deadline) {
        setMsg(error ? errorMessage(error) : data.error); setBusy(false); doneRef.current = false; return
      }
    }
    onDone()
  }

  // Se acabó el tiempo de esta pregunta: se guarda lo escrito y pasa a la siguiente
  useEffect(() => { if (deadline && left === 0) next() }, [left, deadline]) // eslint-disable-line

  const question = task.part === 'object'
    ? <>¿Qué le vas a regalar a <b>{task.recipient}</b>?</>
    : task.part === 'use'
      ? <>Un regalo misterioso… <b>¿para qué sirve?</b></>
      : <>Alguien recibe un regalo… <b>¿qué exclama?</b></>

  return (
    <form className="gift-step" onSubmit={(e) => { e.preventDefault(); next() }}>
      <div className="gift-step-head">
        <span className="small muted">Pregunta {n} de {total}</span>
        {deadline && <span className={`timer-pill ${left <= 5 ? 'hot' : ''}`}>{left}s</span>}
      </div>
      <div className="gift-step-dots">{Array.from({ length: total }, (_, i) => <i key={i} className={i < n ? 'on' : ''} />)}</div>
      <div className="gift-q">{info.emoji} {question}</div>
      <input autoFocus value={text} maxLength={80} placeholder={info.placeholder} onChange={(e) => setText(e.target.value)} />
      {msg && <div className="error">{msg}</div>}
      <button className="btn primary big-btn" disabled={busy || !text.trim()}>{n === total ? 'Listo ✓' : 'Siguiente →'}</button>
    </form>
  )
}

// Cuenta regresiva de la escritura. Al llegar a 0, cualquier pantalla le avisa al servidor (gift_tick),
// que solo cierra si de verdad se acabó el tiempo.
export function GiftTimer({ data, onExpire, big = false, hidden = false }) {
  const offset = useMemo(() => (data.now ? new Date(data.now).getTime() - Date.now() : 0), [data.now])
  const left = useCountdown(data.ends_at, offset)
  const expired = !!data.ends_at && left === 0
  const cb = useRef(onExpire)
  cb.current = onExpire
  useEffect(() => {
    if (!expired) return
    const tick = () => supabase.rpc('gift_tick').then(() => cb.current?.())
    const t1 = setTimeout(tick, 2500 + Math.random() * 1500)
    const t2 = setInterval(tick, 5000)
    return () => { clearTimeout(t1); clearInterval(t2) }
  }, [expired])
  if (!data.ends_at || hidden) return null
  return (
    <div className={`gift-timer ${left <= 10 ? 'hurry' : ''} ${big ? 'big' : ''}`}>
      {expired ? '⏰ ¡Tiempo!' : `⏱ ${left >= 60 ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}` : `${left} s`}`}
    </div>
  )
}

function Voting({ data, onVoted }) {
  const [sel, setSel] = useState(() => new Set(data.my_votes || []))
  const [state, setState] = useState(null)

  async function toggle(id) {
    const next = new Set(sel)
    if (next.has(id)) next.delete(id)
    else if (next.size >= 3) { setState('Máximo 3: quita una para elegir otra'); return }
    else next.add(id)
    setSel(next)
    setState('Guardando…')
    const { data: res, error } = await supabase.rpc('vote_gift', { p_chains: [...next] })
    setState(error || !res.ok ? (error ? errorMessage(error) : res.error) : `Guardado ✓ (${next.size}/3)`)
    onVoted()
  }

  return (
    <>
      <p className="hint">Elige tus <b>3 favoritos</b>.</p>
      {state && <p className="small muted">{state}</p>}
      <ul className="gift-vote">
        {data.phrases.map((p) => (
          <li key={p.id}>
            <button type="button" disabled={p.mine} className={`gift-opt ${sel.has(p.id) ? 'active' : ''}`} onClick={() => toggle(p.id)}>
              <span className="gift-n">{p.n}</span>
              <span className="grow">{p.phrase}{p.mine && <span className="tag used"> participaste</span>}</span>
              <span className="gift-check">{sel.has(p.id) ? '★' : '☆'}</span>
            </button>
          </li>
        ))}
      </ul>
    </>
  )
}

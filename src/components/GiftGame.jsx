import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLiveRpc } from '../hooks/useLiveRpc'
import { useCountdown } from '../hooks/usePersona'

const MEDALS = { 1: '🥇', 2: '🥈', 3: '🥉' }

/**
 * El Regalo Loco (vista del invitado). Aparece solo cuando hay una ronda.
 * Escritura: 3 partes a ciegas (objeto para alguien, un uso, una reacción).
 * Votación: hasta 3 frases favoritas (no las propias).
 */
export default function GiftGame() {
  const { data, refresh } = useLiveRpc('get_gift_status', ['gift_game'])
  if (!data || data.status === 'none') return null

  return (
    <section className="card gift live-gift">
      <h3>🎁 El Regalo Loco</h3>
      {data.status === 'writing' && (data.tasks?.length
        ? <Writing data={data} onSaved={refresh} />
        : <><GiftTimer data={data} onExpire={refresh} /><p className="hint">{data.participant ? '✅ ¡Listo! Espera a los demás.' : '👀 Esta ronda no juegas. ¡Mira la pantalla!'}</p></>)}
      {data.status === 'reading' && <p className="hint">📺 ¡Mira la pantalla! Luego votas tus 3 favoritos.</p>}
      {data.status === 'voting' && <Voting data={data} onVoted={refresh} />}
      {data.status === 'results' && (
        data.podium?.length
          ? <ol className="gift-podium-mini">{data.podium.map((p) => <li key={p.place}><b>{MEDALS[p.place]}</b> {p.phrase}</li>)}</ol>
          : <p className="hint">🥁 Votación cerrada. ¡Los ganadores se revelan en la pantalla!</p>
      )}
    </section>
  )
}

const PART_INFO = {
  object: { emoji: '🎁', placeholder: 'ej. un pato de hule gigante' },
  use: { emoji: '🔧', placeholder: 'ej. espantar a los vecinos', prefix: 'sirve para…' },
  reaction: { emoji: '😲', placeholder: 'ej. ¡Justo lo que necesitaba!' },
}

function Writing({ data, onSaved }) {
  const tasks = data.tasks || []
  const done = tasks.filter((t) => t.text).length
  return (
    <>
      <GiftTimer data={data} onExpire={onSaved} />
      <p className="hint">⚡ ¡Rápido! Nadie ve lo que escriben los demás. Se guarda solo.</p>
      <div className="gift-progress"><span style={{ width: `${tasks.length ? (done / tasks.length) * 100 : 0}%` }} /></div>
      <p className="small muted">{done}/{tasks.length} listas</p>
      {tasks.map((t, i) => {
        const info = PART_INFO[t.part]
        const label = t.part === 'object'
          ? <>{i + 1}. {info.emoji} ¿Qué le regalas a <b>{t.recipient}</b>?</>
          : t.part === 'use'
            ? <>{i + 1}. {info.emoji} Un regalo misterioso… <b>¿para qué sirve?</b></>
            : <>{i + 1}. {info.emoji} Alguien recibe un regalo… <b>¿qué exclama?</b></>
        return <GiftField key={`${t.chain}-${t.part}`} chain={t.chain} part={t.part} saved={t.text} onSaved={onSaved}
          label={label} placeholder={info.placeholder} prefix={info.prefix} />
      })}
    </>
  )
}

// Cuenta regresiva de la escritura. Al llegar a 0, cualquier pantalla le avisa al servidor (gift_tick),
// que solo cierra si de verdad se acabó el tiempo.
export function GiftTimer({ data, onExpire, big = false }) {
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
  if (!data.ends_at) return null
  return (
    <div className={`gift-timer ${left <= 10 ? 'hurry' : ''} ${big ? 'big' : ''}`}>
      {expired ? '⏰ ¡Tiempo!' : `⏱ ${left >= 60 ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}` : `${left} s`}`}
    </div>
  )
}

function GiftField({ chain, part, saved, label, placeholder, prefix, onSaved }) {
  const [text, setText] = useState(saved || '')
  const [state, setState] = useState(saved ? 'saved' : 'idle')
  const [msg, setMsg] = useState(null)
  useEffect(() => { if (saved && state !== 'dirty') setText(saved) }, [saved]) // eslint-disable-line

  async function save() {
    if (!text.trim()) return
    setState('saving')
    const { data, error } = await supabase.rpc('save_gift_text', { p_chain: chain, p_part: part, p_text: text })
    if (error || !data.ok) { setMsg(error ? errorMessage(error) : data.error); setState('dirty') }
    else { setMsg(null); setState((st) => (st === 'saving' ? 'saved' : st)); onSaved() }
  }

  // Guardado automático un momento después de dejar de escribir (con 30 s no hay tiempo para botones)
  useEffect(() => {
    if (state !== 'dirty' || !text.trim()) return
    const t = setTimeout(save, 700)
    return () => clearTimeout(t)
  }, [text, state]) // eslint-disable-line

  return (
    <div className="gift-field">
      <label>{label}</label>
      {prefix && <span className="small muted">{prefix}</span>}
      <div className="row nowrap">
        <input value={text} maxLength={80} placeholder={placeholder}
          onChange={(e) => { setText(e.target.value); setState('dirty') }}
          onBlur={() => state === 'dirty' && save()}
          onKeyDown={(e) => e.key === 'Enter' && text.trim() && save()} />
        <span className={`gift-saved ${state}`}>{state === 'saved' ? '✓' : state === 'saving' ? '…' : ''}</span>
      </div>
      {msg && <div className="error">{msg}</div>}
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

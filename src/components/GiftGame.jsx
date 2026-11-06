import { useEffect, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLiveRpc } from '../hooks/useLiveRpc'

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
      {data.status === 'writing' && (data.participant ? <Writing data={data} onSaved={refresh} /> : <p className="hint">👀 No juegas esta ronda. ¡Mira la pantalla!</p>)}
      {data.status === 'reading' && <p className="hint">📺 ¡Mira la pantalla! Se están leyendo los regalos… luego votarás tus 3 favoritos.</p>}
      {data.status === 'voting' && <Voting data={data} onVoted={refresh} />}
      {data.status === 'results' && (
        data.podium?.length
          ? <ol className="gift-podium-mini">{data.podium.map((p) => <li key={p.place}><b>{MEDALS[p.place]}</b> {p.phrase}</li>)}</ol>
          : <p className="hint">🥁 Votación cerrada. ¡Los ganadores se revelan en la pantalla!</p>
      )}
    </section>
  )
}

function Writing({ data, onSaved }) {
  const done = [data.my_object, data.my_use, data.my_reaction].filter(Boolean).length
  return (
    <>
      <p className="hint">Escribe las 3 partes. Cada una va a un regalo distinto y <b>nadie ve lo que escribieron los demás</b>: la gracia es que la frase final salga absurda. 🤪</p>
      <div className="gift-progress"><span style={{ width: `${(done / 3) * 100}%` }} /></div>
      <p className="small muted">{done}/3 listas</p>
      <GiftField part="object" saved={data.my_object} onSaved={onSaved}
        label={<>1️⃣ ¿Qué le regalas a <b>{data.recipient}</b>?</>}
        placeholder="ej. un pato de hule gigante" />
      <GiftField part="use" saved={data.my_use} onSaved={onSaved}
        label={<>2️⃣ Un regalo misterioso… <b>¿para qué sirve?</b></>}
        placeholder="ej. espantar a los vecinos" prefix="sirve para…" />
      <GiftField part="reaction" saved={data.my_reaction} onSaved={onSaved}
        label={<>3️⃣ Alguien recibe un regalo… <b>¿qué exclama?</b></>}
        placeholder="ej. ¡Justo lo que necesitaba!" />
    </>
  )
}

function GiftField({ part, saved, label, placeholder, prefix, onSaved }) {
  const [text, setText] = useState(saved || '')
  const [state, setState] = useState(saved ? 'saved' : 'idle')
  const [msg, setMsg] = useState(null)
  useEffect(() => { if (saved && state !== 'dirty') setText(saved) }, [saved]) // eslint-disable-line

  async function save() {
    setState('saving')
    const { data, error } = await supabase.rpc('save_gift_part', { p_part: part, p_text: text })
    if (error || !data.ok) { setMsg(error ? errorMessage(error) : data.error); setState('dirty') }
    else { setMsg(null); setState('saved'); onSaved() }
  }

  return (
    <div className="gift-field">
      <label>{label}</label>
      {prefix && <span className="small muted">{prefix}</span>}
      <div className="row nowrap">
        <input value={text} maxLength={80} placeholder={placeholder}
          onChange={(e) => { setText(e.target.value); setState('dirty') }}
          onKeyDown={(e) => e.key === 'Enter' && text.trim() && save()} />
        <button className={`btn small ${state === 'saved' ? 'ok' : ''}`} disabled={!text.trim() || state === 'saving' || state === 'saved'} onClick={save}>
          {state === 'saved' ? '✓' : state === 'saving' ? '…' : 'Guardar'}
        </button>
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
      <p className="hint">Elige tus <b>3 regalos más graciosos</b>. Los tuyos no se pueden votar.</p>
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

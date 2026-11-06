import { useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useLiveRpc } from '../hooks/useLiveRpc'
import { KIND_LABEL } from '../lib/impostor'

/**
 * El Impostor (vista del invitado). Aparece solo cuando hay una ronda.
 * - Carta secreta: se ve MANTENIENDO PRESIONADO (así nadie la ve por encima del hombro).
 * - Votación desde el celular cuando el admin la abre.
 * - Los impostores tienen 1 intento para adivinar la palabra.
 */
export default function ImpostorGame({ myId }) {
  const { data: raw, refresh } = useLiveRpc('get_impostor_status', ['impostor_game', 'impostor_votes'])
  if (!raw || raw.status === 'none') return null
  const data = { ...raw, me_away: !!raw.players?.find((p) => p.id === myId)?.away }

  const finished = data.status === 'finished'

  return (
    <section className="card impostor live-imp">
      <div className="costume-head">
        <h3>🕵️ El Impostor <span className="muted small">#{data.number}</span></h3>
        <span className="save-badge">{data.impostor_count} {data.impostor_count === 1 ? 'impostor' : 'impostores'}</span>
      </div>

      {!data.participant && !finished && <p className="hint">👀 Esta ronda no juegas. ¡Mira la pantalla!</p>}

      {data.participant && !finished && data.me_away && <p className="away-note">⏸️ Estás en pausa. Tu carta se guarda.</p>}
      {data.participant && !finished && <SecretCard data={data} />}
      {data.participant && !finished && !data.alive && <p className="hint">☠️ Fuiste eliminado. Ya no votas{data.role === 'impostor' ? ', pero aún puedes adivinar la palabra.' : '.'}</p>}

      {data.last_result && !finished && <LastResult r={data.last_result} />}

      {data.participant && data.alive && !data.me_away && data.vote.status === 'open' && !finished && (
        <VoteBox data={data} myId={myId} onVoted={refresh} />
      )}

      {data.can_guess && <GuessBox onDone={refresh} />}
      {data.role === 'impostor' && data.my_guess && !finished && <p className="hint">Tu intento: “{data.my_guess}” ❌</p>}

      {finished && (
        <div className={`imp-final ${data.winner}`}>
          <div className="imp-winner">{data.winner === 'crew' ? '🛡 ¡Ganó la tripulación!' : '🕵️ ¡Ganaron los impostores!'}</div>
          <div className="small">{data.win_reason}</div>
          <div>La palabra era <b>{data.word}</b></div>
          {data.participant && (
            <div className="small">
              {data.role === 'impostor' ? 'Eras impostor' : 'Eras tripulante'}
              {((data.winner === 'crew' && data.role === 'crew') || (data.winner === 'impostors' && data.role === 'impostor')) ? ' · ¡ganaste! 🎉' : ''}
            </div>
          )}
        </div>
      )}
    </section>
  )
}

function SecretCard({ data }) {
  const [show, setShow] = useState(false)
  const on = () => setShow(true)
  const off = () => setShow(false)
  const isImp = data.role === 'impostor'
  return (
    <div
      className={`secret-card ${show ? 'open' : ''} ${show && isImp ? 'imp' : ''}`}
      onPointerDown={on} onPointerUp={off} onPointerLeave={off} onPointerCancel={off}
      onContextMenu={(e) => e.preventDefault()}
    >
      {show ? (
        isImp ? (
          <>
            <div className="secret-role">🤫 ERES IMPOSTOR</div>
            <div className="secret-sub">Pista: <b>{data.hint}</b></div>
            <div className="small">Disimula y descubre la palabra</div>
          </>
        ) : (
          <>
            <div className="small">Tu palabra es</div>
            <div className="secret-word">{data.word}</div>
            <div className="small">Di algo relacionado sin hacerlo obvio</div>
          </>
        )
      ) : (
        <>
          <div className="secret-q">🂠</div>
          <div><b>Mantén presionado</b> para ver tu carta</div>
          <div className="small muted">Suelta para ocultarla</div>
        </>
      )}
    </div>
  )
}

function VoteBox({ data, myId, onVoted }) {
  const [msg, setMsg] = useState(null)
  const [pending, setPending] = useState(null)
  const myVote = pending ?? data.vote.my_vote
  const options = data.players.filter((p) => p.alive && !p.away && p.id !== myId)

  async function vote(id) {
    setPending(id)
    setMsg(null)
    const { data: res, error } = await supabase.rpc('vote_impostor', { p_target: id })
    if (error || !res.ok) { setMsg(error ? errorMessage(error) : res.error); setPending(null) }
    else onVoted()
  }

  return (
    <div className="imp-vote">
      <div className={`kind-badge ${data.vote.kind}`}>{KIND_LABEL[data.vote.kind].long}</div>
      <p className="hint">¿Quién es el impostor?</p>
      <div className="vote-grid">
        {options.map((p) => (
          <button key={p.id} type="button" className={`vote-btn ${myVote === p.id ? 'active' : ''}`} onClick={() => vote(p.id)}>
            {p.name}
          </button>
        ))}
      </div>
      {msg && <div className="error">{msg}</div>}
    </div>
  )
}

function GuessBox({ onDone }) {
  const [text, setText] = useState('')
  const [msg, setMsg] = useState(null)
  const [busy, setBusy] = useState(false)

  async function send() {
    if (!window.confirm(`¿Seguro? Solo tienes UN intento: “${text}”`)) return
    setBusy(true)
    const { data, error } = await supabase.rpc('guess_impostor_word', { p_guess: text })
    setBusy(false)
    if (error || !data.ok) setMsg(error ? errorMessage(error) : data.error)
    else { setMsg(data.correct ? '¡Correcto! 🎉' : 'No era esa 😬'); onDone() }
  }

  return (
    <div className="imp-guess">
      <div className="small"><b>🎯 ¿Sabes la palabra?</b> Si aciertas, ganan los impostores. Solo 1 intento.</div>
      <div className="row nowrap">
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="La palabra es…" maxLength={60} />
        <button className="btn small" disabled={busy || !text.trim()} onClick={send}>Adivinar</button>
      </div>
      {msg && <div className="hint">{msg}</div>}
    </div>
  )
}

export function LastResult({ r, big = false }) {
  let text
  let cls = ''
  if (r.type === 'eliminated') {
    text = <>☠️ <b>{r.name}</b> fue eliminado con {r.votes} votos… {r.was_impostor ? <b>¡ERA IMPOSTOR! 🎯</b> : <b>era inocente 😬</b>}</>
    cls = r.was_impostor ? 'good' : 'bad'
  } else if (r.type === 'tie') {
    text = <>⚖️ Empate en la votación: nadie sale.</>
  } else if (r.type === 'none') {
    text = <>Nadie votó: nadie sale.</>
  } else if (r.type === 'defense') {
    text = r.top ? <>🗣 Votación de defensa: el más votado fue <b>{r.top}</b> ({r.votes}){r.tie ? ' (empate)' : ''}. ¡Que se defienda!</> : <>🗣 Votación de defensa sin votos.</>
  } else if (r.type === 'guess') {
    text = <>🎯 <b>{r.name}</b> adivinó la palabra: “{r.guess}”</>
    cls = 'bad'
  }
  return <div className={`imp-result ${cls} ${big ? 'big' : ''}`}>{text}</div>
}

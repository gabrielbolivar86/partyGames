import { useMemo, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { usePersonaRpc, useCountdown } from '../hooks/usePersona'
import FactTips from './FactTips'

/**
 * ¿Quién es el personaje? (vista del invitado)
 * Aparece arriba solo cuando hay una ronda en curso o recién revelada.
 */
export default function PersonaGame() {
  const { data, refresh, offset } = usePersonaRpc('get_persona_status')
  const round = data?.round
  if (!round) return null

  return round.status === 'revealed'
    ? <Revealed round={round} settings={data.settings} />
    : <Voting key={round.id} round={round} candidates={data.candidates} offset={offset} onVoted={refresh} />
}

function Voting({ round, candidates, offset, onVoted }) {
  const left = useCountdown(round.ends_at, offset)
  const [query, setQuery] = useState('')
  const [pending, setPending] = useState(null)
  const [msg, setMsg] = useState(null)
  const myVote = pending ?? round.my_vote
  const timeUp = left === 0

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? candidates.filter((c) => `${c.name} ${c.nickname || ''}`.toLowerCase().includes(q)) : candidates
  }, [candidates, query])
  const voted = candidates.find((c) => c.id === myVote)

  async function vote(id) {
    setPending(id)
    setMsg(null)
    const { data, error } = await supabase.rpc('vote_persona', { p_guess: id })
    if (error || !data.ok) { setMsg(error ? errorMessage(error) : data.error); setPending(null) }
    else onVoted()
  }

  return (
    <section className="card persona live">
      <div className="costume-head">
        <h3>🕵️ ¿Quién es el personaje? <span className="muted small">#{round.number}</span></h3>
        <span className={`timer-pill ${left <= 5 ? 'hot' : ''}`}>{timeUp ? '⏰' : `${left}s`}</span>
      </div>
      <blockquote className="persona-fact">“{round.fact}”</blockquote>

      {round.is_owner ? (
        <div className="owner-box">🤫 <b>¡Es tu dato!</b> Pon cara de póker… ganas puntos por cada persona que no te descubra.</div>
      ) : timeUp ? (
        <p className="hint">¡Tiempo! {voted ? <>Votaste por <b>{voted.nickname || voted.name}</b>.</> : 'No alcanzaste a votar.'} Mira la pantalla 👀</p>
      ) : (
        <>
          <p className="hint">{voted ? <>Tu voto: <b>{voted.nickname || voted.name}</b> ✓ (puedes cambiarlo)</> : '¿De quién crees que es? Toca un nombre.'}</p>
          {candidates.length > 8 && <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar…" />}
          <div className="vote-grid">
            {filtered.map((c) => (
              <button key={c.id} type="button" className={`vote-btn ${myVote === c.id ? 'active' : ''}`} onClick={() => vote(c.id)}>
                {c.nickname || c.name}
              </button>
            ))}
          </div>
        </>
      )}
      {msg && <div className="error">{msg}</div>}
    </section>
  )
}

function Revealed({ round, settings }) {
  const r = round.result
  const owner = r.owner

  return (
    <section className="card persona">
      <h3>🕵️ Ronda #{round.number}: ¡era…!</h3>
      <blockquote className="persona-fact small-fact">“{round.fact}”</blockquote>
      <div className="persona-answer">{owner.nickname || owner.name}{owner.costume && <span className="muted small"> · {owner.costume}</span>}</div>
      {round.is_owner ? (
        <div className="hunt-result ok">
          <div className="hunt-pts">+{r.owner_points}</div>
          <div>{r.caught ? 'Te atraparon 😅 pero ganas puntos por participar' : '¡No te atraparon! Puntos x2 😎'}</div>
        </div>
      ) : round.my_correct ? (
        <div className="hunt-result ok"><div className="hunt-pts">+{settings.correct}</div><div>¡Adivinaste! 🎉</div></div>
      ) : round.my_vote ? (
        <div className="hunt-result err"><div>No era quien pensabas 😅</div></div>
      ) : (
        <p className="hint">No votaste en esta ronda.</p>
      )}
      <p className="small muted">{r.correct} de {r.total} acertaron</p>
    </section>
  )
}

// Tarjeta "Mis datos curiosos": varios por persona, con ideas y explicación clara
const MAX_FACTS = 2

export function MyFactCard() {
  const { data, refresh } = usePersonaRpc('get_persona_status')
  const [editing, setEditing] = useState(null) // null | 'new' | id del dato
  const [text, setText] = useState('')
  const [msg, setMsg] = useState(null)
  const [busy, setBusy] = useState(false)
  if (!data) return null

  const facts = data.my_facts || []
  const canAdd = facts.length < MAX_FACTS

  function open(fact) {
    setEditing(fact ? fact.id : 'new')
    setText(fact ? fact.text : '')
    setMsg(null)
  }

  async function save() {
    setBusy(true)
    const { error } = editing === 'new'
      ? await supabase.rpc('add_my_fact', { p_text: text })
      : await supabase.rpc('update_my_fact', { p_fact_id: editing, p_text: text })
    setBusy(false)
    if (error) setMsg(errorMessage(error))
    else { setEditing(null); refresh() }
  }

  async function remove(fact) {
    if (!window.confirm('¿Borrar este dato?')) return
    const { error } = await supabase.rpc('delete_my_fact', { p_fact_id: fact.id })
    if (error) setMsg(errorMessage(error))
    refresh()
  }

  return (
    <section className="card form soon">
      <h3>🤫 Mis datos curiosos <span className="muted small">{facts.length}/{MAX_FACTS}</span></h3>

      {facts.length === 0 && editing === null && (
        <p className="muted">Aún no tienes datos para el juego <i>¿Quién es el personaje?</i></p>
      )}

      {facts.length > 0 && (
        <ul className="my-facts">
          {facts.map((f) => (
            <li key={f.id}>
              {editing === f.id ? null : (
                <>
                  <span className="grow">“{f.text}”{f.used && <span className="tag used">ya salió</span>}</span>
                  {!f.used && (
                    <span className="row nowrap">
                      <button className="btn small ghost-btn" onClick={() => open(f)}>✏️</button>
                      <button className="btn small ghost-btn" onClick={() => remove(f)}>🗑</button>
                    </span>
                  )}
                </>
              )}
            </li>
          ))}
        </ul>
      )}

      {editing !== null ? (
        <>
          <textarea rows={3} maxLength={200} value={text} onChange={(e) => setText(e.target.value)}
            placeholder="Escribe tu dato aquí…" autoFocus />
          <FactTips />
          {msg && <div className="error">{msg}</div>}
          <div className="row">
            <button className="btn small ok" onClick={save} disabled={busy || !text.trim()}>Guardar</button>
            <button className="btn small ghost-btn" onClick={() => setEditing(null)}>Cancelar</button>
          </div>
        </>
      ) : (
        <>
          {msg && <div className="error">{msg}</div>}
          {canAdd && (
            <button className="btn add-fact" onClick={() => open(null)}>
              {facts.length === 0 ? '＋ Escribir mi dato curioso' : '＋ Si tienes otra anécdota o dato, agrégala aquí'}
            </button>
          )}
          {facts.length > 0 && (
            <p className="hint">Se muestran sin tu nombre para que adivinen, y al final de la ronda se revela que eres tú. Si tu dato sale, ganas puntos extra… ¡y el doble si no te atrapan!</p>
          )}
        </>
      )}
    </section>
  )
}

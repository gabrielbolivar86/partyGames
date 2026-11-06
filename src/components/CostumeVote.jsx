import { useEffect, useMemo, useRef, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'
import { useCostume } from '../hooks/useCostume'

const MEDALS = { 1: '🥇', 2: '🥈', 3: '🥉' }

/**
 * Votación de mejor disfraz (vista del invitado).
 * - Toca a los disfrazados en el orden que prefieras (el primero que tocas = tu 1.º).
 * - Reordena con ▲ ▼ o quítalos con ✕.
 * - Cada cambio se guarda solo (borrador). Lo que cuenta es lo guardado cuando el admin cierra.
 */
export default function CostumeVote() {
  const { data, error } = useCostume()

  if (error) return <section className="card"><div className="error">{error}</div></section>
  if (!data) return <section className="card"><p className="muted">Cargando concurso…</p></section>

  if (data.status === 'not_started') {
    return (
      <section className="card soon">
        <h3>🎭 Mejor disfraz</h3>
        <p className="muted">La votación aún no empieza. Te avisaremos aquí mismo.</p>
      </section>
    )
  }

  if (data.status === 'closed') {
    return (
      <section className="card">
        <h3>🎭 Mejor disfraz</h3>
        {data.podium.length === 0
          ? <p className="muted">¡Votación cerrada! 🤫 Los resultados se revelarán en la pantalla.</p>
          : <MiniPodium podium={data.podium} />}
      </section>
    )
  }

  return <Ballot data={data} />
}

function MiniPodium({ podium }) {
  return (
    <ol className="board compact">
      {[...podium].sort((a, b) => a.place - b.place).map((p) => (
        <li key={p.player_id}>
          <span className="pos">{MEDALS[p.place]}</span>
          <span className="who"><strong>{p.nickname || p.name}</strong> <span className="muted">· {p.costume}</span></span>
        </li>
      ))}
    </ol>
  )
}

function Ballot({ data }) {
  const byId = useMemo(() => Object.fromEntries(data.candidates.map((c) => [c.id, c])), [data.candidates])
  const savedRanking = data.ranking || []
  const hasSaved = data.ranking !== null

  // Ranking local: lo guardado, filtrado a candidatos que siguen existiendo
  const [order, setOrder] = useState(() => savedRanking.filter((id) => byId[id]))
  const [saveState, setSaveState] = useState('idle') // idle | saving | saved | error
  const [saveError, setSaveError] = useState(null)
  const firstRender = useRef(true)
  const timer = useRef(null)

  // Si alguien es eliminado o deja de estar disfrazado, sacarlo del ranking local
  useEffect(() => {
    setOrder((o) => (o.every((id) => byId[id]) ? o : o.filter((id) => byId[id])))
  }, [byId])

  // Guardado automático (debounce)
  useEffect(() => {
    if (firstRender.current) { firstRender.current = false; return }
    setSaveState('saving')
    clearTimeout(timer.current)
    timer.current = setTimeout(async () => {
      const { error } = await supabase.rpc('save_costume_ballot', { p_ranking: order })
      if (error) { setSaveState('error'); setSaveError(errorMessage(error)) }
      else { setSaveState('saved'); setSaveError(null) }
    }, 600)
    return () => clearTimeout(timer.current)
  }, [order])

  // "¡Nuevo!" = disfrazado que llegó después de la primera vez que viste la lista
  const [seen, setSeen] = useState(() => loadSeen(data.candidates.map((c) => c.id), hasSaved, savedRanking))
  useEffect(() => { saveSeen(seen) }, [seen])
  useEffect(() => {
    setSeen((s) => {
      const missing = order.filter((id) => !s.includes(id))
      return missing.length ? [...s, ...missing] : s
    })
  }, [order])

  const unranked = data.candidates.filter((c) => !order.includes(c.id))
  const isNew = (id) => !seen.includes(id)
  const newCount = unranked.filter((c) => isNew(c.id)).length

  const move = (i, dir) => setOrder((o) => {
    const j = i + dir
    if (j < 0 || j >= o.length) return o
    const copy = [...o]
    ;[copy[i], copy[j]] = [copy[j], copy[i]]
    return copy
  })
  const remove = (id) => setOrder((o) => o.filter((x) => x !== id))
  const add = (id) => setOrder((o) => [...o, id])

  if (!data.can_vote) return null

  return (
    <section className="card costume">
      <div className="costume-head">
        <h3>🎭 Vota por el mejor disfraz</h3>
        <SaveBadge state={saveState} />
      </div>
      <p className="hint">Toca a los disfrazados en orden: el primero que tocas es tu 1.º lugar. Puedes cambiarlo hasta que el admin cierre la votación.</p>
      {saveError && <div className="error">{saveError}</div>}

      {data.candidates.length === 0 && <p className="muted">Aún no hay otros invitados disfrazados.</p>}

      {order.length > 0 && (
        <ol className="rank-list">
          {order.map((id, i) => {
            const c = byId[id]
            if (!c) return null
            return (
              <li key={id}>
                <span className="rank-pos">{MEDALS[i + 1] || `${i + 1}.`}</span>
                <span className="who">
                  <strong>{c.nickname || c.name}</strong>
                  <span className="small muted">{c.costume}</span>
                </span>
                <span className="rank-actions">
                  <button type="button" onClick={() => move(i, -1)} disabled={i === 0} aria-label="Subir">▲</button>
                  <button type="button" onClick={() => move(i, 1)} disabled={i === order.length - 1} aria-label="Bajar">▼</button>
                  <button type="button" onClick={() => remove(id)} aria-label="Quitar">✕</button>
                </span>
              </li>
            )
          })}
        </ol>
      )}

      {unranked.length > 0 && (
        <>
          <div className="unranked-title">
            {order.length === 0 ? 'Disfrazados' : 'Sin ordenar'}
            {newCount > 0 && <span className="badge new">{newCount} nuevo{newCount > 1 ? 's' : ''}</span>}
          </div>
          <div className="unranked">
            {unranked.map((c) => (
              <button type="button" key={c.id} className="pick add" onClick={() => add(c.id)}>
                <span>
                  <strong>{c.nickname || c.name}</strong>
                  <span className="small muted"> · {c.costume}</span>
                </span>
                {isNew(c.id) ? <span className="tag-new">¡Nuevo!</span> : <span className="plus">＋</span>}
              </button>
            ))}
          </div>
        </>
      )}
    </section>
  )
}

const SEEN_KEY = 'pg-costume-seen'

function loadSeen(currentIds, hasSaved, savedRanking) {
  try {
    const stored = JSON.parse(localStorage.getItem(SEEN_KEY))
    if (Array.isArray(stored)) return stored
  } catch { /* sin storage */ }
  // Primera vez en este celular: si ya había votado (otro celular), lo nuevo es lo que no está en su voto;
  // si no, nada se marca como nuevo.
  return hasSaved ? savedRanking : currentIds
}

function saveSeen(ids) {
  try { localStorage.setItem(SEEN_KEY, JSON.stringify(ids)) } catch { /* sin storage */ }
}

function SaveBadge({ state }) {
  if (state === 'saving') return <span className="save-badge">Guardando…</span>
  if (state === 'saved') return <span className="save-badge ok">Guardado ✓</span>
  if (state === 'error') return <span className="save-badge err">No guardado</span>
  return null
}

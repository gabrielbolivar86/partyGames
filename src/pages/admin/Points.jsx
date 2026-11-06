import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useRealtimeRefresh } from '../../hooks/useRealtimeRefresh'

const QUICK = [1, 2, 5, 10]

export function PointsForm({ players }) {
  const [playerId, setPlayerId] = useState('')
  const [query, setQuery] = useState('')
  const [amount, setAmount] = useState(5)
  const [sign, setSign] = useState(1)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const list = [...players].sort((a, b) => a.name.localeCompare(b.name))
    return q ? list.filter((p) => `${p.name} ${p.nickname || ''}`.toLowerCase().includes(q)) : list
  }, [players, query])

  const selected = players.find((p) => p.player_id === playerId)
  const points = sign * Math.abs(Number(amount) || 0)

  async function submit() {
    if (!selected || !points) return
    setBusy(true)
    setMsg(null)
    const { error } = await supabase.rpc('admin_add_points', {
      p_player_id: playerId, p_points: points, p_reason: reason,
    })
    setBusy(false)
    if (error) setMsg({ type: 'error', text: errorMessage(error) })
    else {
      setMsg({ type: 'ok', text: `${points > 0 ? '+' : ''}${points} a ${selected.name}` })
      setReason('')
    }
  }

  return (
    <section className="card form">
      <h3>✨ Dar o quitar puntos</h3>
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar invitado…" />
      <div className="pick-list short">
        {filtered.map((p) => (
          <button key={p.player_id} type="button" className={`pick ${playerId === p.player_id ? 'active' : ''}`}
            onClick={() => setPlayerId(p.player_id)}>
            <strong>{p.name}</strong> <span className="muted">· {p.points} pts</span>
          </button>
        ))}
      </div>

      <div className="seg wide">
        <button type="button" className={sign > 0 ? 'active' : ''} onClick={() => setSign(1)}>➕ Dar</button>
        <button type="button" className={sign < 0 ? 'active danger' : ''} onClick={() => setSign(-1)}>➖ Quitar</button>
      </div>
      <div className="row quick">
        {QUICK.map((q) => (
          <button key={q} type="button" className={`chip ${Number(amount) === q ? 'active' : ''}`} onClick={() => setAmount(q)}>{q}</button>
        ))}
        <input type="number" min="1" max="1000" value={amount} onChange={(e) => setAmount(e.target.value)} className="num" />
      </div>
      <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={120} placeholder="Motivo (opcional): ej. ganó el baile" />

      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <button className={`btn ${sign > 0 ? 'primary' : 'danger'}`} disabled={!selected || !points || busy} onClick={submit}>
        {selected ? `${points > 0 ? '+' : ''}${points} puntos a ${selected.name}` : 'Elige un invitado'}
      </button>
    </section>
  )
}

export function LedgerList() {
  const [items, setItems] = useState([])
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('admin_ledger', { p_limit: 40 })
    if (error) setError(error.message)
    else { setError(null); setItems(data || []) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['points_ledger'], refresh)

  async function undo(id) {
    if (!window.confirm('¿Deshacer este movimiento?')) return
    const { error } = await supabase.rpc('admin_delete_points', { p_entry_id: id })
    if (error) setError(errorMessage(error))
    refresh()
  }

  return (
    <section className="card">
      <h3>📜 Últimos movimientos</h3>
      {error && <div className="error">{error}</div>}
      {items.length === 0 && <p className="muted">Todavía no hay puntos registrados.</p>}
      <ul className="ledger">
        {items.map((l) => (
          <li key={l.id}>
            <span className={`delta ${l.points > 0 ? 'pos' : 'neg'}`}>{l.points > 0 ? '+' : ''}{l.points}</span>
            <span className="grow">
              <strong>{l.name}</strong>
              <span className="small muted"> · {l.source}{l.reason ? ` · ${l.reason}` : ''}{!l.visible ? ' · 🙈 oculto' : ''}</span>
            </span>
            {l.source === 'admin' && (
              <button className="btn small ghost-btn" onClick={() => undo(l.id)} title="Deshacer">↩︎</button>
            )}
          </li>
        ))}
      </ul>
    </section>
  )
}

import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useRealtimeRefresh } from '../../hooks/useRealtimeRefresh'

// Lista de invitados: corregir disfraz/nombre o eliminar
export default function Players({ myId }) {
  const [players, setPlayers] = useState([])
  const [query, setQuery] = useState('')
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('admin_players')
    if (error) setError(error.message)
    else { setError(null); setPlayers(data || []) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['players'], refresh)

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? players.filter((p) => `${p.name} ${p.nickname || ''} ${p.costume || ''}`.toLowerCase().includes(q)) : players
  }, [players, query])

  const costumed = players.filter((p) => p.has_costume).length

  async function setAway(p) {
    const { error } = await supabase.rpc('admin_set_away', { p_player: p.player_id, p_away: !p.away })
    if (error) setError(errorMessage(error))
    refresh()
  }

  async function remove(p) {
    if (!window.confirm(`¿Eliminar a ${p.name}? Se borran sus puntos y votos.`)) return
    const { error } = await supabase.rpc('admin_delete_player', { p_player_id: p.player_id })
    if (error) setError(errorMessage(error))
    refresh()
  }

  return (
    <section className="card">
      <h3>👥 Invitados <span className="muted small">{players.length} · {costumed} disfrazados{players.some((p) => p.away) ? ` · ⏸️ ${players.filter((p) => p.away).length} en pausa` : ''}</span></h3>
      <p className="small muted">⏸️ pone a alguien en pausa (conserva su carta).</p>
      {error && <div className="error">{error}</div>}
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar…" />
      <ul className="players-list">
        {filtered.map((p) => (
          <li key={p.player_id}>
            {editing === p.player_id
              ? <EditPlayer player={p} onDone={() => { setEditing(null); refresh() }} />
              : (
                <>
                  <div className="grow">
                    <strong>{p.name}</strong>{p.nickname && <span className="muted"> “{p.nickname}”</span>}
                    {p.is_admin && <span className="tag">admin</span>}
                    {p.away && <span className="away-tag"> ⏸️ en pausa</span>}
                    <div className="small muted">{p.has_costume ? `🧛 ${p.costume}` : 'Sin disfraz'} · 📱 {p.devices}</div>
                  </div>
                  <div className="row nowrap">
                    <button className="btn small ghost-btn" title={p.away ? 'Volvió' : 'Poner en pausa'} onClick={() => setAway(p)}>{p.away ? '▶︎' : '⏸️'}</button>
                    <button className="btn small" onClick={() => setEditing(p.player_id)}>✏️</button>
                    {p.player_id !== myId && <button className="btn small ghost-btn" onClick={() => remove(p)}>🗑</button>}
                  </div>
                </>
              )}
          </li>
        ))}
      </ul>
    </section>
  )
}

function EditPlayer({ player, onDone }) {
  const [f, setF] = useState({
    name: player.name, nickname: player.nickname || '', hasCostume: player.has_costume, costume: player.costume || '',
  })
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function save() {
    setBusy(true)
    const { error } = await supabase.rpc('admin_update_player', {
      p_player_id: player.player_id, p_name: f.name, p_nickname: f.nickname,
      p_has_costume: f.hasCostume, p_costume: f.costume,
    })
    setBusy(false)
    if (error) setError(errorMessage(error))
    else onDone()
  }

  return (
    <div className="form edit-player">
      <input value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="Nombre" maxLength={40} />
      <input value={f.nickname} onChange={(e) => setF({ ...f, nickname: e.target.value })} placeholder="Apodo" maxLength={30} />
      <label className="check">
        <input type="checkbox" checked={f.hasCostume} onChange={(e) => setF({ ...f, hasCostume: e.target.checked })} />
        Está disfrazado
      </label>
      {f.hasCostume && <input value={f.costume} onChange={(e) => setF({ ...f, costume: e.target.value })} placeholder="Disfraz" maxLength={80} />}
      {error && <div className="error">{error}</div>}
      <div className="row">
        <button className="btn small ok" onClick={save} disabled={busy}>Guardar</button>
        <button className="btn small ghost-btn" onClick={onDone}>Cancelar</button>
      </div>
    </div>
  )
}

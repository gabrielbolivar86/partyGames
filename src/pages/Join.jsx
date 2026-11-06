import { useEffect, useMemo, useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'

export default function Join({ notice, clearNotice, onDone }) {
  const [tab, setTab] = useState('new')

  return (
    <div className="screen join">
      <div className="hero">
        <div className="hero-emoji">🎃👻🦇</div>
        <h1 className="spooky">Fiesta de Halloween</h1>
        <p className="muted">Regístrate para sumar puntos durante la noche</p>
      </div>

      {notice && (
        <div className="alert" onClick={clearNotice}>{notice}</div>
      )}

      <div className="tabs">
        <button className={tab === 'new' ? 'active' : ''} onClick={() => setTab('new')}>Soy nuevo</button>
        <button className={tab === 'link' ? 'active' : ''} onClick={() => setTab('link')}>Ya tengo perfil</button>
      </div>

      {tab === 'new' ? <RegisterForm onDone={onDone} /> : <LinkForm onDone={onDone} />}
    </div>
  )
}

function RegisterForm({ onDone }) {
  const [form, setForm] = useState({
    name: '', nickname: '', hasCostume: true, costume: '', funFact: '', funFactOptIn: true,
  })
  const [sending, setSending] = useState(false)
  const [error, setError] = useState(null)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })

  async function submit(e) {
    e.preventDefault()
    setSending(true)
    setError(null)
    const { data, error } = await supabase.rpc('register_player', {
      p_name: form.name,
      p_nickname: form.nickname,
      p_has_costume: form.hasCostume,
      p_costume: form.costume,
      p_fun_fact: form.funFact,
      p_fun_fact_opt_in: form.funFactOptIn && form.funFact.trim() !== '',
    })
    setSending(false)
    if (error) setError(errorMessage(error))
    else {
      try { localStorage.removeItem('pg-costume-seen') } catch { /* sin storage */ }
      onDone(data)
    }
  }

  return (
    <form className="card form" onSubmit={submit}>
      <label>Nombre *
        <input value={form.name} onChange={set('name')} maxLength={40} required autoComplete="given-name" placeholder="Ej. Ana Pérez" />
      </label>
      <label>Apodo
        <input value={form.nickname} onChange={set('nickname')} maxLength={30} placeholder="Cómo te dicen" />
      </label>

      <div className="toggle-row">
        <span>¿Vienes disfrazado?</span>
        <div className="seg">
          <button type="button" className={form.hasCostume ? 'active' : ''} onClick={() => setForm({ ...form, hasCostume: true })}>Sí 🧛</button>
          <button type="button" className={!form.hasCostume ? 'active' : ''} onClick={() => setForm({ ...form, hasCostume: false })}>No</button>
        </div>
      </div>
      {form.hasCostume && (
        <label>¿De qué vienes disfrazado? *
          <input value={form.costume} onChange={set('costume')} maxLength={80} required placeholder="Ej. Momia egipcia" />
        </label>
      )}
      {!form.hasCostume && <p className="hint">Sin disfraz no entras al concurso de mejor disfraz, pero sí votas y juegas todo lo demás.</p>}

      <label>Un dato curioso o anécdota tuya 🤫
        <textarea value={form.funFact} onChange={set('funFact')} maxLength={200} rows={3}
          placeholder="Algo gracioso que poca gente sepa de ti (es para un juego, será anónimo)" />
      </label>
      <label className="check">
        <input type="checkbox" checked={form.funFactOptIn} onChange={set('funFactOptIn')} />
        Quiero que mi dato entre al juego "¿Quién es el personaje?"
      </label>

      {error && <div className="error">{error}</div>}
      <button className="btn primary" disabled={sending}>{sending ? 'Enviando…' : 'Entrar a la fiesta'}</button>
    </form>
  )
}

function LinkForm({ onDone }) {
  const [players, setPlayers] = useState([])
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState(null)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    supabase.from('players').select('id, name, nickname, costume').eq('approved', true).order('name')
      .then(({ data, error }) => error ? setError(error.message) : setPlayers(data || []))
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? players.filter((p) => `${p.name} ${p.nickname || ''}`.toLowerCase().includes(q)) : players
  }, [players, query])

  async function submit() {
    if (!selected) return
    setSending(true)
    setError(null)
    const { data, error } = await supabase.rpc('request_link', { p_player_id: selected })
    setSending(false)
    if (error) setError(errorMessage(error))
    else onDone(data)
  }

  return (
    <div className="card form">
      <p className="hint">¿Cambiaste de celular o se borró tu sesión? Busca tu nombre y el admin aprobará este dispositivo.</p>
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar tu nombre…" />
      <div className="pick-list">
        {filtered.map((p) => (
          <button key={p.id} type="button" className={`pick ${selected === p.id ? 'active' : ''}`} onClick={() => setSelected(p.id)}>
            <strong>{p.name}</strong>
            {p.nickname && <span className="muted"> “{p.nickname}”</span>}
          </button>
        ))}
        {filtered.length === 0 && <p className="muted">No hay coincidencias.</p>}
      </div>
      {error && <div className="error">{error}</div>}
      <button className="btn primary" disabled={!selected || sending} onClick={submit}>
        {sending ? 'Enviando…' : 'Solicitar acceso'}
      </button>
    </div>
  )
}

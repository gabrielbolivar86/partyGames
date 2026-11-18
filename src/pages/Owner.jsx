import { useCallback, useEffect, useState } from 'react'
import { supabase, errorMessage, ensureSession } from '../lib/supabase'
import { hostUrl, joinUrl, dashboardUrl } from '../lib/urls'
import { GAME_CATALOG } from '../lib/games'

// Panel del dueño de la app: crear fiestas y darles anfitrión (enlace + contraseña)
export default function Owner() {
  const [parties, setParties] = useState(null)
  const [error, setError] = useState(null)
  const [fresh, setFresh] = useState(null) // { slug, name, password } recién creada o con clave nueva

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('owner_list_parties')
    if (error) setError(errorMessage(error))
    else { setError(null); setParties(data) }
  }, [])

  useEffect(() => {
    (async () => {
      const err = await ensureSession()
      if (err) setError(err)
      else load()
    })()
  }, [load])

  return (
    <div className="screen">
      <header className="topbar">
        <div className="brand">👑 <span>Mis fiestas</span></div>
      </header>
      <main className="content">
        {error && (
          <section className="card">
            <div className="error">{error}</div>
            <p className="hint">Si eres el dueño: registra este dispositivo en tu fiesta y corre <code>supabase/12_hacerme_dueno.sql</code>.</p>
          </section>
        )}
        {fresh && <HostCard info={fresh} onClose={() => setFresh(null)} />}
        {parties && <CreateParty onCreated={(info) => { setFresh(info); load() }} />}
        {parties?.map((p) => (
          <PartyRow key={p.id} p={p} onPassword={(password) => setFresh({ slug: p.slug, name: p.name, password })} onDeleted={load} />
        ))}
      </main>
    </div>
  )
}

function randomPassword() {
  const abc = 'abcdefghjkmnpqrstuvwxyz23456789'
  const bytes = crypto.getRandomValues(new Uint8Array(8))
  return Array.from(bytes, (b) => abc[b % abc.length]).join('')
}

function slugify(text) {
  return text.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40)
}

function CreateParty({ onCreated }) {
  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [slugTouched, setSlugTouched] = useState(false)
  const [password, setPassword] = useState(randomPassword)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { data, error } = await supabase.rpc('owner_create_party', { p_name: name, p_slug: slug, p_password: password })
    setBusy(false)
    if (error) return setError(errorMessage(error))
    onCreated({ slug: data.slug, name: name.trim(), password })
    setName(''); setSlug(''); setSlugTouched(false); setPassword(randomPassword())
  }

  return (
    <form className="card form" onSubmit={submit}>
      <h3>➕ Nueva fiesta</h3>
      <label>Nombre de la fiesta
        <input value={name} maxLength={60} required placeholder="Ej. Halloween en casa de Ana"
          onChange={(e) => { setName(e.target.value); if (!slugTouched) setSlug(slugify(e.target.value)) }} />
      </label>
      <label>Enlace (lo que va en la URL)
        <input value={slug} required maxLength={40} placeholder="halloween-ana"
          onChange={(e) => { setSlugTouched(true); setSlug(slugify(e.target.value)) }} />
      </label>
      {slug && <p className="small muted">{joinUrl(slug)}</p>}
      <label>Contraseña del anfitrión
        <div className="row nowrap">
          <input value={password} onChange={(e) => setPassword(e.target.value)} minLength={6} required autoComplete="off" />
          <button className="btn small ghost-btn" type="button" onClick={() => setPassword(randomPassword())} title="Generar otra">🎲</button>
        </div>
      </label>
      {error && <div className="error">{error}</div>}
      <button className="btn primary" disabled={busy}>{busy ? 'Creando…' : 'Crear fiesta'}</button>
    </form>
  )
}

// Lo que le mandas al anfitrión. La contraseña solo se ve aquí (en la base queda cifrada).
function HostCard({ info, onClose }) {
  const message = `🎃 ¡Tu fiesta "${info.name}" está lista!\n` +
    `Entra como anfitrión: ${hostUrl(info.slug)}\n` +
    `Contraseña: ${info.password}\n` +
    `Ahí verás el enlace para tus invitados y el de la TV.`
  return (
    <section className="card form">
      <h3>🔑 Datos para el anfitrión</h3>
      <p className="hint">Cópialos ahora: la contraseña no se vuelve a mostrar (puedes generar otra cuando quieras).</p>
      <CopyLine label="Enlace de anfitrión" value={hostUrl(info.slug)} />
      <CopyLine label="Contraseña" value={info.password} />
      <CopyLine label="Mensaje completo" value={message} multiline />
      <button className="btn small ghost-btn" onClick={onClose}>Listo</button>
    </section>
  )
}

export function CopyLine({ label, value, multiline }) {
  const [done, setDone] = useState(false)
  async function copy() {
    try { await navigator.clipboard.writeText(value); setDone(true); setTimeout(() => setDone(false), 1500) } catch { /* sin portapapeles */ }
  }
  return (
    <div className="copy-line">
      <span className="small muted">{label}</span>
      <div className="row nowrap">
        {multiline
          ? <textarea readOnly value={value} rows={4} onFocus={(e) => e.target.select()} />
          : <input readOnly value={value} onFocus={(e) => e.target.select()} />}
        <button className="btn small" type="button" onClick={copy}>{done ? '✓' : '📋'}</button>
      </div>
    </div>
  )
}

function PartyRow({ p, onPassword, onDeleted }) {
  const [open, setOpen] = useState(false)
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState(null)
  const games = GAME_CATALOG.filter((g) => p.games?.includes(g.id)).map((g) => g.emoji).join(' ')

  async function newPassword() {
    if (!window.confirm(`¿Generar una contraseña nueva para "${p.name}"? La anterior deja de funcionar (los anfitriones que ya entraron siguen dentro).`)) return
    const password = randomPassword()
    const { error } = await supabase.rpc('owner_set_password', { p_slug: p.slug, p_password: password })
    if (error) setError(errorMessage(error))
    else onPassword(password)
  }

  async function remove() {
    const { error } = await supabase.rpc('owner_delete_party', { p_slug: p.slug, p_confirm: confirm })
    if (error) setError(errorMessage(error))
    else onDeleted()
  }

  return (
    <section className="card form">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div>
          <h3 style={{ margin: 0 }}>{p.name}</h3>
          <div className="small muted">/{p.slug} · {p.players} invitados · {p.hosts} anfitrión(es) {games && `· ${games}`}</div>
        </div>
        <button className="btn small ghost-btn" onClick={() => setOpen((o) => !o)}>{open ? 'Cerrar' : 'Ver'}</button>
      </div>
      {open && (
        <>
          <CopyLine label="Anfitrión (con contraseña)" value={hostUrl(p.slug)} />
          <CopyLine label="Invitados" value={joinUrl(p.slug)} />
          <CopyLine label="Pantalla / TV" value={dashboardUrl(p.slug)} />
          <div className="row">
            <a className="btn small" href={`#/p/${p.slug}/`}>Abrir fiesta</a>
            <button className="btn small" onClick={newPassword}>{p.has_password ? '🔑 Nueva contraseña' : '🔑 Crear contraseña'}</button>
          </div>
          <details>
            <summary className="small muted">Borrar fiesta…</summary>
            <p className="hint">Se borran sus invitados, puntos y juegos. Escribe <code>{p.slug}</code> para confirmar.</p>
            <input value={confirm} onChange={(e) => setConfirm(e.target.value)} />
            <button className="btn danger" disabled={confirm !== p.slug} onClick={remove}>🗑 Borrar para siempre</button>
          </details>
          {error && <div className="error">{error}</div>}
        </>
      )}
    </section>
  )
}

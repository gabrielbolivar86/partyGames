import { useCallback, useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { useRealtimeRefresh } from '../../hooks/useRealtimeRefresh'

const STATUS = {
  not_started: { label: 'Sin empezar', cls: '' },
  open: { label: 'Activa', cls: 'ok' },
  closed: { label: 'Terminada', cls: 'warn' },
}

export default function CodesAdmin({ dashboardMode }) {
  const [ov, setOv] = useState(null)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [count, setCount] = useState(8)
  const [showPins, setShowPins] = useState(false)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('admin_hunt_overview')
    if (error) setError(error.message)
    else { setError(null); setOv(data) }
  }, [])

  useEffect(() => { refresh() }, [refresh])
  useRealtimeRefresh(['hunt_claims', 'code_hunt'], refresh)

  async function call(fn, args, confirmText) {
    if (confirmText && !window.confirm(confirmText)) return false
    setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    if (error) setError(errorMessage(error))
    refresh()
    return !error
  }

  async function editLabel(c) {
    const label = window.prompt(`¿Dónde está escondido el código #${c.number}? (solo lo ves tú)`, c.label || '')
    if (label === null) return
    call('admin_hunt_update_code', { p_code_id: c.id, p_label: label })
  }

  async function deleteAll() {
    const ok = window.prompt('Esto borra TODOS los códigos y los puntos que dieron. Escribe BORRAR para confirmar')
    if (ok === null) return
    call('admin_hunt_delete_all', { p_confirm: ok })
  }

  if (!ov) return <section className="card"><p className="muted">Cargando…</p>{error && <div className="error">{error}</div>}</section>
  const st = STATUS[ov.status]
  const printUrl = window.location.origin + window.location.pathname + '#/imprimir-codigos'

  return (
    <>
      <section className="card">
        <h3>🔍 Caza de códigos <span className={`status ${st.cls}`}>{st.label}</span></h3>
        {error && <div className="error">{error}</div>}
        <div className="stats">
          <div><b>{ov.codes.length}</b><span>códigos</span></div>
          <div><b>{ov.codes.filter((c) => c.found > 0).length}</b><span>encontrados</span></div>
          <div><b>{ov.claims}</b><span>registros</span></div>
        </div>
        {ov.status !== 'open'
          ? <button className="btn primary" disabled={busy || ov.codes.length === 0} onClick={() => call('admin_hunt_set_status', { p_status: 'open' })}>
              {ov.status === 'closed' ? '↺ Reactivar la caza' : '▶︎ Empezar la caza'}
            </button>
          : <button className="btn danger wide" disabled={busy} onClick={() => call('admin_hunt_set_status', { p_status: 'closed' }, '¿Terminar la caza? Ya no se podrán registrar códigos.')}>
              ■ Terminar la caza
            </button>}
        <div className="row" style={{ marginTop: 10 }}>
          <button className="btn small" disabled={busy}
            onClick={() => call('admin_set_dashboard', { p_mode: dashboardMode === 'codes' ? 'leaderboard' : 'codes' })}>
            📺 {dashboardMode === 'codes' ? 'Volver a tabla general' : 'Mostrar en pantalla'}
          </button>
        </div>
      </section>

      <section className="card form">
        <h3>🔑 Códigos</h3>
        <div className="row">
          <input type="number" min="1" max="50" value={count} onChange={(e) => setCount(e.target.value)} className="num" />
          <button className="btn" disabled={busy} onClick={() => call('admin_hunt_create_codes', { p_count: Number(count) })}>＋ Crear códigos</button>
        </div>
        {ov.codes.length > 0 && (
          <>
            <a className="btn primary" href={printUrl} target="_blank" rel="noreferrer">🖨 Imprimir códigos</a>
            <button className="btn small ghost-btn" onClick={() => setShowPins((s) => !s)}>{showPins ? '🙈 Ocultar códigos' : '👀 Mostrar códigos'}</button>
            <ul className="codes-list">
              {ov.codes.map((c) => (
                <li key={c.id}>
                  <span className="code-num">#{c.number}</span>
                  <span className="grow">
                    <span className="code-pin">{showPins ? c.pin : '••••••'}</span>
                    <button className="link-btn" onClick={() => editLabel(c)}>📍 {c.label || 'agregar ubicación'}</button>
                    <div className="small muted">{c.found ? `${c.found} lo encontraron · 1.º ${c.first}` : 'Nadie lo encontró aún'}</div>
                  </span>
                  <button className="btn small ghost-btn" disabled={busy}
                    onClick={() => call('admin_hunt_delete_code', { p_code_id: c.id }, `¿Eliminar el código #${c.number}? Se quitan los puntos que dio.`)}>🗑</button>
                </li>
              ))}
            </ul>
            <button className="btn small ghost-btn" onClick={deleteAll}>🗑 Borrar todos los códigos</button>
          </>
        )}
      </section>

      <HuntSettings settings={ov.settings} onSaved={refresh} />
    </>
  )
}

function HuntSettings({ settings, onSaved }) {
  const [s, setS] = useState(settings)
  const [msg, setMsg] = useState(null)
  useEffect(() => { setS(settings) }, [JSON.stringify(settings)]) // eslint-disable-line

  async function save() {
    const { error } = await supabase.rpc('admin_hunt_settings', {
      p_max: Number(s.max), p1: Number(s.p1), p2: Number(s.p2), p3: Number(s.p3), p46: Number(s.p46), prest: Number(s.rest),
    })
    setMsg(error ? { type: 'error', text: errorMessage(error) } : { type: 'ok', text: 'Guardado' })
    onSaved()
  }

  const field = (k, label) => (
    <label className="pts-field">{label}
      <input type="number" min="0" max="1000" value={s[k]} onChange={(e) => setS({ ...s, [k]: e.target.value })} />
    </label>
  )

  return (
    <section className="card form">
      <h3>⚙️ Reglas</h3>
      <div className="pts-grid five">
        {field('p1', '1.º')}
        {field('p2', '2.º')}
        {field('p3', '3.º')}
        {field('p46', '4.º-6.º')}
        {field('rest', '7.º+')}
      </div>
      <label className="pts-field">Máximo de códigos por persona (0 = sin límite)
        <input type="number" min="0" max="100" value={s.max} onChange={(e) => setS({ ...s, max: e.target.value })} />
      </label>
      <p className="hint">Puntos según el orden en que cada persona encuentra ESE código. Los cambios aplican a los próximos registros.</p>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <button className="btn" onClick={save}>Guardar reglas</button>
    </section>
  )
}

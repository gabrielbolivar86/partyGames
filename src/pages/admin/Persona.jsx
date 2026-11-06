import { useEffect, useState } from 'react'
import { supabase, errorMessage } from '../../lib/supabase'
import { usePersonaRpc, useCountdown } from '../../hooks/usePersona'

export default function PersonaAdmin({ dashboardMode }) {
  const { data: ov, error: loadError, refresh, offset } = usePersonaRpc('admin_persona_overview')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [showOwner, setShowOwner] = useState(false)

  async function call(fn, args, confirmText) {
    if (confirmText && !window.confirm(confirmText)) return
    setBusy(true)
    const { error } = await supabase.rpc(fn, args)
    setBusy(false)
    setError(error ? errorMessage(error) : null)
    refresh()
  }

  if (!ov) return <section className="card"><p className="muted">Cargando…</p>{loadError && <div className="error">{loadError}</div>}</section>
  const round = ov.round
  const voting = round?.status === 'voting'

  return (
    <>
      <section className="card">
        <h3>🕵️ ¿Quién es el personaje?</h3>
        {error && <div className="error">{error}</div>}
        <div className="stats">
          <div><b>{ov.pool.available}</b><span>datos sin usar</span></div>
          <div><b>{ov.history.length}</b><span>rondas jugadas</span></div>
          <div><b>{ov.pool.with_fact}/{ov.pool.players}</b><span>personas con dato</span></div>
        </div>

        {!voting && (
          <button className="btn primary" disabled={busy || ov.pool.available === 0} onClick={() => call('admin_persona_start', {})}>
            ▶︎ {round ? 'Siguiente ronda' : 'Nueva ronda'} (dato al azar)
          </button>
        )}
        {ov.pool.available === 0 && !voting && <p className="hint">No quedan datos sin usar. Los invitados pueden agregar más desde "Mis datos curiosos" en su celular.</p>}
        {ov.pool.available > 0 && !voting && <p className="hint">{ov.pool.facts} datos en total. Cada ronda saca uno al azar; como hay personas con varios datos, nadie puede adivinar por descarte.</p>}
        <div className="row" style={{ marginTop: 10 }}>
          {dashboardMode !== 'persona'
            ? <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'persona' })}>📺 Mostrar en pantalla</button>
            : <button className="btn small" onClick={() => call('admin_set_dashboard', { p_mode: 'leaderboard' })}>📺 Volver a tabla general</button>}
          {round?.status === 'revealed' && <button className="btn small ghost-btn" onClick={() => call('admin_persona_clear', {})}>Quitar ronda de la pantalla</button>}
        </div>
      </section>

      {round && (
        <section className="card">
          <h3>Ronda #{round.number} <span className={`status ${voting ? 'ok' : 'warn'}`}>{voting ? 'Votando' : 'Revelada'}</span></h3>
          <blockquote className="persona-fact">“{round.fact}”</blockquote>
          <button className="link-btn" onClick={() => setShowOwner((s) => !s)}>
            {showOwner ? `🙈 Es de: ${round.owner}` : '👀 Ver de quién es (spoiler)'}
          </button>

          {voting && <VotingControls round={round} offset={offset} busy={busy} call={call} />}
          {!voting && round.result && (
            <p className="small">
              Era <b>{round.result.owner.name}</b> · {round.result.correct} de {round.result.total} acertaron
            </p>
          )}
        </section>
      )}

      <PersonaSettings settings={ov.settings} onSaved={refresh} />

      {ov.history.length > 0 && (
        <section className="card">
          <h3>📜 Rondas jugadas</h3>
          <ul className="ledger">
            {ov.history.map((h) => (
              <li key={h.number}>
                <span className="delta pos">#{h.number}</span>
                <span className="grow"><b>{h.owner}</b> <span className="small muted">· {h.correct}/{h.total} acertaron · “{h.fact}”</span></span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  )
}

function VotingControls({ round, offset, busy, call }) {
  const left = useCountdown(round.ends_at, offset)
  return (
    <>
      <div className="stats two">
        <div><b>{left > 0 ? `${left}s` : '⏰'}</b><span>{left > 0 ? 'quedan' : '¡tiempo!'}</span></div>
        <div><b>{round.votes}</b><span>votos</span></div>
      </div>
      <button className="btn primary" disabled={busy}
        onClick={() => call('admin_persona_reveal', {}, left > 0 ? 'Aún queda tiempo. ¿Revelar de todas formas?' : null)}>
        🎭 Revelar quién es
      </button>
      <div className="row" style={{ marginTop: 10 }}>
        <button className="btn small ghost-btn" disabled={busy}
          onClick={() => call('admin_persona_cancel', { p_discard: false }, '¿Cancelar la ronda? El dato vuelve a quedar disponible.')}>↩︎ Cancelar ronda</button>
        <button className="btn small ghost-btn" disabled={busy}
          onClick={() => call('admin_persona_cancel', { p_discard: true }, '¿Descartar este dato? No volverá a salir.')}>🚫 Descartar dato</button>
      </div>
    </>
  )
}

function PersonaSettings({ settings, onSaved }) {
  const [s, setS] = useState(settings)
  const [msg, setMsg] = useState(null)
  useEffect(() => { setS(settings) }, [JSON.stringify(settings)]) // eslint-disable-line

  async function save() {
    const { error } = await supabase.rpc('admin_persona_settings', {
      p_seconds: Number(s.seconds), p_correct: Number(s.correct), p_bonus: Number(s.bonus),
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
      <div className="pts-grid three">
        {field('seconds', '⏱ Segundos')}
        {field('correct', '✅ Adivinar')}
        {field('bonus', '😎 Dueño')}
      </div>
      <p className="hint">Quien adivina gana "Adivinar". El dueño del dato gana "Dueño" por participar, y <b>el doble</b> si no lo atrapan (menos de la mitad de los votos acertó).</p>
      {msg && <div className={msg.type === 'error' ? 'error' : 'success'}>{msg.text}</div>}
      <button className="btn" onClick={save}>Guardar reglas</button>
    </section>
  )
}

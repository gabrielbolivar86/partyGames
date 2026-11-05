import { useState } from 'react'
import { supabase, errorMessage } from '../lib/supabase'

export default function Waiting({ me, onChange, onCheck }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const isLink = me.kind === 'link'

  async function cancel() {
    setBusy(true)
    const { data, error } = await supabase.rpc('cancel_my_request')
    setBusy(false)
    if (error) setError(errorMessage(error))
    else onChange(data)
  }

  return (
    <div className="screen center">
      <div className="card waiting">
        <div className="ghost">👻</div>
        <h2>¡Hola, {me.player.nickname || me.player.name}!</h2>
        <p>{isLink
          ? 'Pedimos al admin que apruebe este celular para tu perfil.'
          : 'Tu registro llegó al admin. En cuanto te apruebe, entrarás automáticamente.'}</p>
        <p className="muted small">Puedes dejar esta pantalla abierta, se actualiza sola.</p>
        {error && <div className="error">{error}</div>}
        <div className="row">
          <button className="btn" onClick={onCheck}>Revisar</button>
          <button className="btn ghost-btn" onClick={cancel} disabled={busy}>Cancelar</button>
        </div>
      </div>
    </div>
  )
}

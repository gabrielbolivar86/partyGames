import { THEMES } from '../lib/themes'
import { Icon } from './Icon'

// Grilla de mini-cartas: cada una se pinta con SUS colores (vienen de THEMES, no del tema activo)
export default function ThemePicker({ value, onChange, busy }) {
  return (
    <div className="theme-picker" role="radiogroup" aria-label="Tema de la fiesta">
      {THEMES.map((t) => {
        const c = t.colors
        const active = t.id === value
        return (
          <button key={t.id} type="button" role="radio" aria-checked={active} disabled={busy}
            className={`theme-option ${active ? 'active' : ''}`}
            style={{ background: c.page, borderColor: c.ink, color: c.textOnPage }}
            onClick={() => !active && onChange(t.id)}>
            <span className="theme-name"><Icon name={t.icon} size={18} />{t.name}</span>
            <span className="theme-q" style={{ background: c.question, color: '#18181B', borderColor: c.ink }}>¿Listos?</span>
            <span className="theme-swatches">
              {[c.primary, c.secondary, c.surface].map((h, i) => <i key={i} style={{ background: h, borderColor: c.ink }} />)}
            </span>
            {active && <span className="theme-check" style={{ background: c.primary, color: c.onPrimary }}><Icon name="IconCheck" size={16} /></span>}
          </button>
        )
      })}
    </div>
  )
}

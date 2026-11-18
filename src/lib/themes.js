// Temas por fiesta (Fase 11). Los colores se definen aquí y en src/styles.css ([data-theme="…"]).
// El anfitrión elige uno en "Mi fiesta"; llega por get_dashboard().party.theme.

const INK = '#18181B'
const WHITE = '#FFFFFF'
const MUTED = '#52525B'

const light = (c) => ({ ink: INK, textOnPage: INK, muted: MUTED, surface: WHITE, ...c })

export const THEMES = [
  { id: 'fiesta', name: 'Fiesta', icon: 'IconConfetti',
    colors: light({ page: '#FFFBF0', primary: '#FF5D5D', secondary: '#4D7CFE', question: '#FACC15', onPrimary: WHITE, onSecondary: WHITE }) },
  { id: 'halloween', name: 'Halloween', icon: 'IconPumpkinScary',
    colors: { ink: '#0D0A14', textOnPage: '#F4F1FF', muted: '#C9C0E0', page: '#2B2140', surface: '#F4F1FF',
      primary: '#FF8A3D', secondary: '#A78BFA', question: '#A3E635', onPrimary: INK, onSecondary: INK } },
  { id: 'navidad', name: 'Navidad', icon: 'IconChristmasTree',
    colors: light({ page: '#FFF4E4', primary: '#D62839', secondary: '#1B7F4E', question: '#9ED9A8', onPrimary: WHITE, onSecondary: WHITE }) },
  { id: 'baby-nino', name: 'Baby shower niño', icon: 'IconBabyCarriage',
    colors: light({ page: '#DCEFFF', primary: '#2E9BEA', secondary: '#3CCFC0', question: '#FFC93C', onPrimary: WHITE, onSecondary: INK }) },
  { id: 'baby-nina', name: 'Baby shower niña', icon: 'IconBabyCarriage',
    colors: light({ page: '#FFE3EE', primary: '#F0569A', secondary: '#B43C7A', question: '#FFB6D3', onPrimary: WHITE, onSecondary: WHITE }) },
  { id: 'revelacion', name: 'Revelación de género', icon: 'IconHelpHexagon',
    colors: light({ page: '#F7F1FF', primary: '#F0569A', secondary: '#2E9BEA', question: '#C9B6FF', onPrimary: WHITE, onSecondary: WHITE }) },
  { id: 'verde', name: 'Neutro verde', icon: 'IconLeaf',
    colors: light({ page: '#F1F4EC', primary: '#2F8F5B', secondary: '#8DB596', question: '#DCE8C8', onPrimary: WHITE, onSecondary: INK }) },
  { id: 'azul', name: 'Neutro azul', icon: 'IconDroplet',
    colors: light({ page: '#EEF3FA', primary: '#2F5FD0', secondary: '#7FA8E8', question: '#CFE0FA', onPrimary: WHITE, onSecondary: INK }) },
]

export const THEME_IDS = THEMES.map((t) => t.id)
export const DEFAULT_THEME = 'fiesta'
const STORAGE_KEY = 'pg-theme'

export function getTheme(id) {
  return THEMES.find((t) => t.id === id) || THEMES[0]
}

export function readSavedTheme() {
  try { return getTheme(localStorage.getItem(STORAGE_KEY)).id } catch { return DEFAULT_THEME }
}

export function applyTheme(id) {
  const theme = getTheme(id)
  document.documentElement.dataset.theme = theme.id
  document.querySelector('meta[name=theme-color]')?.setAttribute('content', theme.colors.page)
  try { localStorage.setItem(STORAGE_KEY, theme.id) } catch { /* sin storage */ }
}

// Razón de contraste WCAG entre dos colores #RRGGBB
export function contrast(a, b) {
  const lum = (hex) => {
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }
  const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m)
  return (x + 0.05) / (y + 0.05)
}

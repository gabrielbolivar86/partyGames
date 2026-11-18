import { useEffect } from 'react'
import { useDashboard } from '../hooks/useDashboard'
import { applyTheme } from '../lib/themes'

// Aplica el tema de la fiesta (llega en tiempo real por get_dashboard). No dibuja nada.
export default function ThemeSync() {
  const { data } = useDashboard()
  const theme = data?.party?.theme
  const name = data?.party?.name
  useEffect(() => { if (data) applyTheme(theme) }, [data, theme])
  useEffect(() => { document.title = name || 'Juegos de fiesta' }, [name])
  return null
}

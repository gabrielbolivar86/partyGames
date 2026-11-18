import { ThemeIcon } from './Icon'

// Cargando: el ícono del tema en una cartita que se tambalea
export default function Spinner() {
  return <div className="spinner" role="status" aria-label="Cargando"><ThemeIcon size={36} /></div>
}

import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'

/**
 * Sesión del invitado en este celular.
 * - Crea una sesión anónima la primera vez (queda guardada en el navegador).
 * - Pregunta al servidor el estado: none | pending | approved.
 * - Mientras está "pending" consulta cada 3 s (polling) hasta que el admin lo apruebe.
 */
export function useMe() {
  const [me, setMe] = useState(null)        // respuesta de my_status()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [notice, setNotice] = useState(null) // ej. "tu solicitud fue rechazada"
  const prevStatus = useRef(null)

  const refresh = useCallback(async () => {
    const { data, error } = await supabase.rpc('my_status')
    if (error) {
      setError(error.message)
    } else {
      setError(null)
      if (prevStatus.current === 'pending' && data.status === 'none') {
        setNotice('El admin no aprobó la solicitud. Revisa tus datos o habla con el anfitrión.')
      }
      if (prevStatus.current === 'approved' && data.status === 'none') {
        setNotice('Este celular fue desvinculado de tu perfil.')
      }
      prevStatus.current = data.status
      setMe(data)
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        const { error } = await supabase.auth.signInAnonymously()
        if (error) {
          if (!cancelled) {
            setError('No se pudo iniciar sesión: ' + error.message)
            setLoading(false)
          }
          return
        }
      }
      if (!cancelled) refresh()
    })()
    return () => { cancelled = true }
  }, [refresh])

  // Polling solo mientras espera aprobación
  const status = me?.status
  useEffect(() => {
    if (status !== 'pending') return
    const t = setInterval(refresh, 3000)
    return () => clearInterval(t)
  }, [status, refresh])

  // Al volver a la app, revisar estado
  useEffect(() => {
    const onVisible = () => document.visibilityState === 'visible' && refresh()
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [refresh])

  return { me, setMe, loading, error, notice, clearNotice: () => setNotice(null), refresh }
}

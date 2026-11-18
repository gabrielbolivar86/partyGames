import { getParty } from './supabase'

// URL base de la app (funciona en Vercel y en GitHub Pages /repo/)
const base = () => window.location.origin + window.location.pathname

// Enlaces de una fiesta (por defecto, la fiesta abierta ahora)
export const partyUrl = (slug = getParty()) => base() + `#/p/${slug}`
export const joinUrl = (slug = getParty()) => partyUrl(slug) + '/'
export const dashboardUrl = (slug = getParty()) => partyUrl(slug) + '/dashboard'
export const hostUrl = (slug = getParty()) => partyUrl(slug) + '/anfitrion'
export const printCodesUrl = (slug = getParty()) => partyUrl(slug) + '/imprimir-codigos'
export const ownerUrl = () => base() + '#/owner'

// Fiesta que se usó por última vez en este dispositivo
const LAST_KEY = 'pg-last-party'
export const DEFAULT_PARTY = 'halloween-2026'
export const readLastParty = () => { try { return localStorage.getItem(LAST_KEY) } catch { return null } }
export const saveLastParty = (slug) => { try { localStorage.setItem(LAST_KEY, slug) } catch { /* sin storage */ } }

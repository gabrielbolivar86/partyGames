// URL base de la app (funciona en Vercel y en GitHub Pages /repo/)
const base = () => window.location.origin + window.location.pathname

export const joinUrl = () => base() + '#/'
export const dashboardUrl = () => base() + '#/dashboard'

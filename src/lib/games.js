// Catálogo de juegos: lo que el anfitrión puede activar o apagar para su fiesta.
// `tab` = pestaña del panel admin · `mode` = modo de la pantalla (TV).
export const GAME_CATALOG = [
  {
    id: 'costume', emoji: '🎭', name: 'Mejor disfraz', tab: 'costume', mode: 'costume_reveal',
    players: '3 o más (con varios disfrazados)',
    duration: 'Toda la noche',
    description: 'Cada invitado vota por su disfraz favorito desde el celular y al final se revela el podio en la pantalla.',
  },
  {
    id: 'codes', emoji: '🔍', name: 'Caza de códigos', tab: 'codes', mode: 'codes',
    players: '2 o más (cualquier cantidad)',
    duration: 'Toda la noche',
    description: 'Imprimes códigos secretos, los escondes por la casa y quien los encuentra los escribe para sumar puntos.',
  },
  {
    id: 'persona', emoji: '🕵️', name: '¿Quién es el personaje?', tab: 'persona', mode: 'persona',
    players: '4 o más (necesita datos curiosos)',
    duration: '1–2 min por ronda',
    description: 'Sale un dato curioso de un invitado y todos votan quién creen que es. Usa los datos que escriben al registrarse.',
  },
  {
    id: 'impostor', emoji: '🃏', name: 'El Impostor', tab: 'impostor', mode: 'impostor',
    players: '3 a 12 (ideal 5–8)',
    duration: '5–10 min por ronda',
    description: 'Todos reciben la misma palabra menos el impostor. Dan pistas en voz alta y votan para descubrirlo.',
  },
  {
    id: 'gift', emoji: '🎁', name: 'El Regalo', tab: 'gift', mode: 'gift',
    players: '4 o más',
    duration: '10–15 min',
    description: 'Cada uno escribe una parte del regalo loco de otro sin ver lo demás; al final se leen y se vota el mejor.',
  },
  {
    id: 'wolf', emoji: '🐺', name: 'Hombre Lobo', tab: 'wolf', mode: 'wolf',
    players: '4 a 18 (ideal 6 o más) + 1 narrador',
    duration: '20–40 min',
    description: 'Roles secretos en el celular: los lobos atacan de noche y el pueblo los busca de día. Uno narra desde su celular.',
  },
]

export const ALL_GAME_IDS = GAME_CATALOG.map((g) => g.id)
const byField = (field) => Object.fromEntries(GAME_CATALOG.map((g) => [g[field], g.id]))
const TAB_TO_GAME = byField('tab')
const MODE_TO_GAME = byField('mode')

// Si todavía no llegó la lista (o la base no tiene fase 10) se muestran todos
const isOn = (games, id) => !id || !Array.isArray(games) || games.includes(id)
export const tabEnabled = (games, tab) => isOn(games, TAB_TO_GAME[tab])
export const modeEnabled = (games, mode) => isOn(games, MODE_TO_GAME[mode])
export const gameEnabled = (games, id) => isOn(games, id)

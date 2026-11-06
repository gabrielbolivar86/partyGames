// Hombre Lobo · definición de roles, baraja sugerida, balance y guion del narrador (etapa 1)

export const ROLES = {
  lobo: {
    name: 'Lobo', emoji: '🐺', team: 'wolves', weight: -6,
    does: 'Cada noche, con tu manada, eliges a una víctima. De día finges ser un aldeano.',
    wins: 'Ganas cuando los lobos son tantos como los aldeanos vivos.',
  },
  aldeano: {
    name: 'Aldeano', emoji: '👤', team: 'village', weight: 1,
    does: 'No tienes poderes: tu arma es debatir y votar bien de día.',
    wins: 'Ganas cuando todos los lobos están muertos.',
  },
  vidente: {
    name: 'Vidente', emoji: '🔮', team: 'village', weight: 7,
    does: 'Cada noche eliges a un jugador y ves su carta. Cuidado: si los lobos te descubren, irán por ti.',
    wins: 'Ganas con la aldea.',
  },
  bruja: {
    name: 'Bruja', emoji: '🧪', team: 'village', weight: 4,
    does: 'Ves a quién atacaron los lobos. Tienes una poción para salvarlo y otra para envenenar a alguien; cada una se usa una sola vez.',
    wins: 'Ganas con la aldea.',
  },
  cazador: {
    name: 'Cazador', emoji: '🏹', team: 'village', weight: 3,
    does: 'Cuando mueres (de noche o linchado), disparas y te llevas a alguien contigo.',
    wins: 'Ganas con la aldea.',
  },
}

export const SPECIAL_ORDER = ['lobo', 'vidente', 'bruja', 'cazador']

export function roleOf(key) {
  return ROLES[key] || { name: key || '?', emoji: '❔', team: 'village', weight: 0, does: '', wins: '' }
}

// Nombre visible (la base de datos devuelve "Lobo", "Bruja"…) → clave
export function keyFromName(name) {
  return Object.keys(ROLES).find((k) => ROLES[k].name === name) || null
}

/** Baraja sugerida para N jugadores, con las razones */
export function suggestDeck(n) {
  const d = { lobo: 1, vidente: 0, bruja: 0, cazador: 0 }
  const reasons = []
  if (n <= 5) {
    d.vidente = 1
    reasons.push('Con menos de 6 jugadores es más una partida de prueba: 1 lobo y una Vidente para que la aldea tenga una pista.')
  } else if (n === 6) {
    d.cazador = 1
    reasons.push('6 jugadores: 1 lobo (17 %) y un Cazador, que castiga al lobo si se equivoca de víctima.')
  } else if (n === 7) {
    d.vidente = 1
    reasons.push('7 jugadores: 1 lobo y la Vidente para que la aldea pueda investigar.')
  } else if (n === 8) {
    Object.assign(d, { lobo: 2, vidente: 1, cazador: 1 })
    reasons.push('8 jugadores: 2 lobos (25 %), dentro del 20–25 % recomendado.')
    reasons.push('Vidente + Cazador compensan a la aldea sin hacerla demasiado fuerte.')
  } else if (n <= 11) {
    Object.assign(d, { lobo: 2, vidente: 1, bruja: 1, cazador: 1 })
    reasons.push(`${n} jugadores: 2 lobos (${pct(2, n)} %).`)
    reasons.push('Con más de 9 jugadores la aldea necesita información (Vidente) y una segunda oportunidad (Bruja).')
  } else if (n <= 15) {
    Object.assign(d, { lobo: 3, vidente: 1, bruja: 1, cazador: 1 })
    reasons.push(`${n} jugadores: 3 lobos (${pct(3, n)} %), dentro del 20–25 % recomendado.`)
    reasons.push('Vidente + Bruja + Cazador: la aldea tiene información, una poción para salvar y un último disparo.')
    reasons.push('Desde 12 jugadores se elige Alcalde el día 1: ordena el debate y su voto vale doble.')
  } else if (n <= 20) {
    Object.assign(d, { lobo: 4, vidente: 1, bruja: 1, cazador: 1 })
    reasons.push(`${n} jugadores: 4 lobos (${pct(4, n)} %): con grupos grandes la manada necesita más miembros.`)
    reasons.push('Alcalde desde el día 1 para que el debate no sea un caos.')
  } else {
    Object.assign(d, { lobo: 5, vidente: 1, bruja: 1, cazador: 1 })
    reasons.push(`${n} jugadores: 5 lobos (${pct(5, n)} %).`)
    reasons.push('Con tantos jugadores, todos los roles de la aldea ayudan a que la partida no dure demasiado.')
  }
  return { deck: d, reasons }
}

const pct = (k, n) => Math.round((k / n) * 100)

/** Cartas completas (con aldeanos) y balance */
export function analyzeDeck(deck, n) {
  const specials = SPECIAL_ORDER.reduce((s, k) => s + (deck[k] || 0), 0)
  const aldeanos = Math.max(0, n - specials)
  const full = { ...deck, aldeano: aldeanos }
  const score = Object.entries(full).reduce((s, [k, c]) => s + roleOf(k).weight * c, 0)
  const warnings = []
  if (specials > n) warnings.push(`Hay ${specials} roles especiales y solo ${n} jugadores.`)
  if ((deck.lobo || 0) < 1) warnings.push('Debe haber al menos 1 lobo.')
  const wp = n ? (deck.lobo || 0) / n : 0
  if (n >= 6 && (wp < 0.17 || wp > 0.3)) warnings.push(`Los lobos son el ${Math.round(wp * 100)} % (lo recomendado es 20–25 %).`)
  if (deck.vidente && deck.bruja && n < 9) warnings.push('Vidente + Bruja con menos de 9 jugadores hace muy fuerte a la aldea.')

  let level = 'green'
  let text = 'Equilibrado ✨'
  if (Math.abs(score) > 6) {
    level = 'red'
    text = score > 0 ? 'La aldea tiene mucho poder: agrega un Lobo o quita un rol especial' : 'Los lobos son muy fuertes: quita un Lobo o agrega Vidente/Bruja'
  } else if (Math.abs(score) > 3) {
    level = 'yellow'
    text = score > 0 ? 'Se inclina un poco hacia la aldea' : 'Se inclina un poco hacia los lobos'
  }
  return { full, aldeanos, specials, score, level, text, warnings, ok: specials <= n && (deck.lobo || 0) >= 1 }
}

export const PHASES = {
  dealt: { emoji: '🃏', label: 'Reparto', tv: 'Miren su carta en secreto (mantener presionado)', player: 'Mantén presionada tu carta para verla. Que nadie más la vea.' },
  night: { emoji: '🌙', label: 'Noche', tv: 'Todos miren su celular y respondan', player: 'Es de noche. Mira tu celular y responde sin que nadie vea.' },
  night_witch: { emoji: '🧪', label: 'Noche · turno de la bruja', tv: 'La noche continúa… sigan mirando su celular', player: 'La noche continúa…' },
  dawn: { emoji: '☀️', label: 'Amanecer', tv: 'La aldea despierta…', player: 'La aldea despierta. Mira la pantalla.' },
  mayor: { emoji: '🎖️', label: 'Elección de alcalde', tv: 'Voten en su celular: el alcalde vale doble', player: 'Vota quién será el alcalde (su voto vale doble).' },
  debate: { emoji: '🗣', label: 'Debate', tv: '¿Quién es lobo? Los muertos no hablan', player: 'Debatan quién es lobo. Si estás muerto, no hables.' },
  vote: { emoji: '🗳', label: 'Votación', tv: 'Voten en su celular a quién linchar', player: 'Vota a quién linchar. Puedes cambiar tu voto hasta que cierre.' },
  verdict: { emoji: '⚖️', label: 'Veredicto', tv: 'La aldea decidió…', player: 'Mira la pantalla.' },
  duty: { emoji: '🏹', label: 'Últimas palabras', tv: 'El cazador dispara / el alcalde elige sucesor', player: 'Esperen…' },
  finished: { emoji: '🏁', label: 'Fin de la partida', tv: '', player: '' },
}

// Guion que lee el narrador en cada fase
export function narratorScript(phase, v) {
  switch (phase) {
    case 'dealt':
      return 'Cada uno mire su carta en secreto (mantener presionado). Siéntense donde dice su celular. Cuando todos la hayan visto: "La aldea se va a dormir…"'
    case 'night':
      return `🌙 "Noche ${v.night_no}. Todos cierren los ojos… y miren su celular. Lobos: elijan a su víctima. Vidente: elige a quién investigar. Los demás: respondan de quién sospechan, así nadie se delata."`
    case 'night_witch':
      return '🧪 "La bruja despierta… ve a quién atacaron los lobos. ¿Usará sus pociones?" (todos siguen mirando su celular)'
    case 'dawn':
      return '☀️ "La aldea despierta…" Lee en voz alta quién murió (o que no hubo bajas). Los muertos no pueden hablar más.'
    case 'mayor':
      return '🎖️ "Antes de debatir, elijan un alcalde. Voten en su celular. Su voto valdrá doble."'
    case 'debate':
      return '🗣 "¿Quién es lobo? Tienen unos minutos para debatir." Cuando termine el tiempo, pasa a la votación.'
    case 'vote':
      return '🗳 "Voten en su celular a quién linchar." Cuando todos votaron, cierra la votación.'
    case 'verdict':
      return '⚖️ Lee el resultado: a quién lincharon y qué era. Luego: "La aldea se va a dormir…"'
    case 'duty':
      return '🏹 Espera a que el cazador dispare o el alcalde elija sucesor en su celular, y luego avanza.'
    default:
      return ''
  }
}

// Sugerencia de cuántos impostores poner según el número de jugadores (el admin puede cambiarlo)
export function maxImpostors(n) {
  return Math.max(1, Math.floor((n - 1) / 2))
}

export function suggestImpostors(n) {
  let k
  let reason
  if (n <= 6) { k = 1; reason = 'Con pocos jugadores, 1 impostor ya es difícil de encontrar y cada palabra cuenta.' }
  else if (n <= 12) { k = 2; reason = 'Cerca de 1 impostor por cada 5–6 jugadores: se pueden cubrir entre ellos sin que sea imposible encontrarlos.' }
  else if (n <= 20) { k = 3; reason = 'Con grupos grandes, 3 impostores mantienen la tensión: no basta con encontrar a uno.' }
  else { k = 4; reason = 'Con más de 20 jugadores, 4 impostores evitan que la ronda se resuelva demasiado rápido.' }
  k = Math.min(k, maxImpostors(n))
  return { k, reason }
}

export const KIND_LABEL = {
  defense: { short: 'Defensa', long: '🗣 Votación de defensa (nadie sale)', emoji: '🗣' },
  elimination: { short: 'Eliminación', long: '☠️ Votación de eliminación', emoji: '☠️' },
}

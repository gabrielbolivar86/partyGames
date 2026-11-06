import { useLiveRpc } from './useLiveRpc'

// Qué juegos están activos para este invitado (pestañas) y si está "ausente".
export function useMyGames() {
  return useLiveRpc('get_my_games', [
    'wolf_state', 'gift_game', 'impostor_game', 'impostor_votes', 'persona_game',
    'code_hunt', 'costume_contest', 'players',
  ], { debounceMs: 200 })
}

import { formatInt } from '../lib/format'
import { t, type TKey } from '../lib/i18n'

// ONE EFFECT OF A PIECE OF GEAR, IN THE PLAYER'S LANGUAGE (0425, the Gear face). The server serves each effect twice: as its English
// words (`effects`, public.stat_words) and as figures (`fx`: stat, delta). A Korean screen cannot print the English words, so this
// words the figure with the game's own stat words (dict/ship.ts). The number is the served delta: whole for every stat, two places
// for speed (as public.stat_words prints it). tests/gearNames.spec.ts fails when a starter piece moves a stat this map does not name.

/** The served stat code → the dictionary word it is printed with. */
export const GEAR_STAT_WORD: Readonly<Record<string, TKey>> = {
  attack: 'ship.attack',
  reach: 'ship.reach',
  armour: 'ship.armour',
  handling: 'ship.handling',
  durability: 'ship.hull',
  speed: 'ship.knots',
  hold: 'ship.tons',
}

const MINUS = '−'

/** "+30 Attack", "−0.69 knots", "+80 Hull" — or, for a stat this map does not name, null (the caller prints the served words). */
export function gearEffectWord(stat: string, delta: number): string | null {
  const key = GEAR_STAT_WORD[stat]
  if (!key) return null
  const sign = delta < 0 ? MINUS : '+'
  const n = Math.abs(delta)
  const figure = stat === 'speed' ? n.toFixed(2) : formatInt(n)
  return `${sign}${figure} ${t(key)}`
}

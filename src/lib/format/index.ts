// The single import surface for formatting. Screens import from 'src/lib/format', never from the
// two modules directly, so there is exactly one place to look for "how does this game print a
// number" and exactly one place a new rule can be added.
export {
  MINUS,
  formatInt,
  formatFixed,
  formatDucats,
  formatDucatsDelta,
  formatUnitPrice,
  formatTuns,
  formatNm,
  formatKnots,
  formatPct,
  formatPctPoints,
  formatPctDelta,
  formatOfTotal,
} from './numbers'
export {
  TIME_COMPRESSION,
  REAL_MS_PER_VOYAGE_DAY,
  REAL_MS_PER_GAME_MONTH,
  voyageDaysToRealMs,
  realMsToVoyageDays,
  formatVoyageDays,
  formatRealDuration,
  formatRealShort,
  formatCountdown,
  formatTwoClocks,
  formatRelative,
  formatClock,
  seasonOfMonth,
  gameDate,
  formatGameDate,
  type Season,
  type GameDate,
} from './time'

import { worldCaptainStats, type CaptainStatsView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

// ONE CAPTAIN'S SHEET (0337, docs/WORLD_POWERS.md 2.4): `useNavyShipCard`'s doorway for her. Read when her card opens, and again on the world's beat while it
// stays open, so a trait chosen or a promotion lands on the sheet as it lands on the card. The answer is the server's whole sheet: this derives nothing, and
// a captain the server does not know (a null answer) reads as no sheet, never as a sheet of zeros. `loading` is the first ask only; the beat's re-ask is silent.
export function useCaptainStats(code: string | null): ServedRead<CaptainStatsView | null> {
  return useServedRead<CaptainStatsView | null>(code, () => worldCaptainStats(code ?? ''), { name: 'worldCaptainStats' })
}

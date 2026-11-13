// A SEA THAT IS CLOSED TO HER, AS THE SERVER SAID IT — the one reading of the sea rule's answer.
//
// `public.sea_refusal` (0215) is the only place a title or a wave is compared with what a sea asks. It answers a
// refusal `E_SEA_CLOSED` whose figures name the sea, its two asks, her two figures and (0396) which of the two is
// short. The same figures arrive four ways: on a refused order or dry run (the envelope, `Refusal.sea`), on a Trade
// board row (`sea.refusal`), on a leg of `world.route_legs` (`shut`) and on a standing route that stopped. Every
// screen reads them HERE and prints them with `seaWallWords` (components/ui): nothing compares a number on the
// client, so a wall cannot say one thing on the Map and another on Trade.

export const SEA_CLOSED = 'E_SEA_CLOSED'

export interface SeaWall {
  /** The zone's code (`NOR-MID`) and its served English name. */
  zone: string
  zoneName: string
  needsTitle: number
  needsWave: number
  /** Hers; null for a fleet with no hull, or when the server judged the title alone. */
  title: number | null
  wave: number | null
  /** 0396: which ask is above hers. Null on a world before 0396: the wall then prints both asks beside both of hers. */
  shortTitle: boolean | null
  shortWave: boolean | null
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const flag = (v: unknown): boolean | null => (typeof v === 'boolean' ? v : null)

/** The sea rule's figures as a wall, or null for anything that is not exactly their shape. */
export function readSeaWall(raw: unknown): SeaWall | null {
  if (!raw || typeof raw !== 'object') return null
  const f = raw as Record<string, unknown>
  const needsTitle = num(f.needs_title)
  const needsWave = num(f.needs_wave)
  if (typeof f.zone !== 'string' || f.zone === '' || needsTitle === null || needsWave === null) return null
  return {
    zone: f.zone,
    zoneName: typeof f.zone_name === 'string' && f.zone_name !== '' ? f.zone_name : f.zone,
    needsTitle,
    needsWave,
    title: num(f.title),
    wave: num(f.wave),
    shortTitle: flag(f.short_title),
    shortWave: flag(f.short_wave),
  }
}

/** The same figures off an exception's DETAIL (cmd.refuse puts the refusal's figures there as JSON). */
export function readRawSeaWall(details: unknown): SeaWall | null {
  if (typeof details !== 'string' || details === '' || details[0] !== '{') return null
  try {
    return readSeaWall(JSON.parse(details))
  } catch {
    return null
  }
}

/** The wall a refusal carries, however it arrived: the envelope's own (`sea`), or a served refusal's figures. */
export function seaWallOf(refusal: { code?: string | null; sea?: SeaWall | null; figures?: unknown } | null | undefined): SeaWall | null {
  if (!refusal) return null
  if (refusal.sea) return refusal.sea
  if (refusal.code !== SEA_CLOSED) return null
  return readSeaWall(refusal.figures)
}

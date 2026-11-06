import { busyUntilMs, inBattle, voyageEtaMs } from '../../domain/fleet'
import { formatCountdown, formatRealShort, instantMs } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { t } from '../../lib/i18n'

// WHEN SHE IS DUE — the countdown the fleet row and the fleet fold both print. WHERE she is, in
// words, is `domain/fleet`'s `whereLine` (this file used to carry a second spelling of it).
//
// Pure. Every figure is the server's: `port` is a CODE and null at sea, `anchor` is the bare point
// of water she is holding at (0039), `voyage.to` / `voyage.dest_point` is where she is bound, and
// the instant a countdown reads is `eta` or `busy_until`, both ISO strings parsed once in
// domain/fleet. Nothing here settles a voyage: past the instant the word is "due", never "arrived",
// because the next read is what lands her.

/** The countdown — to her arrival, or to the moment a busy fleet comes free. Null when nothing is
 *  counting; "due" once the instant has passed and the server has not yet been asked. */
export function fleetDue(fleet: FleetView, nowMs: number): string | null {
  // 0237 (docs/CLOSED_ECONOMY.md §4c): in her port time — "Ready in 0:42" (a live countdown; served only while in it)
  const ready = fleet.voyage ? null : instantMs(fleet.ready_at)
  if (ready !== null && ready > nowMs) return t('domain.readyIn', { t: formatCountdown(ready - nowMs) })
  // 0323 (docs/WORLD_POWERS.md 5.2): in a battle, in port or at sea, the clock on her card is the battle's. Past it she is due, or sailing on to her arrival.
  const until = inBattle(fleet) ? busyUntilMs(fleet) : null
  if (until !== null && until > nowMs) {
    // 0333: while the navy is still on her way, the card says so. Once there she is simply in the fight.
    const navy = instantMs(fleet.navy_at)
    const clock = t('domain.inBattle', { t: formatCountdown(until - nowMs) })
    return navy !== null && navy > nowMs ? `${clock} · ${t('domain.navyArrives', { t: formatCountdown(navy - nowMs) })}` : clock
  }
  const at = voyageEtaMs(fleet) ?? busyUntilMs(fleet)
  if (at === null) return null
  return nowMs >= at ? t('domain.due') : formatRealShort(at - nowMs)
}

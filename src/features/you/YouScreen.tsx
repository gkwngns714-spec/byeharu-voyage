import { Bar, Figure, Row, Sheet, SheetSection } from '../../components/ui'
import { formatInt } from '../../lib/format'
import type { FleetView, LevelTrack, PlayerHouse } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { YourCaptains } from '../../live/YourCaptains'
import { tabWord } from '../../app/navTabs'
import { useLocale, useT } from '../../lib/i18n'

// YOU — the owner, row 181 (2026-10-20): *"Create a tab for personal info, such as my level, my
// ships, captains, achievements, levels etc."*
//
// THREE SECTIONS, AND EVERY ONE OF THEM ALREADY EXISTED SOMEWHERE ELSE. Nothing here is read that
// was not read before and nothing is computed: the world read brings the house (with its three
// level tracks) and the fleets (with their hulls), and the captains are the ONE captains face
// (src/live/YourCaptains.tsx, `world.captains`). This tab is composition, which is why it sits in
// the Cabin: it consults, and it commands nothing (navTabs.ts says what that group is for).
//
//   Levels         the three tracks, as Bars. MOVED HERE FROM PROFILE, not copied: §6 put them
//                  there because there was no personal tab, and the owner has now asked for one by
//                  name. Two screens drawing one ladder is two answers to "what level am I".
//   Your ships     EVERY hull you own, in one list, with the fleet she sails in. FLEETS lists
//                  FLEETS — where each one is, her stores, her hold, her hull — and a hull inside
//                  it sits behind a fold, so "what do I own" had no page. This is that page: a
//                  different reading of rows already served, not a second copy of FLEETS'.
//   Your captains  the roster, MOVED from FLEETS for the reason the levels moved — the owner names
//                  captains as personal info, and one list belongs in one place.
//
// ACHIEVEMENTS ARE NOT HERE, and that is deliberate (decided by default, 2026-10-20): there are no
// achievements in this game yet — no table, no read, nothing to count. ProfileScreen's own header
// records what happened the last time a screen printed a feature that did not exist ("`Not in the
// game yet` (three bullets of unbuilt features) → deleted. A roadmap is this repository's, not the
// player's"), so this tab says nothing about them. The day they exist, they are a section here.

export function YouScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/you')
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return <YouBody title={title} />
}

function YouBody({ title }: { title: string }) {
  const t = useT()
  const player = useWorld((s) => s.player)
  const fleets = useWorld((s) => s.fleets)

  return (
    <Sheet title={title} data-testid="you">
      {player === null ? (
        <SheetSection surface>
          <Row label={t('you.noCompany')} tone="muted" hairline={false} data-testid="you-no-company" />
        </SheetSection>
      ) : (
        <Levels player={player} />
      )}
      <Ships fleets={fleets} />
      {/* 0160: the one captains face — her grade, the traits she uses, the cabin she sits in. */}
      <YourCaptains />
    </Sheet>
  )
}

/** THE THREE TRACKS (0069), as Bars — the hand-off this tab took from Profile. */
function Levels({ player }: { player: PlayerHouse }) {
  const t = useT()
  return (
    <SheetSection heading={t('you.levels')} surface data-testid="levels">
      <Track name={t('you.trading')} track={player.levels.trading} />
      <Track name={t('you.exploration')} track={player.levels.exploration} />
      {/* COMBAT READS NOTHING AND IS NOT DRAWN AS A TRACK. 0069 serves it with `playable: false` on
          purpose — there is no fighting at sea in this game yet (0035) — and a bar at level 1 of an
          unbuilt track would make it look built. The server's flag decides: the day it flips, this
          row becomes the third bar with no edit here. Until then the row says what it waits on. */}
      {player.levels.combat.playable ? (
        <Track name={t('you.combat')} track={player.levels.combat} last />
      ) : (
        <Row
          data-testid="combat-waits"
          label={t('you.combat')}
          tone="muted"
          hairline={false}
          value={<span className="text-t-caption text-ink-faint">{t('you.noFighting')}</span>}
        />
      )}
    </SheetSection>
  )
}

/** The cap of the ONE level curve, `public.level_from_points` (0069:111): floored at 1, capped at
 *  20. Mirrored here for DISPLAY ONLY, the way `TIME_COMPRESSION` mirrors a served knob in
 *  src/lib/format/time.ts — the server does not serve the cap, and a bar needs an end. When
 *  `world.snapshot().config` carries it, this constant goes and the bar reads the served value. */
const LEVEL_CAP = 20

/** One level track as §6 draws it: the name, the bar of the ladder, the level as the figure. A
 *  countable Bar (`of`) rather than a percentage: a level is a rung, not a proportion. */
function Track({ name, track, last = false }: { name: string; track: LevelTrack; last?: boolean }) {
  const t = useT()
  return (
    <Row data-testid="level-track" label={name} value={<Figure value={formatInt(track.level)} />} hairline={!last}>
      <Bar value={track.level} of={LEVEL_CAP} label={t('you.levelOf', { name })} className="mt-2" />
    </Row>
  )
}

/** EVERY HULL YOU OWN, with the fleet she sails in. The served rows, flattened — a flagship says
 *  so, because she is the one hull this game promises never to lose (DESIGN §C.6). */
function Ships({ fleets }: { fleets: readonly FleetView[] }) {
  const t = useT()
  const ships = fleets.flatMap((fleet) => fleet.ships.map((ship) => ({ ship, fleet })))
  return (
    <SheetSection
      heading={t('you.ships')}
      trailing={
        ships.length === 0 ? undefined : (
          <span className="text-t-caption text-ink-faint" data-testid="you-ships-count">
            {t('you.shipsCount', { ships: formatInt(ships.length), fleets: formatInt(fleets.length) })}
          </span>
        )
      }
      surface
      data-testid="you-ships"
    >
      {ships.length === 0 ? (
        <Row label={t('you.noShips')} tone="muted" hairline={false} data-testid="you-no-ships" />
      ) : (
        ships.map(({ ship, fleet }, i) => (
          <Row
            key={ship.id}
            label={ship.name}
            value={<span className="text-t-caption text-ink-muted">{fleet.name}</span>}
            hairline={i < ships.length - 1}
            data-testid="you-ship"
          >
            <span className="block text-t-caption text-ink-faint">
              {[ship.class, ship.is_flagship ? t('you.flagship') : null].filter(Boolean).join(' · ')}
            </span>
          </Row>
        ))
      )}
    </SheetSection>
  )
}

import {
  Badge,
  Card,
  CardHeader,
  Gauge,
  Notice,
  PageHeader,
  Screen,
  StatRow,
  fineClass,
} from '../../components/ui'
import { formatDucats, formatInt } from '../../lib/format'
import { useWorld } from '../../live/worldStore'
import { ReadAgain, WorldFailed, WorldLoading } from '../../live/WorldGate'

// RANK — I.4: "the Ledger is not a UI convenience — it is the source of truth from which rank is
// computed." That sentence is the whole design of this screen, and it is also why the screen it
// promises cannot be drawn in full yet.
//
// ── WHAT IS MISSING, PRECISELY ──────────────────────────────────────────────────────────────────
// There is no standings RPC and no player row a client may read. `world.snapshot()` carries the
// WORLD — ports, legs, goods, ship classes, config, verbs — and no player at all; `world.ledger()`
// carries this house's own events and its purse. So the client can say what YOU are worth. It
// cannot say what that is worth RELATIVE to anyone, because no other house's figures cross the
// wire and nothing in the chain computes a table. A leaderboard drawn from one row is not one.
//
// This was an 18-line skeleton naming three things that would live here one day. It now shows the
// real figures a standing would be computed FROM — every one of them served — and states the
// missing half as a fact rather than as a promise. A player can read their own position even while
// there is nothing to compare it against.
//
// ── FAME IS THE SERVER'S NOW, AND THE WINDOW PROBLEM WENT WITH IT ───────────────────────────────
// This screen used to count voyages and turnover out of `world.events` — ONE PAGE of the ledger,
// the default 50 — and had to print how many entries it had looked at, because the total was not a
// lifetime total.
//
// 0014 made fame a server-side reading of the WHOLE record: `world.player()` returns trade fame,
// exploration fame and ports reached, derived on every call. So the client stops counting — and as
// of 2026-08-22 it counts NOTHING: the last derived figure, a tally of trades in the page this
// screen happened to hold, is gone with the paragraph that had to explain it.
//
// The rule that made this worth doing is the one this project keeps: a figure computed in two
// places is two authorities for it. The ledger is the source of truth from which rank is computed
// (I.4), and now exactly one thing computes it.
//
// ── WHAT THE PLAYER IS TOLD, AND WHAT STAYS IN THIS COMMENT (2026-08-22) ────────────────────────
// This screen used to end with a bulleted list headed "What a standing needs first", naming a
// players table, a settled net worth, first-reached ports and a season boundary. Every line of it
// was true and none of it was the player's business: it is MY backlog, printed on their screen,
// and the same pass found `(0014)` in the Fame card — a migration number, which is provenance for
// a developer and noise to a captain (docs/UI_DIRECTION.md §4 rule 4).
//
// THE HONESTY IS NOT THE BACKLOG. What a player must know is that no table of captains exists and
// that this is the game's state rather than a failed read — that sentence stays, in their words.
// What they need never know is which migration would add one, so it lives here:
//
//   · no players table a client may read — `world.snapshot()` carries the world and no houses
//   · no settled net worth — purse, plus hulls, plus cargo at an agreed valuation
//   · ports FIRST reached are not recorded; fame counts distinct arrivals, which is a different
//     claim on the world
//   · no season boundary, so a table would be of all time rather than of something
//
// And the same pass deleted this screen's last derived figure — "N of the M entries on this page
// are trades". It was ungrammatical ("0 of the 1 entries"), it was a fact about the LEDGER's
// paging rather than about the house, and the Ledger already prints exactly that count on the
// screen that owns it. Nothing above it is paged: `world.player()` reads the whole record. So the
// line disclosed no limitation, and deleting the count deleted the caveat that existed only to
// stop it being misread.

export function RankScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') {
    return <WorldFailed eyebrow="Standings" title="Rank" refusal={fatal} />
  }
  if (phase !== 'ready') {
    return (
      <WorldLoading
        eyebrow="Standings"
        title="Rank"
        subtitle="Where you stand among the captains."
        panels={3}
      />
    )
  }
  return <RankBody />
}

function RankBody() {
  // The snapshot, not `snapshot?.config` — a selector must return something stable, and reaching
  // one level deeper is free here because the snapshot object is replaced only when the world is
  // reopened (worldStore.ts rule 4, 'the one thing to watch').
  const snapshot = useWorld((s) => s.snapshot)
  const ducats = useWorld((s) => s.ducats)
  const house = useWorld((s) => s.player)
  const config = snapshot?.config

  // NOTHING ON THIS SCREEN IS DERIVED FROM THE LEDGER ANY MORE. The last figure that was — a count
  // of trades in the page this screen happened to hold — was deleted; see the header note.
  // `world.player()` reads the whole record, so every number below is a lifetime figure.

  // SERVED, not folded — `world.player()` counts them (migration 0014:140-141). FleetsScreen was
  // folding the roster for the same two figures; both read the house now.
  const shipCount = house?.ships ?? null
  const fleetCount = house?.fleets ?? null
  const fame = house?.fame ?? null

  return (
    <Screen>
      <PageHeader
        eyebrow="Standings"
        title="Rank"
        explain="Your own record, kept by the game and worked out fresh from your ledger every time you look. There is no table of captains yet — the game does not keep one, and no other house's figures are shown to you."
        actions={<ReadAgain />}
      />

      <Card
        head={
          <CardHeader
            flush
            title={house?.company_name ?? 'The house'}
            aside={
              house?.nation ? <Badge tone="neutral">{house.nation_name ?? house.nation}</Badge> : null
            }
          />
        }
      >
        <dl className="space-y-2">
          <StatRow
            label="Purse"
            value={ducats === null ? '—' : formatDucats(ducats)}
            hint="The game's own figure, checked against your ledger every time it is read. It is where a standing by wealth would start."
          />
          <StatRow
            label="Fleets"
            value={`${fleetCount === null ? '—' : formatInt(fleetCount)} / ${config ? formatInt(config.fleet_max) : '—'}`}
            /* `fleet_max` was named here by its config key — provenance for a developer, and to a
               captain a word from nowhere. What they need is what the second figure MEANS. */
            hint="The second figure is the same for every house in the world. It is a limit, not a rank, and nothing you do raises it."
          />
          <StatRow
            label="Ships"
            value={`${shipCount === null ? '—' : formatInt(shipCount)} / ${config ? formatInt(config.ship_max) : '—'}`}
          />
        </dl>

        {/* The gauge needs a COUNT; an unread house has none, and drawing a zero-length gauge
            would be inventing one. It simply does not draw. */}
        {config && shipCount !== null && (
          <div className="mt-3 flex items-center gap-3">
            <Gauge
              value={shipCount}
              max={config.ship_max}
              segments={config.ship_max}
              tone={shipCount >= config.ship_max ? 'warning' : 'accent'}
              label={`${shipCount} of ${config.ship_max} ships`}
            />
            <span className={fineClass()}>
              {shipCount >= config.ship_max ? 'every berth taken' : 'hulls the house may still own'}
            </span>
          </div>
        )}
      </Card>

      <Card head={<CardHeader flush title="Fame" />}>
        {/* The provenance a player needs is "it is re-read from your ledger, not banked" — which
            is why the figure can never quietly disagree with the record. The migration that made
            it so was named here as "(0014)"; that is a fact about this repository, not about the
            game, and docs/UI_DIRECTION.md §4 rule 4 keeps it off the screen. */}
        <p className="mb-3 text-xs text-ink-muted">
          Counted from your whole ledger every time you open this screen — never a running total
          kept aside, so it cannot drift away from what you actually did.
        </p>
        <dl className="space-y-2">
          <StatRow
            label="Trade fame"
            value={fame ? formatInt(fame.trade) : '—'}
            hint="One point per 100 ducats TURNED OVER on a purchase or a sale. Turnover, not profit: the profit is already the purse, and paying fame for it too would score one thing twice."
          />
          <StatRow
            label="Exploration fame"
            value={fame ? formatInt(fame.exploration) : '—'}
            hint="25 for each DISTINCT port you have arrived at. A port is reached once; sailing between two of them for ever is trade, not exploration."
          />
          <StatRow label="Total" value={fame ? formatInt(fame.total) : '—'} />
          <StatRow label="Ports reached" value={fame ? formatInt(fame.ports_reached) : '—'} />
          <StatRow label="Turned over" value={fame ? formatDucats(fame.turnover) : '—'} />
        </dl>
      </Card>

      {/* THE LIMITATION STAYS; THE BACKLOG GOES. A player must be told that no table of captains
          exists, and told that it is the game's state and not a slow or broken read — otherwise
          this screen looks like a leaderboard that failed to load. What they must NOT be told is
          which four pieces of server work would build one; that list is in this file's header. */}
      <Card head={<CardHeader flush title="The table of captains" />}>
        <Notice tone="neutral" className="text-xs">
          No table of captains exists yet, and nothing here has failed to load. Other captains keep
          their own books and none of their figures are shown to you, so there is nobody to place
          you against. What you can read is above, and it is your whole record.
        </Notice>
      </Card>
    </Screen>
  )
}

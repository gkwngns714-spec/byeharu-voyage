import { useMemo } from 'react'
import {
  Badge,
  Card,
  CardHeader,
  Gauge,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  StatRow,
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
// exploration fame and ports reached, derived on every call. So the client stops counting. What
// remains derived here is only what fame does not cover — how many entries this page holds — and
// it still says so.
//
// The rule that made this worth doing is the one this project keeps: a figure computed in two
// places is two authorities for it. The ledger is the source of truth from which rank is computed
// (I.4), and now exactly one thing computes it.

export function RankScreen() {
  const world = useWorld()

  if (world.phase === 'failed') {
    return <WorldFailed eyebrow="Standings" title="Rank" refusal={world.fatal} />
  }
  if (world.phase !== 'ready') {
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
  const world = useWorld()
  const events = world.events
  const fleets = world.fleets
  const config = world.snapshot?.config

  // WHAT THE SERVER DOES NOT COUNT. Fame, turnover and ports reached are `world.player()`'s now;
  // the only thing left to derive is how many trades sit in the page this screen happens to hold,
  // which is a fact about the PAGE and not about the house.
  const tradesOnPage = useMemo(
    () => events.filter((e) => e.kind === 'BOUGHT' || e.kind === 'SOLD').length,
    [events],
  )

  const shipCount = fleets.reduce((n, f) => n + f.ships.length, 0)
  const house = world.player
  const fame = house?.fame ?? null

  return (
    <Screen>
      <PageHeader
        eyebrow="Standings"
        title="Rank"
        explain="Your own record, computed from the ledger the server keeps. There is no table of captains yet: nothing in the chain computes one, and no other house's figures cross the wire."
        actions={<ReadAgain world={world} />}
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
            value={world.ducats === null ? '—' : formatDucats(world.ducats)}
            hint="The server's figure, reconciled against the ledger on every read. It is the number a net-worth standing would start from."
          />
          <StatRow
            label="Fleets"
            value={`${formatInt(fleets.length)} / ${config ? formatInt(config.fleet_max) : '—'}`}
            hint="fleet_max is a WORLD knob, the same for every house — not a rank, and not something you have earned."
          />
          <StatRow
            label="Ships"
            value={`${formatInt(shipCount)} / ${config ? formatInt(config.ship_max) : '—'}`}
          />
        </dl>

        {config && (
          <div className="mt-3 flex items-center gap-3">
            <Gauge
              value={shipCount}
              max={config.ship_max}
              segments={config.ship_max}
              tone={shipCount >= config.ship_max ? 'warning' : 'accent'}
              label={`${shipCount} of ${config.ship_max} ships`}
            />
            <span className="font-mono text-[11px] text-ink-faint">
              {shipCount >= config.ship_max ? 'every berth taken' : 'hulls the house may still own'}
            </span>
          </div>
        )}
      </Card>

      <Card head={<CardHeader flush title="Fame" />}>
        <p className="mb-3 text-xs text-ink-muted">
          Derived by the server from the whole record every time it is asked (0014) — never a stored
          counter, so it cannot drift from the ledger it is computed from.
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

        <p className="mt-3 font-mono text-[11px] text-ink-faint">
          {formatInt(tradesOnPage)} of the {formatInt(events.length)} entries on this page are
          trades. That count is about the PAGE; the fame above is about the house.
        </p>
      </Card>

      <Card head={<CardHeader flush title="The table of captains" />}>
        <Notice tone="neutral" className="text-xs">
          There is no standing to show, and this is not late data or a failed read: nothing in the
          chain computes a table, and no other house&apos;s figures are served to a client. Both are
          server work rather than screen work.
        </Notice>
        <div className="mt-3">
          <SectionLabel>What a standing needs first</SectionLabel>
          <ul className="space-y-1 text-sm text-ink-muted">
            <li>· A players table a client may read at all — the snapshot carries none today.</li>
            <li>· A settled net worth: purse, plus hulls, plus cargo at some agreed valuation.</li>
            <li>· Ports first reached — a claim on the world, which has to be recorded once.</li>
            <li>· A season boundary, so that a table is of something rather than of all time.</li>
          </ul>
        </div>
      </Card>
    </Screen>
  )
}

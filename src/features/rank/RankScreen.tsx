import { useMemo } from 'react'
import {
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
// ── THE DERIVED COUNTS ARE HONEST ABOUT THEIR WINDOW ────────────────────────────────────────────
// Voyages, ports and trades are counted from `world.events`, which is ONE PAGE of the ledger (the
// store fetches the default 50). That is not the house's lifetime total, and this screen must not
// print it as one — so it says how many entries it looked at. The purse, the fleets and the ships
// are exact, because those are served whole.

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

  const tally = useMemo(() => {
    let voyages = 0
    let trades = 0
    let earned = 0
    let spent = 0
    const ports = new Set<string>()
    for (const e of events) {
      if (e.kind === 'VOYAGE_REPORT') {
        voyages += 1
        // VOYAGE_REPORT carries `to` as a port CODE. Arriving somewhere is the only landfall the
        // payload set records; nothing else in it names a port you have reached.
        const to = e.payload['to']
        if (typeof to === 'string') ports.add(to)
      }
      if (e.kind === 'BOUGHT' || e.kind === 'SOLD') trades += 1
      const d = e.ducats_delta
      if (typeof d === 'number') {
        if (d > 0) earned += d
        else spent += -d
      }
    }
    return { voyages, trades, earned, spent, ports: ports.size }
  }, [events])

  const shipCount = fleets.reduce((n, f) => n + f.ships.length, 0)

  return (
    <Screen>
      <PageHeader
        eyebrow="Standings"
        title="Rank"
        explain="Your own record, computed from the ledger the server keeps. There is no table of captains yet: nothing in the chain computes one, and no other house's figures cross the wire."
        actions={<ReadAgain world={world} />}
      />

      <Card head={<CardHeader flush title="The house" />}>
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

      <Card head={<CardHeader flush title="What is on the record" />}>
        <p className="mb-3 text-xs text-ink-muted">
          Counted from the {formatInt(events.length)} most recent ledger{' '}
          {events.length === 1 ? 'entry' : 'entries'} — not the house&apos;s lifetime. The chain
          keeps every entry; this screen has read one page of them.
        </p>
        <dl className="space-y-2">
          <StatRow label="Voyages completed" value={formatInt(tally.voyages)} />
          <StatRow label="Ports reached" value={formatInt(tally.ports)} />
          <StatRow label="Trades struck" value={formatInt(tally.trades)} />
          <StatRow
            label="Taken in"
            value={formatDucats(tally.earned)}
            hint="The sum of the positive movements in the entries read. It is gross, not income: wages are paid without writing an entry of their own."
          />
          <StatRow label="Paid out" value={formatDucats(tally.spent)} />
        </dl>
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

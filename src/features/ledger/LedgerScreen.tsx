import { useMemo, useState } from 'react'
import {
  Badge,
  Card,
  EmptyState,
  Icon,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
} from '../../components/ui'
import {
  formatClock,
  formatDucats,
  formatDucatsDelta,
  formatGameDate,
  formatRelative,
  gameDate,
} from '../../lib/format'
import { useWorld } from '../../fixtures/useWorld'
import type { LedgerEntry, LedgerKind, ReportParagraph } from '../../fixtures/types'

// LEDGER — E.6. "The narrative organ of the game. This is where combat lives, as prose."
//
// TWO THINGS ARE TRUE OF THIS SCREEN AT ONCE, and both matter:
//
//   1. It is a LEDGER. Reverse-chronological, every row an immutable event, every money movement
//      carrying the balance it produced. I.4: "the Ledger is not a UI convenience — it is the
//      source of truth from which rank is computed." So the running balance is DISPLAYED, not
//      inferred, and a reader can walk the column and check that it adds up. It does: the fixture
//      opens at 9,400 and closes at the player's 8,000.
//
//   2. It is the AFTER-ACTION REPORT. B.6: "Nothing here renders. Everything here writes." A storm
//      is not a bar that went down; it is a paragraph about a night under bare poles off Cape St
//      Vincent, and the hull figure is a line UNDER the paragraph, not instead of it. Every hazard
//      report is rendered as prose in the serif face — the log's voice — because the sentence is
//      the game and the number is the receipt.
//
// No commands. No filters that hide money. Nothing animates except a newly-arrived line.

const KINDS: readonly (LedgerKind | 'all')[] = ['all', 'VOYAGE', 'TRADE', 'PORT', 'MARKET']

export function LedgerScreen() {
  const model = useWorld()
  const [filter, setFilter] = useState<LedgerKind | 'all'>('all')

  // E.6 is reverse-chronological: the newest thing that happened to you, first.
  const entries = useMemo(
    () => [...model.world.ledger].sort((a, b) => b.atMs - a.atMs),
    [model.world.ledger],
  )
  const shown = entries.filter((e) => filter === 'all' || e.kind === filter)
  const unread = entries.filter((e) => e.unread).length

  const date = gameDate(model.nowMs, model.world.calendarEpochMs, model.world.epochYear)
  const net = entries.reduce((sum, e) => sum + e.ducatsDelta, 0)

  return (
    <Screen>
      <PageHeader
        eyebrow="Record"
        title="Ledger"
        subtitle="Everything that happened, in the order it happened."
        actions={
          <span className="font-mono text-sm text-accent">{formatDucats(model.world.player.ducats)}</span>
        }
      />

      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-1.5">
            {KINDS.map((k) => (
              <button
                key={k}
                type="button"
                onClick={() => setFilter(k)}
                className={[
                  'min-h-11 rounded-md px-3 font-mono text-xs uppercase tracking-wider transition',
                  k === filter
                    ? 'bg-accent text-app'
                    : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
                ].join(' ')}
              >
                {k === 'all' ? 'all' : k.toLowerCase()}
              </button>
            ))}
          </div>
          <div className="text-right font-mono text-[11px] text-ink-faint">
            <div>{formatGameDate(date)}</div>
            <div>
              {unread} unread · window net {formatDucatsDelta(net)}
            </div>
          </div>
        </div>
      </Card>

      {shown.length === 0 ? (
        <EmptyState icon={<Icon name="ledger" size={28} />} title="Nothing under that filter" />
      ) : (
        <div className="space-y-3">
          {shown.map((entry) => (
            <Entry key={entry.id} entry={entry} nowMs={model.nowMs} />
          ))}
        </div>
      )}

      <Notice tone="neutral" className="text-xs">
        The balance column runs: every entry is the one before it plus its own movement. It opens at{' '}
        {formatDucats(entries[entries.length - 1].balanceAfter - entries[entries.length - 1].ducatsDelta)}{' '}
        and closes at {formatDucats(model.world.player.ducats)} — which is what the Command tab
        shows you can spend.
      </Notice>
    </Screen>
  )
}

function Entry({ entry, nowMs }: { entry: LedgerEntry; nowMs: number }) {
  const money = entry.ducatsDelta !== 0
  return (
    <Card tone={entry.report ? 'accent' : 'default'} className="bv-fade-in">
      <div className="mb-2 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span aria-hidden className={entry.unread ? 'text-accent' : 'text-ink-faint'}>
          {entry.unread ? '●' : '○'}
        </span>
        <span className="font-mono text-xs text-ink-faint">{formatClock(entry.atMs)}</span>
        <span className="font-mono text-xs uppercase tracking-wider text-ink">{entry.actor}</span>
        <Badge tone={kindTone(entry.kind)}>{entry.kind}</Badge>
        <span className="ml-auto font-mono text-[11px] text-ink-faint">
          {formatRelative(entry.atMs, nowMs)}
        </span>
      </div>

      <p className="font-serif text-base text-ink">{entry.headline}</p>

      {entry.report && (
        <div className="mt-3 space-y-3 border-l-2 border-accent/30 pl-3">
          {entry.report.map((para) => (
            <Paragraph key={`${entry.id}-${para.day}`} para={para} />
          ))}
        </div>
      )}

      {entry.lines && entry.lines.length > 0 && (
        <div className="mt-3">
          <SectionLabel>Ledger</SectionLabel>
          <dl className="space-y-1">
            {entry.lines.map((line) => (
              <div key={line.label} className="flex items-baseline justify-between gap-3 text-sm">
                <dt className="text-ink-faint">{line.label}</dt>
                <dd className="text-right font-mono text-ink-muted">{line.value}</dd>
              </div>
            ))}
          </dl>
        </div>
      )}

      <div className="mt-3 flex flex-wrap items-baseline justify-between gap-2 border-t border-edge pt-2">
        <span
          className={[
            'font-mono text-sm',
            money ? (entry.ducatsDelta > 0 ? 'text-success' : 'text-danger') : 'text-ink-faint',
          ].join(' ')}
        >
          {money ? formatDucatsDelta(entry.ducatsDelta) : 'no movement'}
        </span>
        <span className="font-mono text-xs text-ink-muted">
          balance {formatDucats(entry.balanceAfter)}
        </span>
      </div>
    </Card>
  )
}

function Paragraph({ para }: { para: ReportParagraph }) {
  return (
    <div>
      <p className="mb-1 font-mono text-[11px] uppercase tracking-wider text-ink-faint">
        day {para.day}
        {para.hazard !== 'CLEAR' && (
          <span className={`ml-2 ${hazardClass(para.hazard)}`}>{para.hazard}</span>
        )}
      </p>
      {/* Serif, larger, leading-relaxed: this is the one place in the game that is READING rather
          than scanning, and it is typeset to be read. */}
      <p className="font-serif text-[15px] leading-relaxed text-ink-muted">{para.text}</p>
    </div>
  )
}

function hazardClass(hazard: ReportParagraph['hazard']): string {
  switch (hazard) {
    case 'STORM':
      return 'text-danger'
    case 'PIRATES':
      return 'text-warning'
    case 'CALM':
    case 'SHORT_RATIONS':
      return 'text-ink-muted'
    default:
      return 'text-ink-faint'
  }
}

function kindTone(kind: LedgerKind) {
  switch (kind) {
    case 'VOYAGE':
      return 'accent' as const
    case 'TRADE':
      return 'success' as const
    case 'MARKET':
      return 'warning' as const
    default:
      return 'neutral' as const
  }
}

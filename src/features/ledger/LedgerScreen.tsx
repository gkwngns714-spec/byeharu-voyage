import { Fragment, useMemo, useState } from 'react'
import {
  Card,
  Figure,
  IconDisc,
  ListHeading,
  ListPanel,
  PageSplit,
  RankBars,
  Row,
  Segmented,
  Sheet,
  SignedBars,
  StatCell,
  Tray,
  deltaTone,
  type IconName,
  type RankRow,
  type TrayDetent,
} from '../../components/ui'
import { MINUS, formatClock, formatDate, formatDucatsDelta, formatInt } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { LedgerEvent } from '../../lib/rpc'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { headline, payloadFights, payloadLines } from './headline'
import { FightLog } from '../../live/FightLog'
import { FACES, FACE_OF, biggestOf, byDay, kindsOf, moneyOf, onFace, type Face } from './ledgerFigures'
import { useLocale, useT } from '../../lib/i18n'
import { tabWord } from '../../app/navTabs'

// LEDGER — the running record, ON THE PAGE.
//
// THE PAGE, NOT THE PACKED COLUMN (2026-11-03, owner row 267: *"it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake"*). The unfold slice (2026-11-01, row 260) put the four faces over
// ONE list panel in a 75-rem column with 26 rem kept clear at the right, its rows at their text line, scrolling inside
// itself. History is now a PAGE (`Sheet layout="page"`, screenLayout.ts "THE PAGE") on the pattern Stats set
// (docs/dev-log/2026-11-02-stats-design.md, Card.tsx) and the Codex followed: MAIN | SIDE from 1,024 px — MAIN the entries
// as ONE list card whose rows stand in as many columns as the main holds, under the DAY they happened on; the SIDE the
// tray's column, holding the record's figures AS GRAPHICS (never a paragraph where a figure would do): the money of the
// entries on the face (net, in, out, every move a bar), the record by kind (ranked bars), the biggest moves on the face
// (ranked bars). The page scrolls, never a list inside itself. A row with a report opens the report tray, which slides over
// the side column and moves nothing — as it always did. Nothing removed. The numbers it was measured to are in
// docs/dev-log/2026-11-03-history-design.md.
//
// WHAT THE SIDE PRINTS, AND WHY IT IS HONEST (ledgerFigures.ts): every figure is a sum or a count over the SERVED entries'
// own movement — never the purse (the You screen's) and never a total the game keeps elsewhere. The Money card and the
// Biggest board follow the face, as the Codex's boards follow its filters; the By kind board is the record's own shape
// (every face's share of all the entries), so a face pressed LIGHTS its row rather than leaving the board one bar.
//
// ON A PHONE THE LIST COMES FIRST (the Codex's lesson, 2026-11-02): below the split the side's cards stand AFTER the entries,
// so the first row is on the first glass. The faces are the one `Segmented` under the title — a choice of four is a
// segmented control, never a drop-down.

const FACE_ICON: Record<Exclude<Face, 'all'>, IconName> = {
  trade: 'coin',
  voyage: 'ship',
  crew: 'crew',
}
const markOf = (kind: string): IconName => {
  const face = FACE_OF[kind]
  return face === undefined ? 'ledger' : FACE_ICON[face]
}

/** How many moves the Biggest board ranks, and how many bars the Money card draws (about forty is the most that reads in a
 *  side card — SignedBars.tsx). */
const BOARD = 5
const BARS = 40

export function LedgerScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — the rail says History, so the screen does.
  const title = tabWord(useLocale(), '/ledger')
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return <LedgerBody title={title} />
}

function LedgerBody({ title }: { title: string }) {
  const t = useT()
  const events = useWorld((s) => s.events)
  const portByCode = useWorld((s) => s.portByCode)
  const [face, setFace] = useState<Face>('all')
  const [open, setOpen] = useState<LedgerEvent | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('closed')

  const shown = useMemo(() => onFace(events, face), [events, face])
  const portName = (code: string) => portNameOf(portByCode, code)
  const fights = open === null ? [] : payloadFights(open.payload)

  // the entries under their day (one date per group, spanning the card's columns), and the side's three readings
  const days = useMemo(() => byDay(shown, (atMs) => formatDate(atMs, { year: 'numeric', month: 'short', day: 'numeric' })), [shown])
  const money = useMemo(() => moneyOf(shown, BARS), [shown])
  const kinds = useMemo(() => kindsOf(events), [events])
  const biggest = useMemo(() => biggestOf(shown, BOARD), [shown])

  const kindRows: RankRow[] = kinds.map((k) => ({
    id: k.kind,
    label: k.kind === 'other' ? t('history.other') : t(FACES.find((f) => f.id === k.kind)!.label),
    value: k.n,
    // the face on the glass is lit; the others stand in neutral — the board is the record's shape, the face a view of it
    tone: face === 'all' || face === k.kind ? 'accent' : 'neutral',
    note: k.sum === 0 ? undefined : formatDucatsDelta(k.sum),
  }))
  const biggestRows: RankRow[] = biggest.map(({ event, move }) => ({
    id: event.id,
    label: headline(event, portName),
    value: move,
    tone: move > 0 ? 'success' : 'danger',
  }))

  const show = (event: LedgerEvent) => {
    setOpen(event)
    setDetent('half')
  }

  // THE PAGE SCROLLS (2026-11-03, owner row 267): no `fill`, no inner scroll — the record is as tall as its entries.
  return (
    <Sheet title={title} layout="page" data-testid="ledger">
      <Segmented
        segments={FACES.map((f) => ({ id: f.id, label: t(f.label) }))}
        value={face}
        onChange={setFace}
        label={title}
        className="w-fit max-w-full"
      />
      <PageSplit
        data-testid="ledger-page"
        // no `sideFirst`: on a phone the figures stand AFTER the entries — the record's purpose is the entries
        stickySide
        main={
          <ListPanel look="card" columns="fit" title={t('history.entries')} count={formatInt(shown.length)} data-testid="ledger-list">
            {shown.length === 0 ? (
              <Row label={events.length === 0 ? t('codex.nothingYet') : t('codex.nothingHere')} tone="muted" hairline={false} />
            ) : (
              days.map((group) => (
                <Fragment key={group.day}>
                  {/* THE DAY SPANS THE CARD'S COLUMNS (ListHeading), as a kind heading does in the Codex */}
                  <ListHeading data-testid="ledger-day">{group.day}</ListHeading>
                  {group.rows.map((event) => {
                    const atMs = Date.parse(event.at)
                    const report = payloadLines(event.payload)
                    return (
                      <Row
                        key={event.id}
                        data-testid="ledger-row"
                        mark={<IconDisc name={markOf(event.kind)} />}
                        label={headline(event, portName)}
                        value={movement(event.ducats_delta)}
                        chevron={report.length > 0}
                        onClick={report.length > 0 ? () => show(event) : undefined}
                        hairline={false}
                      >
                        <span className="block text-t-caption tabular-nums text-ink-faint">
                          {Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}
                        </span>
                      </Row>
                    )
                  })}
                </Fragment>
              ))
            )}
          </ListPanel>
        }
        side={
          <>
            <Card title={t('history.money')} data-testid="ledger-money">
              <StatCell look="stacked" label={t('stats.netShort')} value={money.net} format={formatDucatsDelta} tone={deltaTone(money.net)} data-testid="ledger-net" />
              <div className="mt-3">
                <StatCell look="line" label={t('history.in')} value={money.inSum} format={formatDucatsDelta} tone="success" />
                <StatCell look="line" label={t('history.out')} value={money.outSum} format={formatDucatsDelta} tone="danger" />
                <StatCell look="line" label={t('history.moves')} value={money.moved} format={formatInt} />
              </div>
              {money.bars.length > 0 && (
                <>
                  <SignedBars bars={money.bars} label={t('history.movesBars')} height="h-24" className="mt-5" data-testid="ledger-money-bars" />
                  <span className="mt-2 block text-t-caption text-ink-muted">{t('history.movesBars')}</span>
                </>
              )}
            </Card>
            <Card title={t('history.byKind')} data-testid="ledger-kinds">
              <RankBars rules={false} format={formatInt} empty={t('codex.nothingYet')} rows={kindRows} />
            </Card>
            <Card title={t('history.biggest')} data-testid="ledger-biggest">
              <RankBars rules={false} format={formatDucatsDelta} empty={t('history.noMoney')} rows={biggestRows} />
            </Card>
          </>
        }
      />

      {open !== null && (
        <Tray detent={detent} onDetentChange={setDetent} title={headline(open, portName)} data-testid="ledger-report">
          <div className="space-y-3 pb-2">
            {payloadLines(open.payload).map((line, i) => {
              const fight = fights.find((f) => f.line === i)
              return (
                <div key={i}>
                  <p className="text-t-label text-ink-muted">{line}</p>
                  {/* 0353: a fight that kept its log draws its numbers; any other draws the server's sentences, as before */}
                  {fight && fight.log && <FightLog log={fight.log} loss={fight.loss} />}
                  {fight && !fight.log && fight.rounds.length > 0 && (
                    <ol data-testid="battle-report" className="mt-2 space-y-1 border-l border-edge pl-3">
                      {fight.rounds.map((round, j) => (
                        <li key={j} className="text-t-caption text-ink-muted">
                          {round}
                        </li>
                      ))}
                    </ol>
                  )}
                </div>
              )
            })}
          </div>
        </Tray>
      )}
    </Sheet>
  )
}

function movement(delta: number | null) {
  if (delta === null) return undefined
  const rounded = Math.round(delta)
  if (rounded === 0) return <Figure value="0" tone="faint" />
  return <Figure value={`${rounded > 0 ? '+' : MINUS}${formatInt(Math.abs(rounded))}`} tone={rounded > 0 ? 'success' : 'danger'} />
}

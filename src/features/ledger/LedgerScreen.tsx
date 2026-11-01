import { useState } from 'react'
import {
  Figure,
  IconDisc,
  ListPanel,
  Row,
  Segmented,
  Sheet,
  Tray,
  type IconName,
  type TrayDetent,
} from '../../components/ui'
import { MINUS, formatClock, formatInt } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { LedgerEvent } from '../../lib/rpc'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { headline, payloadFights, payloadLines } from './headline'
import { useLocale, useT, type TKey } from '../../lib/i18n'
import { tabWord } from '../../app/navTabs'

// LEDGER — the running record, ON THE GLASS (owner, 2026-11-01, row 260: *"make things unfolded, minimize
// scrolling"*). It was the four faces over one summary row (`History 50 · Open`) with the feed behind a press;
// it is now the four faces over ONE list panel: the entries, newest first, scrolling inside it. A row with a
// report keeps its chevron and opens the report tray, as it always did. Nothing removed.

type Face = 'all' | 'trade' | 'voyage' | 'crew'

const FACES: readonly { id: Face; label: TKey }[] = [
  { id: 'all', label: 'codex.all' },
  { id: 'trade', label: 'codex.trade' },
  { id: 'voyage', label: 'codex.voyage' },
  { id: 'crew', label: 'codex.crew' },
]

const FACE_OF: Record<string, Exclude<Face, 'all'>> = {
  BOUGHT: 'trade',
  SOLD: 'trade',
  FULFILLED: 'trade',
  DEPARTED: 'voyage',
  VOYAGE_REPORT: 'voyage',
  PROVISIONED: 'voyage',
  PROVISION_REFUSED: 'voyage',
  REPAIRING: 'voyage',
  REPAIRED: 'voyage',
  TOWED: 'voyage',
  FORCED_HOME: 'voyage',
  ROUTE_LAP: 'voyage',
  ROUTE_PAUSED: 'voyage',
  HIRED: 'crew',
  DISMISSED: 'crew',
  SIGNED_OFFICER: 'crew',
  STUDIED: 'crew',
  ENROLLED: 'crew',
  WAGES: 'crew',
}

const FACE_ICON: Record<Exclude<Face, 'all'>, IconName> = {
  trade: 'coin',
  voyage: 'ship',
  crew: 'crew',
}
const markOf = (kind: string): IconName => {
  const face = FACE_OF[kind]
  return face === undefined ? 'ledger' : FACE_ICON[face]
}

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

  const shown = face === 'all' ? events : events.filter((e) => FACE_OF[e.kind] === face)
  const portName = (code: string) => portNameOf(portByCode, code)
  const fights = open === null ? [] : payloadFights(open.payload)

  const show = (event: LedgerEvent) => {
    setOpen(event)
    setDetent('half')
  }

  return (
    <Sheet title={title} fill data-testid="ledger">
      <Segmented
        segments={FACES.map((f) => ({ id: f.id, label: t(f.label) }))}
        value={face}
        onChange={setFace}
        label={title}
        className="mb-1 w-fit max-w-full shrink-0"
      />
      <ListPanel title={t('history.countEntries', { n: formatInt(shown.length), count: shown.length })} data-testid="ledger-list">
        {shown.length === 0 ? (
          <Row label={events.length === 0 ? t('codex.nothingYet') : t('codex.nothingHere')} tone="muted" hairline={false} />
        ) : (
          shown.map((event, i) => {
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
                hairline={i < shown.length - 1}
              >
                <span className="block text-t-caption tabular-nums text-ink-faint">
                  {Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}
                </span>
              </Row>
            )
          })
        )}
      </ListPanel>

      {open !== null && (
        <Tray detent={detent} onDetentChange={setDetent} title={headline(open, portName)} data-testid="ledger-report">
          <div className="space-y-3 pb-2">
            {payloadLines(open.payload).map((line, i) => {
              const fight = fights.find((f) => f.line === i)
              return (
                <div key={i}>
                  <p className="text-t-label text-ink-muted">{line}</p>
                  {fight && fight.rounds.length > 0 && (
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

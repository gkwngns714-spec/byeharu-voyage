import { useState } from 'react'
import {
  DetailPage,
  Figure,
  IconDisc,
  Row,
  Segmented,
  Sheet,
  SheetSection,
  SummaryRow,
  Tray,
  type IconName,
  type TrayDetent,
} from '../../components/ui'
import { MINUS, formatClock, formatInt } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { LedgerEvent } from '../../lib/rpc'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { headline, payloadFights, payloadLines } from './headline'
import { useT, type TKey } from '../../lib/i18n'

// LEDGER — the running record. THE COMPACT SCREEN (owner, 2026-10-31): the four faces are a tile
// grid and the feed is one summary row with its entry count; a press opens the feed's own full-
// screen page (every row, the report tray on a row). Nothing removed; nothing unfolds in place.

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
  const t = useT()
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  if (phase === 'failed') return <WorldFailed title={t('codex.history')} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={t('codex.history')} />
  return <LedgerBody />
}

function LedgerBody() {
  const t = useT()
  const events = useWorld((s) => s.events)
  const portByCode = useWorld((s) => s.portByCode)
  const [face, setFace] = useState<Face>('all')
  const [open, setOpen] = useState<LedgerEvent | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('closed')
  const [page, setPage] = useState(false)

  const shown = face === 'all' ? events : events.filter((e) => FACE_OF[e.kind] === face)
  const portName = (code: string) => portNameOf(portByCode, code)
  const fights = open === null ? [] : payloadFights(open.payload)

  const show = (event: LedgerEvent) => {
    setOpen(event)
    setDetent('half')
  }
  const closePage = () => {
    setPage(false)
    setOpen(null)
    setDetent('closed')
  }

  return (
    <Sheet title={t('codex.history')} data-testid="ledger">
      <Segmented segments={FACES.map((f) => ({ id: f.id, label: t(f.label) }))} value={face} onChange={setFace} label={t('codex.history')} className="mb-3 w-fit" />
      <SummaryRow title={t('codex.history')} figure={formatInt(shown.length)} word={t('common.open')} onClick={() => setPage(true)} data-testid="ledger-open" />

      {page && (
        <DetailPage title={t('codex.history')} figure={formatInt(shown.length)} onClose={closePage} data-testid="ledger-open-page">
          {shown.length === 0 ? (
            <Row label={events.length === 0 ? t('codex.nothingYet') : t('codex.nothingHere')} tone="muted" hairline={false} />
          ) : (
            <SheetSection surface>
              {shown.map((event) => {
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
                  >
                    <span className="block text-t-caption tabular-nums text-ink-faint">
                      {Number.isFinite(atMs) ? formatClock(atMs) : '--:--'}
                    </span>
                  </Row>
                )
              })}
            </SheetSection>
          )}
        </DetailPage>
      )}

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

import { useEffect, useMemo, useState } from 'react'
import { Chip, Figure, Note, Row, Sheet, SheetSection } from '../../components/ui'
import { VerbGrid } from './VerbGrid'
import { TradeQuestion } from './TradeQuestion'
import { SailQuestion } from './SailQuestion'
import { StepQuestion } from './StepQuestion'
import { QueueTray } from './QueueTray'
import type { CheckState } from './orderCheck'
import { useCommandDraft } from '../../domain/order'
import { composableVerbs, findVerb, isComplete, orderText } from '../../domain/order'
import { fleetHoldTotal, fleetHoldUsed, fleetPortCode, worstHullFraction, fleetCrew } from '../../domain/fleet'
import { proposeCourse, sailOrigin, sailTarget } from '../../domain/passage'
import { formatInt, formatPct, formatVoyageDays } from '../../lib/format'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { FleetView, Refusal } from '../../lib/rpc'

// CMD — THE HEART. E.1, and the only tab that changes the world. Redrawn to docs/UI_DIRECTION.md §6.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ORDERS ARE MADE, NOT TYPED. (The owner, 2026-08-19: "not typing, but making commands.")
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A fleet, a verb the server serves, then the verb's ONE question. There is no order input and no
// order STRING on the screen: `orderText` is composed at issue time only (§5). The server is the
// only judge — the tray runs `cmd.preview()` where a figure is worth showing before the press, and
// issue is the moment of truth for the rest.
//
// ── WHAT §6 DELETED HERE, AND THE 855→~200 COLLAPSE ────────────────────────────────────────────
// The `ORDERS / Command` header, the eyebrow, the wall clock's seconds, the `prices move in …`
// line (the SHELL prints it now on a trade route — TopBar.tsx), the hero triad shown three times,
// the `MAKE / An order` card, the empty `ORDER` box with `> nothing yet`, `Issue`/`Discard` above
// the grid, `Nothing to check yet`, the `VERB` and `NEEDS` labels, and the rail that put the first
// price ~1,900px down. `OrderComposer` (855), `FleetRail`, `PreviewPanel` and `HaggleBlock` are
// gone; the good tile and the buy tray are the design system's, shared with PORT (TradeTile /
// TradeTray). The verb grid is first, so the first price a BUY can tap is right under it.

const FALLBACK_REFUSAL: Refusal = {
  code: 'E_REFUSED',
  sentence: 'The server refused that, without saying why.',
  fixes: [],
  source: 'server',
}

/** The verbs whose tray shows a served dry run — a passage, or a price the server sets on the day. */
const CHECK_VERBS = new Set(['SAIL', 'HIRE', 'REPAIR', 'PROVISION'])
/** The verbs this screen has a picker for. The six 0068–0074 verbs are served but not yet composed
 *  here — they draw a tile and, when chosen, an honest line rather than a broken picker. */
const COMPOSABLE_HERE = new Set(['SAIL', 'BUY', 'SELL', 'HIRE', 'REPAIR', 'PROVISION'])

export function CommandScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const seaNav = useWorld((s) => s.seaNav)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const markets = useWorld((s) => s.markets)
  const busy = useWorld((s) => s.busy)
  const readAt = useWorld((s) => s.readAt)
  const open = useWorld((s) => s.open)
  const loadMarket = useWorld((s) => s.loadMarket)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)

  const fleetId = useCommandDraft((s) => s.fleetId)
  const verb = useCommandDraft((s) => s.verb)
  const args = useCommandDraft((s) => s.args)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const chooseVerb = useCommandDraft((s) => s.chooseVerb)
  const setArg = useCommandDraft((s) => s.setArg)
  const clearDraft = useCommandDraft((s) => s.clear)

  const [checked, setChecked] = useState<{ text: string; state: CheckState } | null>(null)
  const [issuing, setIssuing] = useState(false)
  const [bootError, setBootError] = useState<string | null>(null)
  const [queueOpen, setQueueOpen] = useState(false)

  useEffect(() => {
    open().catch((err: unknown) => setBootError(err instanceof Error ? err.message : String(err)))
  }, [open])

  const fleet = useMemo(() => fleets.find((f) => f.id === fleetId), [fleets, fleetId])
  useEffect(() => {
    if (fleet) return
    const first = fleets.find((f) => f.status === 'DOCKED') ?? fleets[0]
    if (first) selectFleet(first.id)
  }, [fleet, fleets, selectFleet])

  const portCode = fleet ? fleetPortCode(fleet) : null
  const port = portCode ? (portByCode[portCode] ?? null) : null
  const marketPortId = port?.id ?? null
  useEffect(() => {
    if (!marketPortId) return
    if (useWorld.getState().markets[marketPortId]) return
    void loadMarket(marketPortId)
  }, [marketPortId, loadMarket])
  const market = marketPortId ? markets[marketPortId] : undefined

  const verbs = useMemo(() => composableVerbs(snapshot?.verbs ?? []), [snapshot])
  const spec = findVerb(snapshot?.verbs ?? [], verb)

  const text = spec ? orderText(spec, args, fleet?.name) : ''
  const ready = Boolean(spec && fleet && isComplete(spec, args))
  const wantsCheck = Boolean(spec && CHECK_VERBS.has(spec.verb))

  // A SAIL carries the course the client found; the server verifies and measures it. Attached to
  // both the dry run and the issue, so the estimate priced and the order committed use one water.
  const course = useMemo(() => {
    if (spec?.verb !== 'SAIL' || !fleet || !seaNav) return null
    const target = sailTarget(args, portByCode)
    const origin = sailOrigin(fleet, portByCode)
    if (!target || !origin) return null
    return proposeCourse(seaNav, origin, target)
  }, [spec, fleet, seaNav, args, portByCode])

  // THE DRY RUN — only where a served figure is worth the round trip (SAIL's passage, the priced-
  // on-the-day verbs' cost). BUY/SELL bound themselves through `world.buy_capacity()` in the tray.
  useEffect(() => {
    if (!ready || !fleetId || !wantsCheck) return
    let alive = true
    const timer = setTimeout(() => {
      void preview(fleetId, text, course).then((result) => {
        if (!alive) return
        setChecked({
          text,
          state: result
            ? { status: 'ok', result }
            : { status: 'refused', refusal: useWorld.getState().refusal ?? FALLBACK_REFUSAL },
        })
      })
    }, 250)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [ready, fleetId, wantsCheck, text, course, preview])

  const check: CheckState = !ready || !wantsCheck
    ? { status: 'idle' }
    : checked?.text === text
      ? checked.state
      : { status: 'checking' }

  const doIssue = async () => {
    if (!ready || !fleetId) return
    setIssuing(true)
    const ok = await issue(fleetId, text, course)
    setIssuing(false)
    if (ok) {
      setChecked(null)
      clearDraft()
    }
  }

  if (phase === 'failed' && fatal) {
    return (
      <Sheet title="Command">
        <Note tone="danger" code={fatal.code}>{fatal.sentence}</Note>
      </Sheet>
    )
  }
  if (!snapshot) {
    return (
      <Sheet title="Command">
        {bootError ? (
          <Note tone="danger">The world would not open. {bootError}</Note>
        ) : (
          <Row label="Opening the world…" tone="muted" hairline={false} />
        )}
      </Sheet>
    )
  }

  if (fleets.length === 0) {
    return (
      <Sheet title="Command">
        <Note tone="neutral">There is nothing to command yet. A house founds its first fleet before it can give an order.</Note>
      </Sheet>
    )
  }

  const live = fleet ? fleet.queue.filter((o) => o.status === 'pending' || o.status === 'active').length : 0
  const halted = fleet ? fleet.queue.some((o) => o.status === 'failed') : false

  return (
    <Sheet title="Command">
      {/* WHOSE ORDER — fleet chips scroll sideways; the chosen one shows its one line and its queue. */}
      <div className="-mx-gutter flex gap-2 overflow-x-auto px-gutter pb-1">
        {fleets.map((f) => (
          <Chip key={f.id} on={f.id === fleetId} onClick={() => selectFleet(f.id)} className="shrink-0 whitespace-nowrap">
            {f.name} · {whereOf(f, portByCode)}
          </Chip>
        ))}
      </div>
      {fleet && (
        <Row
          label={verbLine(spec?.verb, fleet)}
          value={
            <button type="button" onClick={() => setQueueOpen(true)} className="flex min-h-11 items-center gap-1 text-t-caption text-ink-muted">
              <Figure value={formatInt(live)} unit="queued" tone={halted ? 'warning' : 'muted'} />
              {halted && <span className="text-warning">halted</span>}
            </button>
          }
          hairline={false}
        />
      )}

      <SheetSection>
        <VerbGrid verbs={verbs} chosen={spec?.verb} onChoose={chooseVerb} />
      </SheetSection>

      {spec && fleet && (
        <SheetSection>
          {(spec.verb === 'BUY' || spec.verb === 'SELL') && market && (
            <TradeQuestion
              intent={spec.verb === 'BUY' ? 'buy' : 'sell'}
              fleet={fleet}
              market={market}
              good={args.good}
              qty={args.qty && /^\d+$/.test(args.qty) ? Number(args.qty) : null}
              onTrade={(intent, code) => {
                const v = intent === 'buy' ? 'BUY' : 'SELL'
                if (spec.verb !== v) chooseVerb(v)
                setArg('good', code)
              }}
              onSetQty={(n) => setArg('qty', String(n))}
              onClose={() => {
                setArg('good', null)
                setArg('qty', null)
              }}
            />
          )}
          {(spec.verb === 'BUY' || spec.verb === 'SELL') && !market && (
            <Row label="Reading this port's market…" tone="muted" hairline={false} />
          )}

          {spec.verb === 'SAIL' && (
            <SailQuestion
              fleet={fleet}
              snapshot={snapshot}
              dest={args.dest}
              onPick={(code) => setArg('dest', code)}
              check={check}
              issuing={issuing}
              onIssue={() => void doIssue()}
            />
          )}

          {(spec.verb === 'HIRE' || spec.verb === 'REPAIR' || spec.verb === 'PROVISION') && (
            <StepQuestion
              fleet={fleet}
              spec={spec}
              port={port}
              args={args}
              setArg={setArg}
              check={check}
              timeCompression={snapshot.config.time_compression}
              issuing={issuing}
              onIssue={() => void doIssue()}
              onClose={() => clearDraft()}
            />
          )}

          {!COMPOSABLE_HERE.has(spec.verb) && (
            <Note tone="neutral">
              {spec.help} She takes this order from the harbour it happens at — it cannot be composed here yet.
            </Note>
          )}
        </SheetSection>
      )}

      {queueOpen && fleet && (
        <QueueTray
          fleet={fleet}
          busy={busy}
          readAt={readAt}
          onCancel={(seq) => void cancel(fleet.id, seq)}
          onClear={() => void clearQueue(fleet.id)}
          onClose={() => setQueueOpen(false)}
        />
      )}
    </Sheet>
  )
}

/** Where a fleet lies or is bound, in a word — for the chip. */
function whereOf(f: FleetView, portByCode: Record<string, import('../../lib/rpc').SnapshotPort>): string {
  if (f.port) return portNameOf(portByCode, f.port)
  if (f.voyage) return `→ ${f.voyage.to ? portNameOf(portByCode, f.voyage.to) : 'sea'}`
  if (f.anchor) return `at anchor`
  return f.status.toLowerCase()
}

/** The one fleet figure the chosen verb is a decision about (§6: "ONE line, t-label, per verb").
 *  With no verb chosen, the two facts a first glance wants: how far she can sail, and her room. */
function verbLine(verb: string | undefined, fleet: FleetView): string {
  const free = `${formatInt(fleet.free_hold)} t free`
  const stores = `${formatVoyageDays(fleet.endurance_days)} stores`
  switch (verb) {
    case 'BUY':
    case 'STORE':
    case 'TAKE':
      return `${free} · ${formatInt(fleetHoldTotal(fleet) - fleetHoldUsed(fleet))} of ${formatInt(fleetHoldTotal(fleet))} t`
    case 'SELL':
      return `${formatInt(fleetHoldUsed(fleet))} t aboard`
    case 'SAIL':
    case 'PROVISION':
      return stores
    case 'HIRE': {
      const c = fleetCrew(fleet)
      return `${formatInt(c.aboard)} of ${formatInt(c.max)} crew · ${formatInt(c.berths)} berths empty`
    }
    case 'REPAIR':
      return `${formatPct(worstHullFraction(fleet), 0)} worst hull`
    default:
      return `${stores} · ${free}`
  }
}

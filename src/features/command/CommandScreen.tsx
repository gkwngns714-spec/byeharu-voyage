import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  EmptyState,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
} from '../../components/ui'
import { formatClock, formatDucats, formatTuns, formatVoyageDays } from '../../lib/format'
import type { Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { OrderComposer } from './OrderComposer'
import { OrderQueue } from './OrderQueue'
import { PreviewPanel, type CheckState } from './PreviewPanel'
import { useCommandDraft } from './commandDraft'
import { freeHoldTuns } from './fleetLimits'
import { composableVerbs, findVerb, isComplete, orderText, type FixAction } from './orderText'

// CMD — THE HEART. E.1, and the only tab that changes the world.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ORDERS ARE MADE, NOT TYPED. (The owner, 2026-08-19: "not typing, but making commands.")
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// There is no order input on this screen and there is no toggle that brings one back. The player
// picks a fleet, a verb the server serves, and then each argument that verb declares — every one
// of them a tap on something that really exists: a port in the snapshot, a good in THIS port's
// market with its price and the server's own advice, a quantity bounded by the hold and the purse.
//
// THE STRING IS STILL THE CONTRACT. F.4: "Submit sends the string, not a structured object. There
// is exactly one parser." So the picks are assembled into the exact line `cmd.issue()` receives and
// that line is shown, READ-ONLY, while it writes itself — which is how a player learns the language
// without ever being made to spell it.
//
// THE SERVER IS THE ONLY JUDGE. Before an order can be issued, `cmd.preview()` runs the REAL verb
// in a subtransaction and rolls it back, so the estimate and the commit cannot disagree. The old
// client-side checker (validate.ts, 838 lines) is deleted: two authorities for "is this order
// legal" is exactly the duplication this project forbids.
//
// A READ IS THE CATCH-UP (D.2). Nothing on this screen ticks. `Read again` refetches, and issuing
// refetches, and that is the entire client-side model of time.
//
// THE REACH LAW (CORE_REUSE 1.5): every picker, chip, fix and cancel here is an ACTION, so nothing
// on this screen lives in a capped or scrolling region — the page's own scroll is the only one.
// Long lists TRUNCATE and say how many they are hiding (see ArgPickers.tsx).

const FALLBACK_REFUSAL: Refusal = {
  code: 'E_REFUSED',
  sentence: 'The server refused that, without saying why.',
  fixes: [],
  source: 'server',
}

export function CommandScreen() {
  const world = useWorld()
  const { open, refresh, loadMarket, preview, issue, cancel, clear: clearQueue } = world
  const draft = useCommandDraft()
  const { fleetId, verb, args, handoffs, selectFleet, chooseVerb, setArg, handOff, clear } = draft

  // THE DRY RUN'S ANSWER, stamped with the line it was about. Keeping the ANSWER rather than a
  // status means the state can never describe a line the player has already changed: a pick that
  // rewrites the line puts the panel back to `checking` by derivation, not by a second setState.
  const [checked, setChecked] = useState<{ text: string; state: CheckState } | null>(null)
  const [issuing, setIssuing] = useState(false)
  const [issued, setIssued] = useState<string | null>(null)
  /** A boot that THREW rather than refused. Rendered, never spun on — see below. */
  const [bootError, setBootError] = useState<string | null>(null)
  const composerRef = useRef<HTMLDivElement>(null)

  // The world opens itself the first time this tab is mounted. `open()` is idempotent, so it costs
  // nothing if the shell has already done it.
  //
  // THE CATCH IS LOAD-BEARING. `open()` awaits `initRpc()`, which THROWS when the migration chain
  // will not apply (a failed self-assert, say) — that throw never reaches the store's `fatal`, so
  // without this the screen would sit on "Opening the world…" for ever. A spinner that keeps
  // spinning is what a swallowed exception looks like (src/lib/db/README §1).
  useEffect(() => {
    open().catch((err: unknown) => setBootError(err instanceof Error ? err.message : String(err)))
  }, [open])

  const fleet = useMemo(() => world.fleets.find((f) => f.id === fleetId), [world.fleets, fleetId])

  // Command the fleet that can act right now. A fleet alongside is the one with choices.
  useEffect(() => {
    if (fleet) return
    const first = world.fleets.find((f) => f.status === 'DOCKED') ?? world.fleets[0]
    if (first) selectFleet(first.id)
  }, [fleet, world.fleets, selectFleet])

  // The market this order would trade in: where she lies, or where she is bound (a BUY issued at
  // sea runs on arrival — F.2, "sell the cloves when you get to Amsterdam").
  const portCode = fleet?.port ?? fleet?.voyage?.to ?? null
  const port = portCode ? (world.portByCode[portCode] ?? null) : null
  const marketPortId = port?.id ?? null
  useEffect(() => {
    if (!marketPortId) return
    if (useWorld.getState().markets[marketPortId]) return
    void loadMarket(marketPortId)
  }, [marketPortId, loadMarket])
  const market = marketPortId ? world.markets[marketPortId] : undefined

  const verbs = useMemo(() => composableVerbs(world.snapshot?.verbs ?? []), [world.snapshot])
  const spec = findVerb(world.snapshot?.verbs ?? [], verb)

  const text = spec ? orderText(spec, args, fleet?.name) : ''
  const ready = Boolean(spec && fleet && isComplete(spec, args))

  // Another tab handed an order over — bring the composer into view rather than leaving the player
  // wondering where their tap went.
  useEffect(() => {
    if (handoffs > 0) composerRef.current?.scrollIntoView({ block: 'start', behavior: 'smooth' })
  }, [handoffs])

  // THE DRY RUN. Debounced, because every pick rewrites the line and every preview is a real
  // transaction on the server (it runs the verb and rolls it back).
  useEffect(() => {
    if (!ready || !fleetId) return
    let alive = true
    const timer = setTimeout(() => {
      void preview(fleetId, text).then((result) => {
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
  }, [ready, fleetId, text, preview])

  const check: CheckState = !ready
    ? { status: 'idle' }
    : checked?.text === text
      ? checked.state
      : { status: 'checking' }

  const doIssue = async () => {
    if (!ready || !fleetId) return
    setIssuing(true)
    const sent = text
    const ok = await issue(fleetId, sent)
    setIssuing(false)
    if (ok) {
      setIssued(sent)
      setChecked(null)
      // Back to "no verb chosen": the order is the server's now, and it is in the queue below.
      clear()
    } else {
      setChecked({
        text: sent,
        state: { status: 'refused', refusal: useWorld.getState().refusal ?? FALLBACK_REFUSAL },
      })
    }
  }

  // A fix is a real order. Tapping one LOADS it — into the composer if it is composable, or onto
  // the queue if it is CANCEL/CLEAR, whose only argument is a queue row.
  const applyFix = (action: FixAction) => {
    if (action.kind === 'compose') {
      handOff({ verb: action.verb, args: action.args })
      return
    }
    if (action.kind === 'queue' && fleetId) {
      if (action.verb === 'CLEAR') void clearQueue(fleetId)
      else void cancel(fleetId, action.index)
    }
  }

  if (world.phase === 'failed' && world.fatal) {
    return (
      <Screen>
        <PageHeader eyebrow="Orders" title="Command" />
        <Notice tone="danger">
          <span className="font-mono">{world.fatal.code}</span> — {world.fatal.sentence}
        </Notice>
      </Screen>
    )
  }

  if (!world.snapshot) {
    return (
      <Screen>
        <PageHeader
          eyebrow="Orders"
          title="Command"
          subtitle={bootError ? 'The world would not open.' : 'Opening the world…'}
        />
        {bootError && (
          <Notice tone="danger" className="whitespace-pre-wrap font-mono text-xs">
            {bootError}
          </Notice>
        )}
      </Screen>
    )
  }

  return (
    <Screen>
      <PageHeader
        eyebrow="Orders"
        title="Command"
        subtitle="Pick what she is to do. The order writes itself."
        actions={
          <>
            {world.ducats !== null && (
              <span className="font-mono text-sm text-accent">{formatDucats(world.ducats)}</span>
            )}
            <Button variant="ghost" disabled={world.busy} onClick={() => void refresh()}>
              {world.busy ? 'reading…' : 'Read again'}
            </Button>
          </>
        }
      />

      {world.fleets.length === 0 ? (
        <EmptyState
          title="No fleets"
          body="There is nothing to command yet. A house founds its first fleet before it can give an order."
        />
      ) : (
        <>
          {/* ── WHOSE ORDER THIS IS ────────────────────────────────────────────────────────── */}
          <Card tone="accent">
            <SectionLabel>Commanding</SectionLabel>
            <div className="flex flex-wrap gap-2">
              {world.fleets.map((f) => {
                const halted = f.queue.some((o) => o.status === 'failed')
                const waiting = f.queue.filter((o) => o.status === 'pending' || o.status === 'active').length
                const where = f.port
                  ? (world.portByCode[f.port]?.name ?? f.port)
                  : f.voyage
                    ? `→ ${world.portByCode[f.voyage.to]?.name ?? f.voyage.to}`
                    : f.status.toLowerCase()
                return (
                  <button
                    key={f.id}
                    type="button"
                    onClick={() => selectFleet(f.id)}
                    className={[
                      'min-h-11 rounded-md border px-3 py-1 text-left transition',
                      f.id === fleetId
                        ? 'border-accent bg-accent text-app'
                        : 'border-edge bg-surface-2 text-ink hover:border-accent/60',
                    ].join(' ')}
                  >
                    <span className="block font-mono text-xs">{f.name}</span>
                    <span className="block font-mono text-[11px] opacity-75">
                      {where}
                      {waiting > 0 && ` · ${waiting} queued`}
                      {halted && ' · HALTED'}
                    </span>
                  </button>
                )
              })}
            </div>
            {fleet && (
              <p className="mt-3 font-mono text-[11px] text-ink-faint">
                {fleet.name}: {formatVoyageDays(fleet.endurance_days)} of stores · {fleet.speed_kn.toFixed(1)} kn ·{' '}
                {formatTuns(freeHoldTuns(fleet))} free{port ? ` · lying at ${port.name}` : ''}
              </p>
            )}
          </Card>

          {/* ── MAKING THE ORDER ───────────────────────────────────────────────────────────── */}
          <div ref={composerRef}>
            <Card>
              <CardHeader
                eyebrow="Make"
                title="An order"
                subtitle="Every choice below is something that really exists right now."
                aside={<Badge tone="neutral">{verbs.length + 2} verbs</Badge>}
              />
              <OrderComposer
                verbs={verbs}
                spec={spec}
                args={args}
                fleet={fleet}
                snapshot={world.snapshot}
                market={market}
                ducats={world.ducats}
                onChooseVerb={chooseVerb}
                onSetArg={setArg}
              />

              {/* THE LINE — read-only, and the whole contract with the server. */}
              <div className="mt-4 space-y-3 rounded-md border border-accent/25 bg-accent-soft p-3">
                <SectionLabel className="mb-0">What will be sent</SectionLabel>
                <p className="flex items-start gap-2">
                  <span aria-hidden className="font-mono text-lg leading-none text-accent">
                    &gt;
                  </span>
                  <code aria-live="polite" className="min-w-0 flex-1 break-words font-mono text-sm text-ink">
                    {text || <span className="text-ink-faint">nothing yet</span>}
                  </code>
                </p>
                <p className="font-mono text-[11px] text-ink-faint">
                  This exact line goes to cmd.issue(fleet, text, version). There is one parser, and it
                  is on the server (F.4).
                </p>
              </div>

              <div className="mt-3 flex flex-wrap gap-2">
                <Button
                  variant="primary"
                  disabled={!ready || issuing || check.status === 'refused' || check.status === 'checking'}
                  busy={issuing}
                  busyLabel="Issuing…"
                  onClick={() => void doIssue()}
                >
                  Issue this order
                </Button>
                <Button variant="ghost" disabled={!spec} onClick={clear}>
                  Start over
                </Button>
              </div>

              <div className="mt-3 border-t border-edge pt-3">
                <PreviewPanel
                  state={check}
                  verbs={world.snapshot.verbs}
                  timeCompression={world.snapshot.config.time_compression}
                  onFix={applyFix}
                />
              </div>

              {issued && (
                <Notice tone="success" className="mt-3 font-mono text-xs">
                  sent: {issued}
                </Notice>
              )}
            </Card>
          </div>

          {/* ── THE QUEUE ──────────────────────────────────────────────────────────────────── */}
          {fleet && (
            <Card>
              <CardHeader
                eyebrow="Standing"
                title="Her queue"
                subtitle="First in, first out. On a failure it halts — it never skips."
                aside={
                  world.readAt ? (
                    // The queue is as fresh as the last READ — nothing here ticks (D.2), so the
                    // panel says WHEN it was read rather than pretending to know the time now.
                    <span className="font-mono text-[11px] text-ink-faint">
                      as of {formatClock(world.readAt)}
                    </span>
                  ) : undefined
                }
              />
              <OrderQueue
                fleet={fleet}
                queueMax={world.snapshot.config.order_queue_max}
                busy={world.busy}
                readAt={world.readAt}
                destination={fleet.voyage ? (world.portByCode[fleet.voyage.to]?.name ?? null) : null}
                onCancel={(seq) => void cancel(fleet.id, seq)}
                onClear={() => void clearQueue(fleet.id)}
              />
            </Card>
          )}
        </>
      )}
    </Screen>
  )
}

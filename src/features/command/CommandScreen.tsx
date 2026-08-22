import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Badge,
  Button,
  buttonClasses,
  Card,
  CardHeader,
  EmptyState,
  Explain,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  fineClass,
} from '../../components/ui'
import { formatClock, formatTuns, formatVoyageDays } from '../../lib/format'
import type { Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { OrderComposer } from './OrderComposer'
import { OrderQueue } from './OrderQueue'
import { PreviewPanel, type CheckState } from './PreviewPanel'
import { useCommandDraft } from '../../domain/order'
import { composableVerbs, findVerb, isComplete, orderText, type FixAction } from '../../domain/order'

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
  // FIELDS, NOT THE STORE (worldStore.ts rule 4). Actions are selected too: a zustand action is a
  // stable reference, so a hook per verb costs nothing and never re-renders.
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const markets = useWorld((s) => s.markets)
  const busy = useWorld((s) => s.busy)
  const readAt = useWorld((s) => s.readAt)
  const open = useWorld((s) => s.open)
  const refresh = useWorld((s) => s.refresh)
  const loadMarket = useWorld((s) => s.loadMarket)
  const preview = useWorld((s) => s.preview)
  const issue = useWorld((s) => s.issue)
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  // The draft store gets the same treatment, and for the same reason: this was `useCommandDraft()`
  // destructured, which re-rendered the whole tab on every keystroke of a pick even where only one
  // field had moved. Every other caller of this store already selected (FleetsScreen, PortScreen).
  const fleetId = useCommandDraft((s) => s.fleetId)
  const verb = useCommandDraft((s) => s.verb)
  const args = useCommandDraft((s) => s.args)
  const handoffs = useCommandDraft((s) => s.handoffs)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const chooseVerb = useCommandDraft((s) => s.chooseVerb)
  const setArg = useCommandDraft((s) => s.setArg)
  const handOff = useCommandDraft((s) => s.handOff)
  const clear = useCommandDraft((s) => s.clear)

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

  const fleet = useMemo(() => fleets.find((f) => f.id === fleetId), [fleets, fleetId])

  // Command the fleet that can act right now. A fleet alongside is the one with choices.
  useEffect(() => {
    if (fleet) return
    const first = fleets.find((f) => f.status === 'DOCKED') ?? fleets[0]
    if (first) selectFleet(first.id)
  }, [fleet, fleets, selectFleet])

  // The market this order would trade in: where she lies, or where she is bound (a BUY issued at
  // sea runs on arrival — F.2, "sell the cloves when you get to Amsterdam").
  const portCode = fleet?.port ?? fleet?.voyage?.to ?? null
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

  if (phase === 'failed' && fatal) {
    return (
      <Screen>
        <PageHeader eyebrow="Orders" title="Command" />
        <Notice tone="danger">
          <span className="font-mono">{fatal.code}</span> — {fatal.sentence}
        </Notice>
      </Screen>
    )
  }

  if (!snapshot) {
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
        explain="Pick what she is to do; the order writes itself. Nothing here happens until you issue it."
        /* The purse used to be printed here as well. It lives in the top bar now, on every screen
           at once (TopBar.tsx): one fact shown in two places is two authorities for it, and the
           copy that scrolls away is the wrong one to keep. */
        actions={
          <Button variant="ghost" disabled={busy} onClick={() => void refresh()}>
            {busy ? 'reading…' : 'Read again'}
          </Button>
        }
      />

      {fleets.length === 0 ? (
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
              {fleets.map((f) => {
                const halted = f.queue.some((o) => o.status === 'failed')
                const waiting = f.queue.filter((o) => o.status === 'pending' || o.status === 'active').length
                const where = f.port
                  ? (portByCode[f.port]?.name ?? f.port)
                  : f.voyage
                    ? `→ ${portByCode[f.voyage.to]?.name ?? f.voyage.to}`
                    : f.status.toLowerCase()
                return (
                  <button
                    key={f.id}
                    type="button"
                    onClick={() => selectFleet(f.id)}
                    // One of the hand-written chip recipes the D12 audit found. It is the design
                    // system's `chip` / `chip-on` now (buttonStyles.ts), so a fleet chip here, a
                    // verb chip in a picker and a filter chip on the Ledger cannot drift apart
                    // again. The two lines are wrapped in ONE span deliberately: `buttonClasses`
                    // puts `gap-2` on the flex container, and two direct children would open 8px
                    // of air between a fleet's name and where she lies.
                    className={buttonClasses(f.id === fleetId ? 'chip-on' : 'chip', 'md', 'text-left')}
                  >
                    <span className="block">
                      <span className="block font-mono text-xs">{f.name}</span>
                      <span className="block font-mono text-[11px] opacity-75">
                        {where}
                        {waiting > 0 && ` · ${waiting} queued`}
                        {halted && ' · HALTED'}
                      </span>
                    </span>
                  </button>
                )
              })}
            </div>
            {fleet && (
              <p className={fineClass('mt-3')}>
                {/* THE SERVER'S OWN FIGURE. `free_hold` is `public.fleet_free_hold` (0017:183) —
                    the same reading `cmd.do_buy` checks and `public.fleet_load` places into — so
                    the line above the composer and the refusal below it cannot disagree. It used
                    to be `freeHoldTuns(fleet)`, one of three client re-derivations of it. */}
                {fleet.name}: {formatVoyageDays(fleet.endurance_days)} of stores · {fleet.speed_kn.toFixed(1)} kn ·{' '}
                {formatTuns(fleet.free_hold)} free
                {/* `port` is where the order will TRADE — where she lies, or where she is bound if
                    she is at sea (F.2). Printing it as "lying at" either way told the player she
                    was alongside while the panel below said "at sea, 84 nm of 248". Same fact,
                    two sentences, one of them false. */}
                {port ? (fleet.status === 'SAILING' ? ` · bound for ${port.name}` : ` · lying at ${port.name}`) : ''}
              </p>
            )}
          </Card>

          {/* ── MAKING THE ORDER ───────────────────────────────────────────────────────────── */}
          <div ref={composerRef}>
            <Card>
              <CardHeader
                eyebrow="Make"
                title="An order"
                explain="Every choice below is something that really exists right now — a port she can reach, a good this market trades, a quantity she can afford."
                aside={<Badge tone="neutral">{verbs.length + 2} verbs</Badge>}
              />
              <OrderComposer
                verbs={verbs}
                spec={spec}
                args={args}
                fleet={fleet}
                snapshot={snapshot}
                market={market}
                onChooseVerb={chooseVerb}
                onSetArg={setArg}
              />

              {/* THE LINE — read-only, and the whole contract with the server. */}
              <div className="mt-4 space-y-3 rounded-md border border-accent/25 bg-accent-soft p-3">
                {/* The dot rides the section label, where the reader is already looking, rather
                    than floating alone under the line it explains. */}
                <SectionLabel className="mb-0">
                  What will be sent
                  <Explain label="What will be sent" dotClassName="ml-0.5">
                    This exact line goes to cmd.issue(fleet, text, version). There is one parser, and
                    it is on the server (F.4).
                  </Explain>
                </SectionLabel>
                <p className="flex items-start gap-2">
                  {/* THIS ONE STAYS A CHARACTER. It reads as a chevron, and `icons.ts` has one —
                      but it is a PROMPT, set in the same mono face and on the same baseline as the
                      order line beside it, which is what makes the two read as one typed command.
                      An SVG here would be a mark next to a line of code instead of the head of it. */}
                  <span aria-hidden className="font-mono text-lg leading-none text-accent">
                    &gt;
                  </span>
                  <code aria-live="polite" className="min-w-0 flex-1 break-words font-mono text-sm text-ink">
                    {text || <span className="text-ink-faint">nothing yet</span>}
                  </code>
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
                {/* TWO THINGS ABOUT THIS BUTTON, AND BOTH ARE EASY TO GET WRONG.

                    IT IS THE DRAFT, NOT THE QUEUE. It calls the draft store's `clear()`
                    (src/domain/order/draft.ts:124), which throws away the verb and arguments being
                    composed ON THIS CLIENT and keeps the fleet selected. Nothing has been sent, so
                    nothing is cancelled. The panel below carries "Clear <fleet>'s queue", which is
                    the other thing entirely: `cmd.clear()` on the server, dropping orders she has
                    already been given. It used to read "Start over", which named neither — and sat
                    a few hundred pixels from a control that really does destroy standing orders.
                    "Discard this order" says which order and how far it had got.

                    IT IS HIDDEN ON PROVISION, by the owner's explicit instruction (2026-08-22:
                    "remove start over on provision"). Not disabled — absent. Every other verb keeps
                    it, and a fleet chosen with no verb yet keeps it too, disabled, exactly as
                    before: there is no draft to discard. */}
                {spec?.verb !== 'PROVISION' && (
                  <Button variant="ghost" disabled={!spec} onClick={clear}>
                    Discard this order
                  </Button>
                )}
              </div>

              <div className="mt-3 border-t border-edge pt-3">
                <PreviewPanel
                  state={check}
                  verbs={snapshot.verbs}
                  timeCompression={snapshot.config.time_compression}
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
                explain={`One queue per fleet, ${snapshot.config.order_queue_max} deep, first in first out. On a failure it halts — it never skips. A voyage already at sea keeps sailing when you clear.`}
                aside={
                  readAt ? (
                    // The queue is as fresh as the last READ — nothing here ticks (D.2), so the
                    // panel says WHEN it was read rather than pretending to know the time now.
                    <span className={fineClass()}>
                      as of {formatClock(readAt)}
                    </span>
                  ) : undefined
                }
              />
              <OrderQueue
                fleet={fleet}
                queueMax={snapshot.config.order_queue_max}
                busy={busy}
                readAt={readAt}
                destination={fleet.voyage ? (portByCode[fleet.voyage.to]?.name ?? null) : null}
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

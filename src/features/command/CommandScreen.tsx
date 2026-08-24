import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  Badge,
  Button,
  buttonClasses,
  Card,
  CardHeader,
  Countdown,
  EmptyState,
  Explain,
  HeroFigure,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  WallClock,
  fineClass,
  useReaskAtEdge,
} from '../../components/ui'
import { formatClock, formatFixed, formatOfTotal, formatPct } from '../../lib/format'
import { useShellState } from '../../app/shellState'
import type { Refusal } from '../../lib/rpc'
import { portNameOf, useWorld } from '../../live/worldStore'
import { OrderComposer } from './OrderComposer'
import { OrderQueue } from './OrderQueue'
import { PreviewPanel, type CheckState } from './PreviewPanel'
import { useCommandDraft } from '../../domain/order'
import { composableVerbs, findVerb, isComplete, orderText, type FixAction } from '../../domain/order'
import { fleetHoldTotal, fleetHoldUsed, fleetPortCode } from '../../domain/fleet'
import { parsePointToken, pointLabel, proposeCourse, sailOrigin } from '../../domain/passage'

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
// A READ IS THE CATCH-UP (D.2). Nothing on this screen ticks. The shell reads the world every
// thirty seconds and on tab focus (AppShell.tsx), issuing refetches, and the market's own
// countdown re-asks at the price edge — that is the entire client-side model of time, and it is
// why this screen carries no refresh control of its own.
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

/** The order's own box — one recipe, worn by the head block and by SAIL's in-tile confirm. */
const ORDER_BOX = 'space-y-3 rounded-md border border-accent/25 bg-accent-soft p-3'

/**
 * THE LINE, AS THE CLERK WRITES IT — one rendering, two wearers: the head block (where it forms
 * in front of the player as the picks fill it in) and SAIL's confirm fold (where it is read one
 * last time before the press). `live` only on the head's copy: two aria-live regions announcing
 * the same string would say everything twice to a screen reader.
 */
function OrderLine({ text, live }: { text: string; live?: boolean }) {
  return (
    <p className="flex items-start gap-2">
      {/* THIS ONE STAYS A CHARACTER. It reads as a chevron, and `icons.ts` has one — but it is a
          PROMPT, set in the same mono face and on the same baseline as the order line beside it,
          which is what makes the two read as one typed command. An SVG here would be a mark next
          to a line of code instead of the head of it. */}
      <span aria-hidden className="font-mono text-lg leading-none text-accent">
        &gt;
      </span>
      <code
        aria-live={live ? 'polite' : undefined}
        className="min-w-0 flex-1 break-words font-mono text-sm text-ink"
      >
        {text || <span className="text-ink-faint">nothing yet</span>}
      </code>
    </p>
  )
}

export function CommandScreen() {
  // FIELDS, NOT THE STORE (worldStore.ts rule 4). Actions are selected too: a zustand action is a
  // stable reference, so a hook per verb costs nothing and never re-renders.
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
  // sea runs on arrival — F.2, "sell the cloves when you get to Amsterdam"). `fleetPortCode` is
  // that question's one answer (domain/fleet); this was one of four places that spelt it out, and
  // the fourth — PortScreen's — had got it wrong.
  const portCode = fleet ? fleetPortCode(fleet) : null
  const port = portCode ? (portByCode[portCode] ?? null) : null
  const marketPortId = port?.id ?? null
  useEffect(() => {
    if (!marketPortId) return
    if (useWorld.getState().markets[marketPortId]) return
    void loadMarket(marketPortId)
  }, [marketPortId, loadMarket])
  const market = marketPortId ? markets[marketPortId] : undefined

  // ── THE WALL CLOCK, AND HOW LONG THE QUAY'S PRICES STAND ───────────────────────────────────────
  // The owner: *"i want actual time shown on command, and how much left for it to change the prices
  // live."* Both instants are SERVED, on the same payload that carries the prices themselves
  // (`clock`, migration 0029) — the client never multiplies a cadence out to find the next boundary,
  // because "when do prices move" may have exactly one author and the read that serves the prices
  // is it.
  //
  // THE RE-ASK IS NOT A REFRESH. On any deployment without pg_cron — which is every browser — the
  // market read is ALSO what steps the drift walk (0029). So a countdown that reaches zero and
  // re-asks is not merely fetching a newer number; it is the thing that makes the prices move. Do
  // not "optimise" it into a conditional fetch.
  const { nowMs } = useShellState()
  const clock = market?.clock
  const priceEdgeMs = clock ? Date.parse(clock.next_change_at) : null
  const pricePayloadAtMs = clock ? Date.parse(clock.now) : null
  const reaskMarket = useCallback(() => {
    if (marketPortId) void loadMarket(marketPortId)
  }, [marketPortId, loadMarket])
  useReaskAtEdge(priceEdgeMs, pricePayloadAtMs, nowMs, reaskMarket)

  const verbs = useMemo(() => composableVerbs(snapshot?.verbs ?? []), [snapshot])
  const spec = findVerb(snapshot?.verbs ?? [], verb)

  const text = spec ? orderText(spec, args, fleet?.name) : ''
  const ready = Boolean(spec && fleet && isComplete(spec, args))

  // THE PROPOSAL (0039). A SAIL carries the course the client found - the one pathfinder over the
  // served raster - and the SERVER verifies every segment and measures the miles itself. Computed
  // when the destination is answered (worst measured search ~166 ms; the browser figure is in the
  // acceptance report), and attached to BOTH the dry run and the issue, so the estimate printed
  // and the order committed are priced over the same water.
  const course = useMemo(() => {
    if (spec?.verb !== 'SAIL' || !fleet || !seaNav) return null
    const destCode = args['dest']
    const pointTok = args['dest_point']
    const port = destCode ? portByCode[destCode] : undefined
    const target = port
      ? { lat: port.lat, lon: port.lon }
      : pointTok
        ? parsePointToken(pointTok)
        : null
    const origin = sailOrigin(fleet, portByCode)
    if (!target || !origin) return null
    return proposeCourse(seaNav, origin, target)
  }, [spec, fleet, seaNav, args, portByCode])

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
  }, [ready, fleetId, text, course, preview])

  const check: CheckState = !ready
    ? { status: 'idle' }
    : checked?.text === text
      ? checked.state
      : { status: 'checking' }

  const doIssue = async () => {
    if (!ready || !fleetId) return
    setIssuing(true)
    const sent = text
    const ok = await issue(fleetId, sent, course)
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

  // ── SAIL COMPLETES UNDER THE TILE THAT COMPLETED IT (the owner, 2026-08-24) ────────────────────
  // *"i want issue this order to be at the bottom of the location i click on it, unfolding it, but
  // without making a new screen."* A SAIL is one argument, and tapping a harbour tile supplies it —
  // so the check and the Issue button UNFOLD right beneath the tapped tile (the same shape as the
  // BUY good row's fold, which the owner asked for twice), instead of asking the player to travel
  // back up to the head of the card.
  //
  // ONE BUTTON PER ORDER, so for SAIL the head block keeps the forming line and LOSES its Issue
  // and its check — both live in this fold, which is the one you press. Two Issue buttons for one
  // order is exactly the duplication this codebase keeps deleting (docs/NO_SPAGHETTI.md §5). The
  // node is BUILT here — beside `doIssue`, `check` and `applyFix`, whose authorities it wires —
  // and only RENDERED down in the picker, so nothing below this screen ever calls the issue path.
  //
  // THE REACH LAW HOLDS: the fold sits in ordinary document flow inside the picker (no scroll box,
  // no cap — ArgPickers' own rule), and it is under the player's finger by construction.
  const sailInline = spec?.verb === 'SAIL'
  const sailConfirm = sailInline ? (
    <div className={ORDER_BOX} data-testid="sail-confirm">
      <OrderLine text={text} />
      <PreviewPanel
        state={check}
        verbs={snapshot.verbs}
        timeCompression={snapshot.config.time_compression}
        onFix={applyFix}
      />
      <Button
        variant="primary"
        disabled={!ready || issuing || check.status === 'refused' || check.status === 'checking'}
        busy={issuing}
        busyLabel="Issuing…"
        onClick={() => void doIssue()}
      >
        Issue this order
      </Button>
    </div>
  ) : null

  return (
    // `wide` — the max-w-6xl measure MARKET already uses. COMMAND earned it when the BUY composer
    // grew a second pane: at the narrow measure the goods list and the fleet rail share 720px, and
    // the three price columns on a market row are the first thing to crush. It changes NOTHING
    // below 768px, where a max-width that large never binds, so the phone layout is untouched.
    <Screen wide>
      <PageHeader
        eyebrow="Orders"
        title="Command"
        explain="Pick what she is to do; the order writes itself. Nothing here happens until you issue it."
        /* The purse used to be printed here as well. It lives in the top bar now, on every screen
           at once (TopBar.tsx): one fact shown in two places is two authorities for it, and the
           copy that scrolls away is the wrong one to keep. */
        /* NO "READ AGAIN" BUTTON (the owner, 2026-08-23: "read again on top left of the game is
           useless. remove it"). The shell already reads the world every thirty seconds and on the
           tab regaining focus (AppShell.tsx, READ_INTERVAL_MS) — a button asking for what is
           already happening teaches the player their tap did nothing. Deleted, not hidden; the
           price-clock re-ask below is a DIFFERENT mechanism (it is what steps the market) and
           stays. */
        actions={
          /* THE TIME, AND THE PRICES' OWN DEADLINE, in the header rather than beside the goods:
             the countdown governs every price on this screen at once, not one row, and a figure
             that belongs to the whole screen must not be anchored to a part of it. Both are
             one-line and tabular, so no ⓘ — there is no sentence here to fold. */
          <span className="flex flex-col items-end leading-tight">
            <WallClock nowMs={nowMs} className="font-mono text-xs text-ink-muted" />
            {priceEdgeMs !== null && (
              <span className={fineClass()}>
                prices move in{' '}
                <Countdown untilMs={priceEdgeMs} nowMs={nowMs} dueText="now" />
              </span>
            )}
          </span>
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
                  ? portNameOf(portByCode, f.port)
                  : f.voyage
                    ? `→ ${f.voyage.to ? portNameOf(portByCode, f.voyage.to) : f.voyage.dest_point ? pointLabel({ lat: f.voyage.dest_point[0], lon: f.voyage.dest_point[1] }) : 'open sea'}`
                    : f.anchor
                      ? `at anchor · ${pointLabel({ lat: f.anchor[0], lon: f.anchor[1] })}`
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
              // ── HER THREE FIGURES, EACH UNDER ITS OWN LABEL ──────────────────────────────────
              // This was one run-on mono sentence — "Gaivota: 15.0 days of stores · 4.9 kn ·
              // 56 t free · lying at Lisbon" — and the owner named all four of its faults
              // (2026-08-23): days of WHAT, 4.9 kn of WHAT, free of WHAT, and a berth already
              // printed on the chip above. So each figure now stands in its own labelled cell
              // (docs/UI_DIRECTION.md §4 rule 2: the number is the hero, the label is the small
              // dim thing beside it), the sentence that explains a figure is behind its dot, and
              // WHERE SHE LIES IS NOT HERE AT ALL — the fleet chip is the one place that names
              // it, and one fact in two places is two authorities for it.
              //
              // THE LABELS ARE NAMES, NOT SENTENCES (the owner, 2026-08-23: "stores last ->
              // provision", "cargo space or cargo, and 0T/54T - 0%"). PROVISION is already the
              // verb that refills the barrels, so the figure and the order that moves it share
              // one word.
              //
              // EVERY FIGURE IS THE SERVER'S OR HAS ITS ONE DOMAIN OWNER: `endurance_days`
              // (voyage.endurance_days, 0009:172), `speed_kn` (voyage.fleet_speed, 0009:171),
              // and the cargo pair from `fleetHoldUsed`/`fleetHoldTotal` (domain/fleet — the same
              // authorities FLEETS prints). NOTHING HERE DERIVES "FREE": `fleet.free_hold`
              // (public.fleet_free_hold, 0017:183) clamps per hull and is deliberately NOT
              // `total − used`, so no free figure is printed beside this pair at all — the served
              // one lives in the BUY rail, where a purchase is actually decided.
              <dl className="mt-3 grid grid-cols-3 gap-3">
                <div>
                  <dt className={fineClass('flex flex-wrap items-center gap-x-0.5 uppercase tracking-wider')}>
                    provision
                    <Explain label="provision">
                      How long she can keep the sea before her water and food run out. PROVISION
                      refills the barrels; a passage longer than this is refused before she sails.
                    </Explain>
                  </dt>
                  <dd>
                    {/* The NUMBER is the value and the word is the small unit — "15.0 days" as one
                        2xl string wraps a 120px column at 390px (measured; the first cut shipped
                        it and the figure broke across three lines). */}
                    <HeroFigure value={formatFixed(fleet.endurance_days, 1)} unit="days" />
                  </dd>
                </div>
                <div>
                  <dt className={fineClass('uppercase tracking-wider')}>speed</dt>
                  <dd>
                    <HeroFigure value={formatFixed(fleet.speed_kn, 1)} unit="kn" />
                  </dd>
                </div>
                <div>
                  <dt className={fineClass('flex flex-wrap items-center gap-x-0.5 uppercase tracking-wider')}>
                    cargo
                    <Explain label="cargo">
                      What her hold carries against what she was built to take — cargo, water and
                      food all take the same tuns. How much room a BUY really has is the server's
                      own figure, and the BUY composer shows it where the purchase is decided.
                    </Explain>
                  </dt>
                  <dd>
                    <HeroFigure
                      value={formatOfTotal(fleetHoldUsed(fleet), fleetHoldTotal(fleet))}
                      unit={`t · ${formatPct(fleetHoldUsed(fleet) / fleetHoldTotal(fleet))} full`}
                    />
                  </dd>
                </div>
              </dl>
            )}
          </Card>

          {/* ── MAKING THE ORDER ───────────────────────────────────────────────────────────── */}
          <div ref={composerRef}>
            <Card>
              <CardHeader
                eyebrow="Make"
                title="An order"
                explain="Every choice below is something that really exists right now — a port she can reach, a good this market trades, a quantity she can afford."
                /* THE COUNT IS OF WHAT IS ON THIS CARD. It read `verbs.length + 2`, and the +2 was
                   CANCEL and CLEAR — which are not composable and are not here: they are MADE on
                   the queue, where the row they act on is (domain/order/text.ts:QUEUE_VERBS). So a
                   card carrying six tiles announced "8 VERBS" and sent the player hunting for two
                   that do not exist on it. `verbs` is already `composableVerbs(...)`; counting the
                   list you rendered is the only count that cannot drift from it. */
                aside={<Badge tone="neutral">{verbs.length} verbs</Badge>}
              />
              {/* ── THE ORDER, ITS CONTROLS AND ITS CHECK STAND AT THE HEAD OF THE CARD ─────────
                  (the owner approved this placement 2026-08-23: "number 1 go"). They used to sit
                  under the pickers, which put the Issue button 1,262px from the top of the page at
                  390px once a SAIL destination was chosen — the player picked a harbour and then
                  scrolled a screen and a half to send her. The head is also the truer reading: the
                  line IS the order being written, so it forms in front of the player as each pick
                  below fills it in.

                  EXCEPT ON SAIL (the owner, 2026-08-24: "i want issue this order to be at the
                  bottom of the location i click on it, unfolding it"). A SAIL completes the moment
                  a harbour tile is tapped, so its check and its Issue live in the fold that opens
                  under that tile (`sailConfirm`, above) — and this head block keeps the forming
                  LINE and loses the button and the check while SAIL is chosen, because two Issue
                  buttons for one order is the duplication this codebase keeps deleting.

                  THIS IS ORDINARY LAYOUT, NOT BEHAVIOUR, and that is why it does not touch the
                  no-restructure law (OWNER_REQUESTS 15/25): the block is in ordinary document
                  flow, always in the same place, and nothing about it appears on press, docks, or
                  follows the scroll (the owner, 2026-08-23: "what will be sent tab stays on the
                  page until the scroll is down enough. i don't like this" — said of a sticky
                  version; it must not come back as sticky, fixed, or any other self-repositioning
                  shape).

                  THE CHECK STAYS WITH THE BUTTON IT GATES. The dry run's verdict — estimate or
                  refusal — is what disables Issue, so the two live together wherever the button
                  is: a refusal printed a screen away from the control it blocks is a reason
                  orphaned from its consequence. */}
              <div className={ORDER_BOX}>
                {/* The dot rides the section label, where the reader is already looking, rather
                    than floating alone under the line it explains. */}
                {/* "Order", not "What will be sent" (the owner, 2026-08-23: "Why add unnecessary
                    words?"). A label names the thing; the sentence that used to be the label is
                    already behind the dot. */}
                <SectionLabel className="mb-0">
                  Order
                  <Explain label="Order" dotClassName="ml-0.5">
                    {/* THE ⓘ IS PLAYER COPY, not a code comment with a dot in front of it. It said
                        "goes to cmd.issue(fleet, text, version) … (F.4)" — a function signature and
                        a design-document section, shown to somebody who is trying to buy pepper. */}
                    This is the order itself, word for word, as your clerk will write it out. Nothing
                    is added on the way: what you read here is what your fleet is told.
                  </Explain>
                </SectionLabel>
                <OrderLine text={text} live />
              </div>

              <div className="mt-3 flex flex-wrap gap-2">
                {!sailInline && (
                  <Button
                    variant="primary"
                    disabled={!ready || issuing || check.status === 'refused' || check.status === 'checking'}
                    busy={issuing}
                    busyLabel="Issuing…"
                    onClick={() => void doIssue()}
                  >
                    Issue this order
                  </Button>
                )}
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

              {/* On SAIL the check rides in the tile's fold with the button it gates. */}
              {!sailInline && (
                <div className="mt-3 border-t border-edge pt-3">
                  <PreviewPanel
                    state={check}
                    verbs={snapshot.verbs}
                    timeCompression={snapshot.config.time_compression}
                    onFix={applyFix}
                  />
                </div>
              )}

              {issued && (
                <Notice tone="success" className="mt-3 font-mono text-xs">
                  sent: {issued}
                </Notice>
              )}

              {/* The rule the head block answers to also binds what follows it: the composer sits
                  below in the same ordinary flow, and picking in it rewrites the line above by
                  state, never by anything moving. */}
              <div className="mt-4 border-t border-edge pt-4">
                <OrderComposer
                  verbs={verbs}
                  spec={spec}
                  args={args}
                  fleet={fleet}
                  snapshot={snapshot}
                  port={port}
                  market={market}
                  sailConfirm={sailConfirm}
                  onChooseVerb={chooseVerb}
                  onSetArg={setArg}
                />
              </div>
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
                destination={
                  fleet.voyage
                    ? fleet.voyage.to
                      ? portNameOf(portByCode, fleet.voyage.to)
                      : fleet.voyage.dest_point
                        ? pointLabel({ lat: fleet.voyage.dest_point[0], lon: fleet.voyage.dest_point[1] })
                        : 'open sea'
                    : null
                }
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

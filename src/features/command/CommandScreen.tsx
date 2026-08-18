import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
} from '../../components/ui'
import { formatDucats, formatRealShort, formatVoyageDays } from '../../lib/format'
import { useWorld } from '../../fixtures/useWorld'
import type { QueuedOrder } from '../../fixtures/types'
import { CheckBlock } from './CheckBlock'
import { OrderQueue } from './OrderQueue'
import { TapBuilder } from './TapBuilder'
import { useCommandDraft } from './commandDraft'
import { checkCommand } from './validate'

// CMD — THE HEART. E.1, and the only tab that changes the world.
//
// ONE GRAMMAR, TWO INPUT METHODS (F.4). There is one input box holding one string. The keyboard
// writes into it; the tap-builder writes into it; MARKET, PORT and FLEETS hand orders into it
// through the shared draft store. Nothing else composes an order, and nothing anywhere builds a
// structured object — because the server parses the STRING, and there is exactly one parser.
//
// THE CHECK LINE runs on every keystroke, client-side, against the fixture (F.5 layer 2). It is
// advisory: the server's check is the authority. That is stated on the screen, not just here.
//
// THE REACH LAW (CORE_REUSE 1.5): the input, Issue, Clear, the fix chips, the verb pad and the
// per-order cancels are ACTIONS. None of them is inside a capped or scrolling region — this screen
// has no max-h and no overflow anywhere; the page itself scrolls, which is the one scroll the law
// permits. "An action may never live inside a region that can scroll or clip it."
//
// NOT WIRED: there is no server. Issue does not send anything; it records the exact string that
// WOULD be sent to cmd.issue(fleet_id, raw_text, expected_version), and says so on screen. A
// button that pretends to have done something is worse than one that admits it has not.

export function CommandScreen() {
  const model = useWorld()
  const { text, fleetId, handoffs, setText, handOff, selectFleet, clear } = useCommandDraft()
  const inputRef = useRef<HTMLInputElement>(null)
  const [issued, setIssued] = useState<readonly { at: number; raw: string; fleet: string }[]>([])

  // Default the command to a fleet the first time the tab is opened: the one that is alongside,
  // because that is the fleet that can do anything right now.
  useEffect(() => {
    if (fleetId) return
    const docked = model.fleetViews.find((v) => v.fleet.status === 'DOCKED') ?? model.fleetViews[0]
    if (docked) selectFleet(docked.fleet.id)
  }, [fleetId, model.fleetViews, selectFleet])

  // Another tab handed an order over — put the caret where the player will keep typing.
  useEffect(() => {
    if (handoffs > 0) inputRef.current?.focus()
  }, [handoffs])

  const result = useMemo(
    () => (text.trim().length === 0 ? null : checkCommand(text, model, fleetId ?? undefined)),
    [text, model, fleetId],
  )

  const selected = fleetId ? model.fleetView(fleetId) : undefined

  const issue = () => {
    if (!result?.ok || !selected) return
    setIssued((prev) => [{ at: model.nowMs, raw: text.trim(), fleet: selected.fleet.name }, ...prev])
    clear()
  }

  const cancel = (fleetName: string, order: QueuedOrder) => {
    handOff(`CANCEL ${fleetName} ${order.seq}`)
  }

  return (
    <Screen>
      <PageHeader
        eyebrow="Orders"
        title="Command"
        subtitle="Write the order. The sea answers later."
        actions={
          <span className="font-mono text-sm text-accent">{formatDucats(model.world.player.ducats)}</span>
        }
      />

      {/* ── THE LINE ─────────────────────────────────────────────────────────────────────── */}
      <Card tone="accent">
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <SectionLabel className="mb-0">Commanding</SectionLabel>
            {model.fleetViews.map((v) => (
              <button
                key={v.fleet.id}
                type="button"
                onClick={() => selectFleet(v.fleet.id)}
                className={[
                  'min-h-11 rounded-md px-3 font-mono text-xs transition',
                  v.fleet.id === fleetId
                    ? 'bg-accent text-app'
                    : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
                ].join(' ')}
              >
                {v.fleet.name}
                <span className="ml-2 opacity-70">
                  {v.fleet.portCode
                    ? model.portOf(v.fleet.portCode).name
                    : `→ ${model.portOf(v.progress!.destination).name} ${formatRealShort(v.progress!.remainingMs)}`}
                </span>
              </button>
            ))}
          </div>

          <div className="flex items-stretch gap-2">
            <span aria-hidden className="self-center font-mono text-lg text-accent">
              &gt;
            </span>
            <input
              ref={inputRef}
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') issue()
              }}
              spellCheck={false}
              autoCapitalize="characters"
              autoCorrect="off"
              placeholder="SAIL Gaivota TO Cádiz"
              aria-label="Order line"
              className="min-h-11 min-w-0 flex-1 rounded-md border border-edge bg-app px-3 font-mono text-sm text-ink outline-none placeholder:text-ink-faint/60 focus:border-accent"
            />
          </div>

          <div className="flex flex-wrap gap-2">
            <Button variant="primary" onClick={issue} disabled={!result?.ok}>
              Issue
            </Button>
            <Button variant="ghost" onClick={clear} disabled={text.length === 0}>
              Clear line
            </Button>
          </div>

          <div className="border-t border-edge pt-3">
            <CheckBlock result={result} onInsert={(command) => handOff(command)} />
          </div>

          <p className="font-mono text-[11px] text-ink-faint">
            This check runs on your device against a cached world (F.5 layer 2). The server's check,
            inside the transaction, is the one that decides.
          </p>
        </div>
      </Card>

      {/* ── THE TAP-BUILDER ──────────────────────────────────────────────────────────────── */}
      <Card>
        <CardHeader
          eyebrow="Tap"
          title="Build an order"
          subtitle="Tap a verb, then its arguments. The same string a keyboard would type appears above."
          aside={<Badge tone="neutral">8 of 27 verbs</Badge>}
        />
        <TapBuilder
          model={model}
          selectedFleetId={fleetId}
          onEmit={(command) => handOff(command)}
        />
      </Card>

      {/* ── THE QUEUES ───────────────────────────────────────────────────────────────────── */}
      <Card>
        <CardHeader
          eyebrow="Standing"
          title="Queues"
          subtitle="One FIFO queue per fleet, twelve deep. On a failure it halts — it never skips."
        />
        <OrderQueue
          views={model.fleetViews}
          ordersFor={model.ordersFor}
          selectedFleetId={fleetId}
          onSelectFleet={selectFleet}
          onCancel={cancel}
        />
        {selected && (
          <p className="mt-4 font-mono text-[11px] text-ink-faint">
            {selected.fleet.name}: {formatVoyageDays(selected.enduranceDays)} of stores ·{' '}
            {selected.speedKn.toFixed(1)} kn · {Math.round(selected.holdFree)} t free
          </p>
        )}
      </Card>

      {/* ── WHAT WOULD HAVE BEEN SENT ────────────────────────────────────────────────────── */}
      <Card tone={issued.length > 0 ? 'warning' : 'default'}>
        <CardHeader
          eyebrow="Not wired"
          title="Issued this session"
          subtitle="No server exists yet. These are the exact strings that would go to cmd.issue()."
        />
        {issued.length === 0 ? (
          <p className="text-sm text-ink-muted">Nothing issued yet.</p>
        ) : (
          <ul className="space-y-1">
            {issued.map((entry) => (
              <li key={`${entry.at}-${entry.raw}`} className="flex flex-wrap items-baseline gap-2">
                <span className="font-mono text-[11px] text-ink-faint">{entry.fleet}</span>
                <code className="font-mono text-xs text-ink">{entry.raw}</code>
              </li>
            ))}
          </ul>
        )}
        <Notice tone="neutral" className="mt-3 text-xs">
          Nothing here was sent. The order queue above is fixture data and does not change.
        </Notice>
      </Card>
    </Screen>
  )
}

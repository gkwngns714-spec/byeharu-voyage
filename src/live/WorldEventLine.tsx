import { Icon } from '../components/ui'
import type { WorldEvent } from '../lib/rpc'
import { useT } from '../lib/i18n'
import { useShellState } from '../app/shellState'
import { PortFlag } from './PortFlag'
import { portNameOf, useWorld } from './worldStore'
import { eventsAt, useWorldEvents } from './useWorldEvents'
import { eventEffectWords, eventWhenWords } from './worldEventWords'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORLD EVENTS, WHERE A PLAYER LOOKS (0469): the Trade line (every event, each a press that puts its harbour in hand) and the
// quay's line (the events at this harbour). One read (./useWorldEvents.ts); everything printed is served: the kind, the harbour, the
// multiple or the toll, the start and the end. Nothing here decides whether an event is on (`live` is the server's).
// Dark, or with no event running or announced, both render NOTHING (no element, no space): the screens are as they were.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const TONE: Record<string, string> = {
  FAMINE: 'text-warning',
  FESTIVAL: 'text-accent',
  BLOCKADE: 'text-danger',
}

function EventWords({ e, nowMs, showPort }: { e: WorldEvent; nowMs: number; showPort: boolean }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <>
      <span className={`font-medium ${TONE[e.code] ?? 'text-ink'}`} data-testid="world-event-kind">
        {t(`events.${e.code}`)}
      </span>
      {showPort && (
        <span className="flex items-center gap-1 text-ink">
          <PortFlag code={e.port_code} /> <span data-testid="world-event-port">{portNameOf(portByCode, e.port_code)}</span>
        </span>
      )}
      <span className="tabular-nums text-ink" data-testid="world-event-effect">
        {eventEffectWords(e, t)}
      </span>
      <span className="tabular-nums text-ink-faint" data-testid="world-event-when">
        {eventWhenWords(e, nowMs, t)}
      </span>
    </>
  )
}

/** THE TRADE LINE: every event running or announced, soonest first. A press puts its harbour in hand (`onCity`), so its cards and
 *  their "Wanted ×2" are one press away; the harbour in hand is marked. Nothing while there is none.
 *  X8 (live/eventReach.ts): the desk passes `near`, and only the events it keeps stand there; Stats > News passes none and lists all. */
export function WorldEventsLine({
  city,
  onCity,
  near,
  className = 'mb-2',
}: {
  city: string | null
  onCity: (code: string) => void
  near?: (e: WorldEvent) => boolean
  className?: string
}) {
  const t = useT()
  const all = useWorldEvents()
  const events = near ? all.filter(near) : all
  const { nowMs } = useShellState()
  if (events.length === 0) return null
  return (
    <ul className={`space-y-1 ${className}`} aria-label={t('events.heading')} data-testid="world-events">
      {events.map((e) => (
        <li key={e.id}>
          <button
            type="button"
            onClick={() => onCity(e.port_code)}
            className={`flex w-full flex-wrap items-center gap-x-2 gap-y-0.5 rounded-md border px-2 py-1 text-left text-t-caption ${
              e.port_code === city ? 'border-accent bg-accent/10' : 'border-edge bg-surface'
            }`}
            data-testid="world-event"
            data-code={e.code}
            data-port={e.port_code}
            data-live={e.live || undefined}
          >
            <Icon name="wreath" size={14} />
            <EventWords e={e} nowMs={nowMs} showPort />
          </button>
        </li>
      ))}
    </ul>
  )
}

/** THE QUAY'S LINE: the events at this harbour (running or announced). Nothing while there is none. */
export function QuayEvents({ portCode }: { portCode: string | null }) {
  const events = eventsAt(useWorldEvents(), portCode)
  const { nowMs } = useShellState()
  if (events.length === 0) return null
  return (
    <div className="space-y-1" data-testid="quay-events">
      {events.map((e) => (
        <p key={e.id} className="flex flex-wrap items-center gap-x-2 text-t-caption" data-testid="quay-event" data-code={e.code} data-live={e.live || undefined}>
          <Icon name="wreath" size={14} />
          <EventWords e={e} nowMs={nowMs} showPort={false} />
        </p>
      ))}
    </div>
  )
}

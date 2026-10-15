import { useState, type ReactNode } from 'react'
import { Bar, Tray, type TrayDetent } from '../components/ui'
import { formatFixed, formatInt } from '../lib/format'
import { CHART_CHROME, hullClassOfCode, hullPath } from '../chart'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ONE SHIP, OPENED FROM HER FLEET'S PANEL — the owner, 2026-10-15:
//
//   *"First name of the ship, the type of ship, the equipment page like in runescape, where there
//    are slots. Then its spec such as attack, speed, cargo … When there are more than one ship, i
//    should be able to press the ships and see their individual spec. another slide from that tab
//    should appear and show"* — and then: *"the ship info page looks crap. make it visually
//    appealing"*.
//
// A second side panel, slid out from the fleet's (VoyageTray) or a merchant's (MerchantSheet).
// Nothing here is computed: every figure is the server's (`FleetShip`, 0074 — stats are base plus
// what is mounted) and the slot counts are `ship.slots`, which is `class_slots` plus her guns.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** WHAT THE PANEL READS — one ship as `world.ship_view` serves her (0124): your own `FleetShip` and a
 *  merchant's card ship are the same object (the card less her id and provisions). Slots, the six
 *  combat stats and `class_code` stay OPTIONAL for one release, so a bundle talking to a server
 *  older than 0124 still renders: what is not served is simply not drawn (shown, never guessed). */
export interface ShipView {
  name: string
  class: string
  /** `ship_classes.code` (0124) — the silhouette is drawn from it. */
  class_code?: string
  is_flagship: boolean
  durability: number
  max_durability: number
  crew: number
  crew_required?: number
  crew_max: number
  hold: number
  cargo_tuns: number
  speed: number
  fittings: readonly { name: string; qty: number; slot?: string }[]
  slots?: Record<string, number>
  attack?: number
  accuracy?: number
  reach?: number
  armour?: number
  handling?: number
  sighting?: number
}

// ── THE SLOT GLYPHS — one small line drawing per kind, 24-unit box, stroked in currentColor ──────
const GLYPH: Record<string, string> = {
  // a square sail on its yard and mast
  rig: 'M12 3v18M5 6h14M6 6c1 4 1 8 0 11h12c-1-3-1-7 0-11',
  // a cannon on its carriage
  weapon: 'M3 11l13-4 2 5-13 4zM18 9.5h3M7 16a2 2 0 1 0 4 0 2 2 0 1 0-4 0',
  // an anchor
  'ground-tackle': 'M12 5a2 2 0 1 0 0-.01M12 7v13M8 10h8M5 14c0 4 3 6 7 6s7-2 7-6',
  // a ship's wheel
  steering: 'M12 7a5 5 0 1 0 0 10 5 5 0 1 0 0-10M12 2v20M2 12h20M5 5l14 14M19 5L5 19',
  // a hull section / shield of planks
  hull: 'M4 6h16l-2 11a3 3 0 0 1-3 2H9a3 3 0 0 1-3-2zM5 10h14M6 14h12',
  // a spyglass
  lookout: 'M3 15l12-7 2 4-12 7zM15 8l4-2 2 4-4 2M7 18l-1 3',
  // a star flourish
  flourish: 'M12 3l2.5 6 6.5.5-5 4 1.5 6.5L12 16l-5.5 4 1.5-6.5-5-4 6.5-.5z',
}
function SlotGlyph({ kind, className = '' }: { kind: string; className?: string }) {
  const d = GLYPH[kind] ?? GLYPH.flourish
  return (
    <svg viewBox="0 0 24 24" width={22} height={22} aria-hidden className={className}>
      <path d={d} fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

/** The slot kinds in the order a reader looks down a ship — sail first, flourish last — and the
 *  word a player uses for each. The CODE is the server's (0074 `class_slots.slot`). */
const SLOT_ORDER: readonly { code: string; word: string }[] = [
  { code: 'rig', word: 'Sail' },
  { code: 'weapon', word: 'Weapon' },
  { code: 'ground-tackle', word: 'Anchor' },
  { code: 'steering', word: 'Rudder' },
  { code: 'hull', word: 'Hull' },
  { code: 'lookout', word: 'Lookout' },
  { code: 'flourish', word: 'Flourish' },
]

interface SlotBox {
  key: string
  kind: string
  word: string
  fitted: string | null
}

/** Every slot she has, one box each, filled in the order her fittings are mounted. A fitting
 *  mounted ×2 fills two boxes — it occupies two slots on the server too. */
function slotBoxes(ship: ShipView): SlotBox[] {
  // NO SLOT TABLE SERVED (a server older than 0124): her fittings, one box per piece, and no empty boxes — the
  // empties would be a guess at her class's slots.
  if (!ship.slots) {
    return ship.fittings.flatMap((f, i) =>
      Array.from({ length: f.qty }, (_, j) => ({
        key: `${i}-${j}`,
        kind: f.slot ?? 'flourish',
        word: SLOT_ORDER.find((s) => s.code === f.slot)?.word ?? 'Fitted',
        fitted: f.name,
      })),
    )
  }
  const slots = ship.slots
  const known = new Set(SLOT_ORDER.map((s) => s.code))
  const kinds = [
    ...SLOT_ORDER,
    // A kind the server adds later still gets its boxes, under its own code.
    ...Object.keys(slots)
      .filter((k) => !known.has(k))
      .map((code) => ({ code, word: code })),
  ]
  const out: SlotBox[] = []
  for (const kind of kinds) {
    const count = slots[kind.code] ?? 0
    const fitted = ship.fittings
      .filter((f) => f.slot === kind.code)
      .flatMap((f) => Array.from({ length: f.qty }, () => f.name))
    for (let i = 0; i < count; i++) {
      out.push({ key: `${kind.code}-${i}`, kind: kind.code, word: kind.word, fitted: fitted[i] ?? null })
    }
  }
  return out
}

function Heading({ children, trailing }: { children: ReactNode; trailing?: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between pb-2 pt-4">
      <h3 className="text-t-caption uppercase tracking-wider text-ink-faint">{children}</h3>
      {trailing}
    </div>
  )
}

/** THE EQUIPMENT PAGE — square slots in a grid, each with its kind's glyph; a fitted slot glows. */
function EquipmentGrid({ ship }: { ship: ShipView }) {
  const boxes = slotBoxes(ship)
  const filled = boxes.filter((b) => b.fitted !== null).length
  return (
    <section data-testid="ship-equipment">
      <Heading
        trailing={
          boxes.length > 0 && (
            <span className="text-t-caption tabular-nums text-ink-faint">{`${filled} / ${boxes.length}`}</span>
          )
        }
      >
        Equipment
      </Heading>
      {boxes.length === 0 ? (
        <p className="rounded-control bg-surface-2 px-3 py-3 text-t-caption text-ink-faint">Nothing fitted.</p>
      ) : (
        <div className="grid grid-cols-4 gap-2">
          {boxes.map((b) => {
            const on = b.fitted !== null
            return (
              <div
                key={b.key}
                data-fitted={on || undefined}
                title={on ? `${b.word}: ${b.fitted}` : `${b.word} — empty`}
                className={[
                  'relative flex aspect-square min-w-0 flex-col items-center justify-center gap-1 rounded-control p-1.5 text-center',
                  'shadow-[inset_0_1px_0_rgb(255_255_255/0.04),inset_0_-2px_4px_rgb(0_0_0/0.35)]',
                  on ? 'bg-accent/10 ring-1 ring-accent/50' : 'bg-surface-2 ring-1 ring-ink-faint/15',
                ].join(' ')}
              >
                <SlotGlyph kind={b.kind} className={on ? 'text-accent' : 'text-ink-faint/40'} />
                <span
                  className={`line-clamp-2 text-[0.6875rem] leading-tight ${on ? 'text-ink' : 'text-ink-faint/60'}`}
                >
                  {on ? b.fitted : b.word}
                </span>
              </div>
            )
          })}
        </div>
      )}
    </section>
  )
}

/** One figure in the spec: a quiet label above, the number large. */
function Stat({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div className="min-w-0 rounded-control bg-surface-2 px-3 py-2">
      <dt className="truncate text-t-caption text-ink-faint">{label}</dt>
      <dd className="truncate">
        <span className="text-t-title tabular-nums">{value}</span>
        {unit && <span className="ml-1 text-t-caption text-ink-faint">{unit}</span>}
      </dd>
    </div>
  )
}

/** A figure with its gauge: hull, crew, cargo — the three a captain reads as "how full". */
function Gauge({
  label,
  now,
  max,
  unit,
  tone,
}: {
  label: string
  now: number
  max: number
  unit?: string
  tone: 'success' | 'warning' | 'danger' | 'accent' | 'neutral'
}) {
  const pct = max > 0 ? Math.max(0, Math.min(1, now / max)) * 100 : 0
  return (
    <div className="min-w-0">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-t-caption text-ink-faint">{label}</span>
        <span className="text-t-caption tabular-nums text-ink">
          {`${formatInt(now)} / ${formatInt(max)}`}
          {unit && <span className="ml-1 text-ink-faint">{unit}</span>}
        </span>
      </div>
      <Bar pct={pct} tone={tone} label={label} className="mt-1" />
    </div>
  )
}

export function ShipPanel({ ship, onClose }: { ship: ShipView; onClose: () => void }) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  const hullPct = ship.max_durability > 0 ? ship.durability / ship.max_durability : 1
  const crewShort = ship.crew_required !== undefined && ship.crew < ship.crew_required
  const combat: { label: string; value: number | undefined }[] = [
    { label: 'Attack', value: ship.attack },
    { label: 'Accuracy', value: ship.accuracy },
    { label: 'Reach', value: ship.reach },
    { label: 'Armour', value: ship.armour },
    { label: 'Handling', value: ship.handling },
    { label: 'Sighting', value: ship.sighting },
  ]
  const shownCombat = combat.filter((c) => c.value !== undefined)

  return (
    <Tray
      mode="side-next"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={ship.name}
      data-testid="map-ship-panel"
      {...CHART_CHROME}
    >
      {/* ── THE PORTRAIT: her hull, large, on a lit plate; her type as a chip ─────────────────── */}
      <div className="flex items-center gap-4 rounded-sheet bg-gradient-to-br from-accent/15 via-surface-2 to-surface-2 p-4">
        <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full bg-surface ring-1 ring-accent/30">
          <svg width={64} height={64} viewBox="-15 -15 30 30" aria-hidden>
            <path
              d={hullPath(hullClassOfCode(ship.class_code), 13)}
              className="fill-accent stroke-chart-sea"
              strokeWidth={0.7}
              strokeLinejoin="round"
            />
          </svg>
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="rounded-chip bg-surface px-2 py-0.5 text-t-caption text-ink">{ship.class}</span>
            {ship.is_flagship && (
              <span className="rounded-chip bg-accent/20 px-2 py-0.5 text-t-caption text-accent">Flagship</span>
            )}
          </div>
          <div className="mt-3 flex flex-col gap-2">
            <Gauge
              label="Hull"
              now={ship.durability}
              max={ship.max_durability}
              tone={hullPct < 0.4 ? 'danger' : hullPct < 0.75 ? 'warning' : 'success'}
            />
            <Gauge label="Crew" now={ship.crew} max={ship.crew_max} tone={crewShort ? 'danger' : 'neutral'} />
          </div>
        </div>
      </div>

      <EquipmentGrid ship={ship} />

      {/* ── THE SPEC ─────────────────────────────────────────────────────────────────────────── */}
      <section data-testid="ship-stats">
        <Heading>Spec</Heading>
        <dl className="grid grid-cols-2 gap-2">
          <Stat label="Speed" value={formatFixed(ship.speed, 1)} unit="knots" />
          <Stat label="Cargo" value={`${formatInt(ship.cargo_tuns)} / ${formatInt(ship.hold)}`} unit="tons" />
        </dl>
        {shownCombat.length > 0 && (
          <dl className="mt-2 grid grid-cols-3 gap-2">
            {shownCombat.map((c) => (
              <Stat key={c.label} label={c.label} value={formatInt(c.value ?? 0)} />
            ))}
          </dl>
        )}
      </section>
    </Tray>
  )
}

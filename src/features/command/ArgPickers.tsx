import { Fragment, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import {
  Badge,
  Button,
  buttonClasses,
  fineClass,
  tileFieldClass,
  useTileCols,
  FilterBox,
  TruncationNote,
  inRowsOf,
} from '../../components/ui'
import {
  formatInt,
  formatUnitPrice,
} from '../../lib/format'
// `haversineNm` is deliberately NOT imported any more: the only thing this file used it for was a
// destination's distance, and that number belongs to the server's leg (see PortPicker's header).
import type { SnapshotPort } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'

// THE PICKERS — one per argument TYPE the server's verb schema declares (`port`, `good`, `qty`,
// `number`, `price`, `enum`). Every one of them offers REAL options read out of the world, and
// every option is a row you tap. Nothing here accepts a typed order.
//
// THE ONE TEXT BOX IN THE WHOLE TAB is the port/good FILTER, and it composes nothing: it narrows
// a list of real rows, and the choice is still a tap. With 996 ports in the chain, a list without
// a filter is a list nobody can reach the bottom of.
//
// THE REACH LAW (CORE_REUSE 1.5): "an action may never live inside a region that can scroll or
// clip it." Every option here is an action, so no picker has a max-height and none of them
// scrolls. A long list is TRUNCATED instead — the rows that are shown are whole and pressable, and
// the screen says how many more the filter is hiding. A scroll box would have hidden them too, and
// less honestly.

/**
 * How many PORTS a list may render before it starts asking the player to narrow the filter.
 *
 * IT IS NOT A GENERAL LIST LENGTH, AND IT USED TO BE. The same twelve capped the goods list too,
 * which meant a market of 68 tradeable goods offered twelve and printed "56 more — narrow the
 * filter" — the owner, 2026-08-22: *"When buy, i want all the trade goods on left side."* Twelve of
 * sixty-eight is not all of them.
 *
 * The two lists are not the same question and that is why they no longer share an answer:
 *   · PORTS are the whole world — 214 today and 996 in an earlier chain — and no sort can put the
 *     one you mean near the top, so the FILTER is the way in and a cap is honest about that.
 *   · GOODS are one port's book. It is bounded by what this harbour actually trades, and the list
 *     is already sorted by the server's own `advice`, so the rows worth buying are at the top and
 *     the rest is the tail of a catalogue rather than a haystack. GoodPicker therefore renders
 *     every row it has, and keeps the filter for reaching one by name.
 */
const MAX_PORT_ROWS = 12

/**
 * HOW MANY TILES STAND IN ONE ROW — the design system's `useTileCols()` (components/ui/useTileCols),
 * read here because BOTH tile pickers on this tab unfold a panel and a fold must land after the ROW
 * containing the pressed tile: an element spanning the grid mid-row shoves the tiles beside it
 * around, and nothing may move when a fold opens. Only the code that knows where a row ENDS can
 * place it.
 *
 * IT WAS THIS FILE'S OWN HOOK UNTIL 2026-08-26, watching a single `(min-width: 640px)` and so able
 * to answer only 2 or 3 — while `goodTileGridClass()`, drawing the same field on MARKET, went to 4
 * at `xl`. Two answers to one question that differed above 1280px, which is docs/NO_SPAGHETTI.md §1
 * question 3 ("can it disagree?") answered yes. There is now one table (components/ui/tileLayout.ts)
 * and both the class and the number are read off it.
 */


// ── port ───────────────────────────────────────────────────────────────────────────────────────

/**
 * Somewhere to sail — every place in the world, nearest sailed water first.
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * THE DISTANCE IS THE SERVER'S SAILED FIGURE, FOR EVERY ROW (0039).
 * ═══════════════════════════════════════════════════════════════════════════════════════════════
 * This picker once used a straight line (Seville read 169 nm against the server's 286 and the
 * SORT was wrong on every row), then the leg graph, which could only price one-leg neighbours and
 * left a dash on the rest. `world.reach` now serves the sailed distance from the origin to EVERY
 * place — from the same table the endurance gate and the trade scan read (sea_reaches, derived
 * from the water raster by the one pathfinder, Arctic closed, no Suez, no Panama) — so every tile
 * carries its real figure and "nearest first" is finally the whole list's order.
 *
 * WHILE THE REACH READ IS IN FLIGHT (or failed), rows print no number and group by region and
 * name — a truthful, lesser answer (docs/NO_SPAGHETTI.md §7C's mirror). A number that is wrong
 * is worse than a dash, and nothing here ever invents one.
 */
export function PortPicker({
  ports,
  reach,
  origin,
  value,
  confirm,
  onPick,
  onConsider,
}: {
  ports: readonly SnapshotPort[]
  /** Sailed nm from `origin` to every place, keyed by code (`world.reach`, 0039). Null while the
   *  read is in flight — rows then carry no figure rather than an invented one. */
  reach: Record<string, number> | null
  /** The port CODE the fleet is at (or bound for). Null when it is not known. */
  origin: string | null
  value: string | undefined
  /**
   * SAIL's confirm fold — the order line, the check and THE Issue button, built by the screen
   * that owns the issue path. When given, it unfolds directly beneath the ROW OF TILES holding
   * the chosen harbour (the owner, 2026-08-24: *"issue this order … at the bottom of the
   * location i click on it, unfolding it"*), and the chosen tile is guaranteed a place in the
   * grid so the fold always has a tile to hang from. This picker never looks inside it.
   */
  confirm?: ReactNode
  onPick: (code: string) => void
  /**
   * The row a pointer or the keyboard is ON, raised as the player runs down the list and cleared
   * when they leave it. It CHOOSES NOTHING — `onPick` is still the only thing that answers the
   * argument, and the tap that fires it is unchanged. SAIL's rail draws the named harbour on its
   * chart (OrderComposer's `considering`); every other caller passes nothing and nothing happens.
   */
  onConsider?: (code: string | null) => void
}) {
  const [filter, setFilter] = useState('')
  const cols = useTileCols()

  const rows = useMemo(() => {
    const q = fold(filter.trim())
    return ports
      .filter((p) => p.code !== origin)
      .filter((p) => foldedMatch(q, p.name, p.code, p.country))
      .map((p) => ({ port: p, nm: reach ? (reach[p.code] ?? null) : null }))
      .sort(
        (a, b) =>
          // Nearest sailed water first — every row carries the server's own figure now (0039).
          // While the reach is still loading, rows fall back to region and name: a stable,
          // readable order, never a ranking by a number that was invented to rank it.
          Number(b.nm !== null) - Number(a.nm !== null) ||
          (a.nm ?? 0) - (b.nm ?? 0) ||
          a.port.region.localeCompare(b.port.region) ||
          a.port.name.localeCompare(b.port.name),
      )
  }, [ports, reach, origin, filter])

  // THE CHOSEN HARBOUR ALWAYS HAS A TILE when the confirm fold rides this picker: a destination
  // handed off from FLEETS (or filtered away) may fall outside the twelve nearest, and a fold
  // with no tile to hang from would strand the order's one Issue button nowhere. She is appended
  // rather than promoted, so the nearest-first order of the honest twelve never re-shuffles.
  const sliced = rows.slice(0, MAX_PORT_ROWS)
  const shown =
    confirm !== undefined && value !== undefined && !sliced.some((r) => r.port.code === value)
      ? [
          ...sliced,
          ...ports
            .filter((p) => p.code === value)
            .map((p) => ({ port: p, nm: reach ? (reach[p.code] ?? null) : null })),
        ]
      : sliced
  const routed = shown.some((r) => r.nm === null)

  // The grid, as ROWS of `cols` tiles — chunked here because the confirm fold must land after
  // the WHOLE ROW containing the chosen tile: an element spanning the grid mid-row would push
  // the rest of that row's tiles around, and nothing may move when a fold opens.
  const tileRows = inRowsOf(shown, cols)

  return (
    <div className="space-y-2">
      {/* "Filter ports" — a placeholder names the control; one that explains its own matching
          rules is teaching, not labelling (the owner's 2026-08-23 label sweep). */}
      <FilterBox value={filter} onChange={setFilter} label="Filter ports" />
      {shown.length === 0 && (
        <p className="text-sm text-ink-muted">No port answers to that. Clear the filter to see them all.</p>
      )}
      {/* ── TILES, NOT SENTENCES (the owner, 2026-08-23: "all the port is alligned by sentence.
          make it like a cube"). A harbour used to be a full-width row that read as a line of
          prose; it is now a TILE in a grid — the name is the title, the sailed distance is the
          hero figure beneath it (docs/UI_DIRECTION.md §4 rule 2), and the eye scans a field of
          harbours instead of reading down a column.

          TWO ACROSS AT 390px, three from `sm` (useTileCols). Measured: a 390px phone gives each
          of two tiles ~167px of content, which holds "São Vicente" on one wrapped line without
          truncating — names WRAP, never ellipsize, because a harbour you cannot read is a harbour
          you cannot choose. Three across at 390px would be ~106px, which crushes both the name
          and the figure.

          THE TAP CHOOSES — AND THE ORDER COMPLETES BENEATH THE TILE. The first reading of the
          owner's 2026-08-23 instruction sent "what sail needs" to a docked sheet at the foot of
          the screen; their 2026-08-24 correction is the spelling that stands: *"i want issue this
          order to be at the bottom of the location i click on it, unfolding it, but without
          making a new screen."* So the tap still COMMITS the destination (nothing else moves —
          the grid never re-sorts on a choice), and the `confirm` fold — the line, the check, the
          Issue — unfolds after the ROW holding the chosen tile, exactly the BUY good row's
          pattern. The chart still rings the chosen harbour (OrderComposer's `chartPorts`).

          THE SORT IS UNCHANGED: nearest sailed water first, then region and name. A grid reads
          left-to-right then down, so "nearest first" still puts the passages worth taking in the
          top rows. */}
      {tileRows.map((row) => (
        <Fragment key={row[0].port.code}>
          {/* The design system's ONE field (tileLayout.ts) — the same table `useTileCols()` chunked
              the rows above with, so the fold's placement and the CSS cannot disagree about where a
              row ends. This was an inline `gridTemplateColumns` under a comment warning that a
              Tailwind `sm:grid-cols-3` here "would be a second author of that number"; the warning
              was right and the fix was to give the number ONE author, not to hand-roll the grid. */}
          <div className={tileFieldClass()}>
            {row.map(({ port, nm }) => (
              <button
                key={port.code}
                type="button"
                onClick={() => onPick(port.code)}
                aria-expanded={confirm !== undefined ? value === port.code : undefined}
                // The pointer/keyboard "considering" events name this harbour on SAIL's chart as
                // the player runs across the grid. A thumb raises neither, which is why nothing
                // depends on them: on the phone the chart follows the CHOICE (the tap above).
                onPointerEnter={onConsider && (() => onConsider(port.code))}
                onPointerLeave={onConsider && (() => onConsider(null))}
                onFocus={onConsider && (() => onConsider(port.code))}
                onBlur={onConsider && (() => onConsider(null))}
                className={buttonClasses(
                  value === port.code ? 'chip-soft' : 'chip',
                  'md',
                  'flex min-h-11 flex-col items-stretch gap-1 px-3 py-2 text-left',
                )}
              >
                <span className="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-sm leading-snug">
                  {port.name}
                  {port.is_ice_closed && <Badge tone="warning">ice</Badge>}
                </span>
                {/* The sailed water is the tile's hero. Never a great circle — see this
                    component's header; a dash only ever means the reach read has not landed. */}
                <span className="font-mono text-base leading-none tabular-nums text-ink">
                  {nm === null ? (
                    <span className="text-ink-faint">—</span>
                  ) : (
                    <>
                      {formatInt(Math.round(nm))}
                      <span className="ml-1 text-[10px] font-normal text-ink-faint">nm</span>
                    </>
                  )}
                </span>
                {/* The CODE stays on the tile: it is the spelling the order line carries ("SAIL …
                    TO CAD"), and unlike a good's code it is not derivable from the name.
                    "shipyard", not "yard" — the owner asked what a yard was, and jargon a player
                    must ask about is a bug (docs/UI_DIRECTION.md §3a trap 3). */}
                <span className={fineClass('block')}>
                  {port.code} · {port.country}
                  {port.has_yard ? ' · shipyard' : ''}
                </span>
              </button>
            ))}
          </div>
          {/* THE CONFIRM FOLD — after the whole row holding the chosen tile, so the tiles beside
              her hold perfectly still and only what is BELOW moves down, which is what an unfold
              is. Rendered, not owned: the node is the screen's (see the prop's doc). */}
          {confirm !== undefined && row.some((r) => r.port.code === value) && confirm}
        </Fragment>
      ))}
      {routed && (
        <p className={fineClass()}>
          Distances are still being fetched — every figure, when it lands, is the sailed water
          from where she lies, never a straight line.
        </p>
      )}
      <TruncationNote hidden={rows.length - shown.length} />
    </div>
  )
}

// ── good ───────────────────────────────────────────────────────────────────────────────────────


// ── number / price / enum ──────────────────────────────────────────────────────────────────────

/** A bounded whole number — crew, a repair percentage, days of stores. Never a free-form field. */
export function NumberPicker({
  min,
  max,
  step,
  suggestions,
  coarse,
  unit,
  value,
  onPick,
}: {
  min: number
  max: number
  step: number
  suggestions: readonly number[]
  /**
   * COARSE JUMPS FOR A BIG RANGE (the owner, 2026-08-23: *"how many crew to hire, have it + 10,
   * +100, max, make it more friendly"*). Each entry is a `+n` chip that ADDS to the current figure
   * — relative, where `suggestions` are absolute — and giving the prop at all also raises a
   * `max` chip that sets the ceiling itself.
   *
   * A JUMP THAT WOULD OVERSHOOT CLAMPS TO THE CEILING, IT IS NEVER DEAD: `+100` with 12 berths
   * left signs 12, because a chip that goes grey exactly when the player reaches for it is a
   * refusal wearing a control's clothes. The ceiling is `max`, which the CALLER owes to the
   * server's own bound (for HIRE that is `fleetCrew().berths` — the very sum E_CREW_MAX counts,
   * 0007:659 — so nothing offered here is a number the server would refuse for size).
   */
  coarse?: readonly number[]
  unit?: string
  value: string | undefined
  onPick: (value: string) => void
}) {
  const numeric = value && /^[0-9]+$/.test(value) ? Number(value) : null
  const current = numeric ?? min
  const clamp = (n: number) => String(Math.max(min, Math.min(max, Math.round(n))))

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {suggestions
          .filter((n) => n >= min && n <= max)
          .map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => onPick(String(n))}
              // Another of the audit's hand-written chips. `md` already carries `text-sm`, so the
              // only thing this recipe still asks for by name is the mono face every figure wears.
              className={buttonClasses(numeric === n ? 'chip-on' : 'chip', 'md', 'font-mono')}
            >
              {n}
              {unit && <span className="ml-1 text-[11px] opacity-70">{unit}</span>}
            </button>
          ))}
        {/* The coarse jumps. `+n` builds on what is already chosen (nothing chosen counts as
            nought, so the first `+10` reads 10) and clamps to the ceiling. Never `chip-on`: like
            QtyPicker's MAX, a jump SETS the number rather than becoming the value. */}
        {coarse?.map((n) => (
          <button
            key={`+${n}`}
            type="button"
            onClick={() => onPick(clamp((numeric ?? 0) + n))}
            className={buttonClasses('chip', 'md', 'font-mono')}
          >
            +{formatInt(n)}
          </button>
        ))}
        {coarse && (
          // JUST "MAX" — the owner, 2026-08-23, of this very chip on HIRE: "what is max 12 in
          // hire? just max is enough." The figure it lands on is already the caption's own
          // `1–12 crew` below, and on HIRE the fleet rail states the empty berths beside it.
          <button
            type="button"
            disabled={max <= 0}
            onClick={() => onPick(String(max))}
            className={buttonClasses('chip', 'md', 'font-mono text-xs uppercase tracking-wider')}
          >
            max
          </button>
        )}
      </div>
      {max > min && (
        <div className="flex items-center gap-2">
          {/* The same stepper pair as QtyPicker's, drawn the same way and for the same reasons —
              see the comment there for why both glyphs stay as text. */}
          <Button
            variant="chip"
            size="icon"
            aria-label="Less"
            onClick={() => onPick(clamp(current - step))}
            className="shrink-0 text-lg"
          >
            −
          </Button>
          <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={current}
            aria-label={unit ?? 'Amount'}
            onChange={(e) => onPick(clamp(Number(e.target.value)))}
            className="h-11 min-w-0 flex-1 accent-accent"
          />
          <Button
            variant="chip"
            size="icon"
            aria-label="More"
            onClick={() => onPick(clamp(current + step))}
            className="shrink-0 text-lg"
          >
            +
          </Button>
        </div>
      )}
      <p className={fineClass()}>
        {formatInt(min)}–{formatInt(max)}
        {unit ? ` ${unit}` : ''} · now {numeric === null ? '—' : formatInt(numeric)}
      </p>
    </div>
  )
}

/** A price ceiling or floor. Offered around the market's own price, never as an empty box. */
export function PricePicker({
  reference,
  op,
  value,
  onPick,
}: {
  /** What the good costs (BUY) or fetches (SELL) right now. */
  reference: number
  op: string | undefined
  value: string | undefined
  onPick: (value: string) => void
}) {
  const offers = [0.9, 0.95, 1, 1.05, 1.1].map((m) => Math.round(reference * m))
  const min = Math.max(1, Math.round(reference * 0.5))
  const max = Math.max(min + 1, Math.round(reference * 1.5))
  return (
    <div className="space-y-2">
      <p className={fineClass()}>
        the market is at {formatUnitPrice(reference)} · your limit {op ?? ''}
      </p>
      <NumberPicker
        min={min}
        max={max}
        step={Math.max(1, Math.round(reference / 50))}
        suggestions={offers}
        unit="d."
        value={value}
        onPick={onPick}
      />
    </div>
  )
}

/** One of a fixed set of words the server's schema itself names. */
export function EnumPicker({
  values,
  value,
  onPick,
}: {
  values: readonly string[]
  value: string | undefined
  onPick: (value: string) => void
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {values.map((v) => (
        <button
          key={v}
          type="button"
          onClick={() => onPick(v)}
          // The last of the audit's hand-written chips in this file. Same recipe as QtyPicker's
          // ALL/HALF, which is the whole point: one word from the server's schema, drawn the one way.
          className={buttonClasses(
            value === v ? 'chip-on' : 'chip',
            'md',
            'font-mono text-xs uppercase tracking-wider',
          )}
        >
          {v}
        </button>
      ))}
    </div>
  )
}


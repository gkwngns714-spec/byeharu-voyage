import { useRef, useState } from 'react'
import { Button, cornerSlotClass, Icon, useDismiss } from '../components/ui'
import { zoomPercent } from './chartView'
import { MAP_LAYERS, setMapLayer, useMapLayer, type MapLayer } from './regionsFilter'
import { CHART_CHROME, type ChartSurface } from './useChartSurface'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE VIEW CONTROLS — the one +/−/find column every chart surface wears.
//
// Two callers on day one (§7B: that is the definition of a shared authority, so it lives in the
// chart layer, not in either screen): the Map tab, whose column this was, and `SmallChart`, which
// grew gestures on 2026-08-23 and needs the SAME three buttons — on an embedded chart they are the
// whole of zoom, because the wheel there belongs to the page (see useChartSurface's header). One
// component, so the buttons, their 44 px size, their corner, and their chrome marker can never
// drift between the two surfaces.
//
// ── FIND, NOT FIT — AND NOW A GLYPH, NOT A WORD ────────────────────────────────────────────────
// The third control is not new. It first read `fit`, a chart programmer's word for an act the
// player thinks of as "where is my ship" — renamed under the owner's no-insider-jargon map rule —
// and then the owner cut the word itself (2026-08-23: *"find button on map, sail, it is not
// correct. have a symbol instead"*): it now wears the `locate` crosshair, with the full sentence
// kept as its accessible name. It returns to the opening frame by FORGETTING the player's moves
// (useChartSurface's `fit`), so there is only ever one definition of where a chart opens; what
// that frame HOLDS differs by surface (the tab: your fleets; SmallChart: her berth and the
// harbours of the order), which is why the aria sentence is the caller's to say.
//
// ── THE FOURTH BUTTON: REGIONS (row 93, 2026-09-14) ────────────────────────────────────────────
// The owner: *"make filter so that i can choose to apply color, or return to the current state."*
// One toggle, under the three, right-aligned in the same column, 44 px tall: the `regions` glyph
// and the one word "Regions" — the owner's map rule allows an icon and a short word, and a
// filter with no word is a button nobody can name. Pressed = on: `aria-pressed`, and the accent
// on its border and ink (brass means "yours/on" everywhere on this chart). It reads and writes the ONE store
// in ./regionsFilter.ts, so both surfaces flip together and a reload finds it where it was left.
// It is here, not on a screen, for the reason the other three are: two surfaces wear this
// column, and a switch that lived on one of them would be a second switch on the other.
//
// ── 2026-11-15: THE FOURTH BUTTON IS A FILTER OF THREE ───────────────────────────────────────────
// The owner: *"also in map, make filter, like regions, no in regions, have option to see seas, showing
// waves, requirement to pass etc."* The same button, in the same place, now opens a short list: Off,
// Regions, Seas — one at a time (./regionsFilter.ts keeps the choice). It reads the layer that is on
// ("Regions", "Seas") or "Filter" when none is, and is pressed (brass) while one is. The list hangs
// under it, right-aligned to the column's edge, out of the flow, gone on a pick, a press outside or
// Escape. A surface that draws no seas (`SmallChart`) offers Off and Regions only (`seas` false).
//
// ── WHY IT IS SAFE TO SIT ON THE GLASS ─────────────────────────────────────────────────────────
// `CHART_CHROME` makes it invisible to every gesture (a press here never pans), the corner is
// `cornerSlotClass`'s — the same table every `Corner` reads, never a hand-written inset — and being
// chrome, `useChromeBoxes` measures it into `surface.chromeBoxes`, so a port's name is never
// printed underneath it (the Saint-Malo defect, ./useChartSurface.ts). A corner slot cannot be
// panned, scrolled or clipped away, which is what lets a control live on a pannable picture at all
// (docs/CORE_REUSE.md §1.5).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function ViewControls({
  surface,
  findAriaLabel,
  findTestId,
  testId,
  seas = false,
}: {
  /** The surface these buttons steer — `zoomIn`, `zoomOut` and `fit`— plus `view`, which they only
   *  READ, to print how far in the chart is. */
  surface: Pick<ChartSurface, 'zoomIn' | 'zoomOut' | 'fit' | 'view'>
  /** What "find" finds ON THIS SURFACE — e.g. "Find your fleets". The frame is the surface's own. */
  findAriaLabel: string
  findTestId?: string
  testId?: string
  /** Whether this surface draws the sea zones (the Map tab): the filter then offers Seas too. */
  seas?: boolean
}) {
  const t = useT()
  const zoom = surface.view ? zoomPercent(surface.view.spanX) : 0
  return (
    <div
      {...CHART_CHROME}
      // ONE RIGHT EDGE (2026-11-14): everything in the column ends on the glass's own inset. The percent used to
      // stretch to the width of the word under it and the three buttons hung left of both, a ragged stack.
      className={`pointer-events-auto absolute z-10 ${cornerSlotClass('top-right')} flex flex-col items-end gap-1`}
      data-testid={testId}
    >
      {/* HOW FAR IN YOU ARE (owner, 2026-10-12: *"show me in map how much i zoomed in and zoomed
          out in percentage"*). 0% is the whole world, 100% the tightest the chart allows, and the
          scale is LOGARITHMIC because the zoom is — ./chartView.ts `zoomPercent` carries the
          reasoning. It sits ABOVE the + and − it describes, in the same column, and it is read-only
          chrome: a number, never a control, so there is nothing here to mis-tap while zooming.

          `aria-live="polite"` so it is announced when it changes rather than read out of order,
          and `tabular-nums` so 8% and 86% do not shuffle the column's width as you press. */}
      <div
        className="min-w-11 rounded-md bg-surface/90 px-1 py-0.5 text-center text-t-caption tabular-nums text-ink-faint backdrop-blur"
        data-testid="map-zoom-percent"
        data-zoom-percent={zoom}
        aria-live="polite"
        aria-label={`Zoom ${zoom}%`}
      >
        {zoom}%
      </div>
      <Button
        variant="secondary"
        size="icon"
        aria-label={t('chart.zoomIn')}
        onClick={surface.zoomIn}
        className="bg-surface/90 backdrop-blur"
      >
        +
      </Button>
      <Button
        variant="secondary"
        size="icon"
        aria-label={t('chart.zoomOut')}
        onClick={surface.zoomOut}
        className="bg-surface/90 backdrop-blur"
      >
        −
      </Button>
      {/* A GLYPH, NOT A WORD (the owner, 2026-08-23: "find button on map, sail, it is not
          correct. have a symbol instead"). + and − are symbols; a word in their column sat
          oddly among them. The crosshair is `locate` (icons.ts), drawn for this control; the
          accessible NAME stays the caller's full sentence — an icon nobody can name is worse
          than a word, so the aria-label is not optional here. */}
      <Button
        variant="secondary"
        size="icon"
        aria-label={findAriaLabel}
        onClick={surface.fit}
        className="bg-surface/90 backdrop-blur"
        data-testid={findTestId}
      >
        <Icon name="locate" size={16} />
      </Button>
      <LayerFilter seas={seas} />
    </div>
  )
}

const LAYER_WORD: Record<MapLayer, 'chart.filter' | 'chart.regions' | 'chart.seas'> = {
  off: 'chart.filter',
  regions: 'chart.regions',
  seas: 'chart.seas',
}
const CHOICE_WORD: Record<MapLayer, 'chart.layerOff' | 'chart.regions' | 'chart.seas'> = {
  off: 'chart.layerOff',
  regions: 'chart.regions',
  seas: 'chart.seas',
}

/** The filter's one button and its list — its own component so the store subscription re-renders
 *  the button alone, not the column. */
function LayerFilter({ seas }: { seas: boolean }) {
  const t = useT()
  const stored = useMapLayer()
  // a surface that draws no seas reads a kept "Seas" as off
  const layer: MapLayer = stored === 'seas' && !seas ? 'off' : stored
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLDivElement | null>(null)
  useDismiss(open, box, () => setOpen(false))
  const choices = MAP_LAYERS.filter((l) => seas || l !== 'seas')
  const on = layer !== 'off'
  return (
    <div ref={box} className="relative self-end">
      <Button
        variant="secondary"
        size="sm"
        aria-pressed={on}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className={`min-h-11 gap-1.5 bg-surface/90 backdrop-blur ${on ? 'border-accent text-accent' : ''}`}
        data-testid="map-layer-filter"
        data-layer={layer}
      >
        <Icon name="regions" size={16} />
        {t(LAYER_WORD[layer])}
      </Button>
      {open && (
        <div
          role="menu"
          aria-label={t('chart.filter')}
          className="absolute right-0 top-full z-40 mt-1 flex min-w-full flex-col rounded-tile bg-surface-2 p-1 shadow-float"
          data-testid="map-layer-menu"
        >
          {choices.map((l) => (
            <button
              key={l}
              type="button"
              role="menuitemradio"
              aria-checked={l === layer}
              onClick={() => {
                setMapLayer(l)
                setOpen(false)
              }}
              className={`flex min-h-11 items-center gap-2 whitespace-nowrap rounded-control px-3 text-left text-t-body ${
                l === layer ? 'text-accent' : 'text-ink'
              } hover:bg-surface`}
              data-testid={`map-layer-${l}`}
            >
              <span aria-hidden="true" className="w-3 text-center">
                {l === layer ? '●' : ''}
              </span>
              {t(CHOICE_WORD[l])}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

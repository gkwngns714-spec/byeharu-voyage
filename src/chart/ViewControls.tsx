import { Button, Icon, overlaySlotClass } from '../components/ui'
import { CHART_CHROME, type ChartSurface } from './useChartSurface'

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
// ── WHY IT IS SAFE TO SIT ON THE GLASS ─────────────────────────────────────────────────────────
// `CHART_CHROME` makes it invisible to every gesture (a press here never pans), the corner is
// `overlaySlotClass`'s — the same table every panel reads, never a hand-written inset — and being
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
}: {
  /** The surface these buttons steer — `zoomIn`, `zoomOut` and `fit` are all they touch. */
  surface: Pick<ChartSurface, 'zoomIn' | 'zoomOut' | 'fit'>
  /** What "find" finds ON THIS SURFACE — e.g. "Find your fleets". The frame is the surface's own. */
  findAriaLabel: string
  findTestId?: string
  testId?: string
}) {
  return (
    <div
      {...CHART_CHROME}
      className={`pointer-events-auto absolute z-10 ${overlaySlotClass('top-right')} flex flex-col gap-1`}
      data-testid={testId}
    >
      <Button
        variant="secondary"
        size="icon"
        aria-label="Zoom in"
        onClick={surface.zoomIn}
        className="bg-surface/90 backdrop-blur"
      >
        +
      </Button>
      <Button
        variant="secondary"
        size="icon"
        aria-label="Zoom out"
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
    </div>
  )
}

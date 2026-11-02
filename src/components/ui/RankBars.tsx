import type { ReactNode } from 'react'
import { Bar, type BarTone } from './Bar'
import { Figure, type FigureTone } from './Figure'
import { useT } from '../../lib/i18n'
import { Row } from './Row'

// RANKED BARS — a short list in order, each row's bar drawn against the biggest in the list.
//
// THE QUESTION IT ANSWERS is the one a list of figures cannot: which of these is big. Five money
// flows printed as five numbers are five numbers; the same five with a bar under each are a shape
// the eye reads before the digits. The Stats tab wanted it in six places — the world's flows by
// kind (twice over), the goods that rose, fell and traded most, a city's best-sold and best-bought
// goods, the merchants' best and worst day — and it is the same recipe in all six.
//
// IT IS BUILT OUT OF `Row` AND `Bar`, not out of a new skin: the rows keep the 52px band, the
// hairline between them, the tabular figure on the right and the touch floor, and the bar sits in
// the row's second line (`children`), which is what that slot is for.
//
// THE BAR IS A PROPORTION OF THE LIST, NOT OF A TOTAL. The widest row is full, everything else is
// measured against it, and the figures carry the real sizes — the honest reading of "ranked", and
// the only one available when the values are a mix of signs (a flow in and a flow out).

export interface RankRow {
  id: string
  label: ReactNode
  /** What the row is worth. Its MAGNITUDE sets the bar; the sign may set the tone. */
  value: number
  /** The bar's and the figure's meaning. Default: `accent` — a quantity of yours. */
  tone?: BarTone
  /** A second caption under the label, above the bar. */
  note?: ReactNode
  /** The reading on the right, when it is not `format(value)` (units beside money, a percentage). */
  text?: string
}

const FIGURE_TONE: Record<BarTone, FigureTone> = {
  accent: 'ink',
  success: 'success',
  warning: 'warning',
  danger: 'danger',
  info: 'info',
  neutral: 'muted',
}

export function RankBars({
  rows,
  format,
  empty,
  rules = true,
  className = '',
  ...rest
}: {
  /** In the order they are to be read — this component sorts nothing. */
  rows: readonly RankRow[]
  /** How a row's figure reads (lib/format owns the spelling). */
  format: (v: number) => string
  /** The 1px rule between rows. Off in a card (2026-11-02, the page layout: whitespace parts rows, a rule parts groups). */
  rules?: boolean
  /** The one row drawn instead of an empty list. */
  empty?: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  const t = useT()
  if (rows.length === 0) {
    return <Row label={empty ?? t('ui.nothingYet')} tone="muted" hairline={false} className={className} {...rest} />
  }
  // The true widest row, and 1 only when every row is nought — flooring it at 1 would draw a list
  // of half-percent movers as a row of stubs.
  const widest = Math.max(...rows.map((r) => Math.abs(r.value))) || 1

  return (
    <div className={className} {...rest}>
      {rows.map((r, i) => {
        const tone = r.tone ?? 'accent'
        return (
          <Row
            key={r.id}
            label={r.label}
            value={<Figure value={r.text ?? format(r.value)} tone={FIGURE_TONE[tone]} />}
            hairline={rules && i < rows.length - 1}
          >
            {r.note !== undefined && <span className="block text-t-caption text-ink-faint">{r.note}</span>}
            <Bar pct={(Math.abs(r.value) / widest) * 100} tone={tone} className="mt-1" />
          </Row>
        )
      })}
    </div>
  )
}

import type { HTMLAttributes, TdHTMLAttributes, ThHTMLAttributes } from 'react'

// Design-system TABLE — the primitive this game is actually made of. A trade ledger is columns of
// numbers, so the table is a first-class primitive here, not an afterthought.
//
// TWO RULES, both structural rather than stylistic:
//   1. THE TABLE SCROLLS, THE PAGE DOES NOT. <Table> wraps its <table> in an `overflow-x-auto`
//      box, so a manifest with eight columns scrolls INSIDE its panel on a 320px phone and can
//      never push the page sideways.
//   2. NUMBERS ARE MONO AND RIGHT-ALIGNED. `align="num"` on a cell does both; the mono token
//      carries tabular figures (see src/index.css), so a column of figures lines up on the
//      decimal. A number in the prose font in a column is a bug, not a preference.
//
// Composition, not configuration: no columns/rows props. Screens write real table markup so a
// cell can hold a badge, a button or a link without the primitive growing a slot for each.

export function Table({ className = '', children, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={`-mx-1 overflow-x-auto px-1 ${className}`} {...rest}>
      <table className="w-full min-w-full border-collapse text-sm">{children}</table>
    </div>
  )
}

/** Column headings: mono, uppercase, faint — the ledger's ruled header line. */
export function TH({
  align = 'text',
  className = '',
  children,
  ...rest
  // `align` is Omitted from the native attrs on purpose: HTML's own (deprecated) align attribute
  // is typed 'left'|'center'|'right'|… and intersecting it with ours collapses to `never`.
  // Ours is a SEMANTIC choice — text or number — and the alignment follows from it.
}: Omit<ThHTMLAttributes<HTMLTableCellElement>, 'align'> & { align?: 'text' | 'num' }) {
  return (
    <th
      scope="col"
      className={`border-b border-edge px-2 py-2 font-mono text-[11px] font-normal uppercase tracking-wider text-ink-faint ${
        align === 'num' ? 'text-right' : 'text-left'
      } ${className}`}
      {...rest}
    >
      {children}
    </th>
  )
}

export function TD({
  align = 'text',
  className = '',
  children,
  ...rest
}: Omit<TdHTMLAttributes<HTMLTableCellElement>, 'align'> & { align?: 'text' | 'num' }) {
  return (
    <td
      className={`border-b border-edge/50 px-2 py-2 align-baseline text-ink ${
        align === 'num' ? 'text-right font-mono' : 'text-left'
      } ${className}`}
      {...rest}
    >
      {children}
    </td>
  )
}


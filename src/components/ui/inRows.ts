// Chunking a list into rows is not a component, and a .tsx that exports a plain function breaks
// fast refresh — so it lives in its own file. Moved out of tradePickers 2026-09-01.

/** Chunk a list into ROWS of `cols`, so a fold can be placed after a whole row. Both pickers below
 *  need it, so it is written once rather than twice in the same file. */
export function inRowsOf<T>(items: readonly T[], cols: number): T[][] {
  const rows: T[][] = []
  for (let i = 0; i < items.length; i += cols) rows.push(items.slice(i, i + cols))
  return rows
}

// WHAT A SOURCE ADDS, AS ROWS — one row per bonus: the source's words on the left, the effect on the
// right, both EXACTLY as the server words them, on the quiet surface. Two faces print it: a ship's
// skill bonuses (ShipPanel, 0133: "Portuguese Medium Hulls III · +12% sighting") and a fleet's crew
// bonuses (CrewBonuses, 0157: "Ana de Sousa · Navigator · Captain's cabin · +4% speed"). On
// 2026-10-18 tests/duplication.spec.ts found the row hand-written in both at 100 % — the shape the
// chip recipe once took twelve times (buttonStyles.ts:31-35) — so it is written here once and
// both ask for it (docs/NO_SPAGHETTI.md §5).
//
// PURE PROPS: the caller decides whether the section is drawn at all (a fleet whose captains add
// nothing draws nothing) and hands the served words; nothing is summed, sorted or formatted here.

export interface BonusRow {
  key: string
  /** Who or what adds it — the server's line, printed whole, truncated when the glass is narrow. */
  source: string
  /** What it adds — the server's figure and unit, never recomputed. */
  effect: string
}

export function BonusRows({ rows }: { rows: readonly BonusRow[] }) {
  return (
    <ul className="flex flex-col gap-1">
      {rows.map((r) => (
        <li key={r.key} className="flex items-baseline justify-between gap-3 rounded-control bg-surface-2 px-3 py-2">
          <span className="min-w-0 truncate text-t-caption text-ink">{r.source}</span>
          <span className="shrink-0 text-t-caption tabular-nums text-accent">{r.effect}</span>
        </li>
      ))}
    </ul>
  )
}

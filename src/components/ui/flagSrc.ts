// THE FLAG'S FILE AND SIZES (2026-10-18) — beside Flag.tsx, because a component file may export only
// components (react-refresh). Read Flag.tsx's header for what a flag is and who draws one; the chart's
// names (src/chart/LabelsLayer.tsx) draw the same file through `flagSrc`.

/** The three heights, in CSS pixels (2026-10-18: a step up from 12/14/18 — the owner could not
 *  find the flags at 12 px); the width is always 1.5 × the height (a 3:2 box). */
export const FLAG_SIZES = { caption: 14, body: 16, title: 20 } as const
export type FlagSize = keyof typeof FLAG_SIZES

/** The bundled picture for a server nation code (`PRT` → `/byeharu-voyage/flags/PRT.svg`). */
export function flagSrc(code: string): string {
  return `${import.meta.env.BASE_URL}flags/${code}.svg`
}

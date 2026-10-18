// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FLAG — a nation's flag, drawn the one way everywhere (the owner, 2026-10-18: "flag images
// for each city … beside the name show flag … when pressing a ship or city, also show flag").
//
// WHAT IT IS: one nation code → one bundled picture, `public/flags/<code>.svg` (licences and
// sources: public/flags/SOURCES.md). The code is the server's (`public.nations.code`, served in
// every payload that names a nation); this file holds no table of nations and no rule about who
// holds what — it is handed the code and the name and draws them.
//
// WHERE IT LIVES AND WHY: the design system, beside Icon, because it is a mark like an icon — pure
// props, reads no store. Its callers are the live wrappers that know WHICH nation: HullCountry (a
// hull's, a merchant's, a company's, the picker's) and PortFlag (a city's, through `portNationOf`),
// plus the Codex's nation rows. The chart's names draw the same file through `flagSrc` and the
// same 3:2 box (src/chart/LabelsLayer.tsx), because an <img> cannot stand inside an <svg>.
//
// THE SIZE SCALE is three steps tied to the type ladder (docs/UI_DIRECTION.md §4.1): `caption`
// beside a caption line, `body` beside a row's label, `title` beside a tray's name. The box is
// always 3:2; a flag of another shape (Denmark 37:28, Genoa 2:1, a swallow-tailed standard) is
// fitted inside it, never cropped, so a row of flags lines up and no flag is cut.
//
// WRONG SHAPE, AND HOW ANYONE WOULD FIND OUT: a nation with no file draws a broken picture —
// tests/flags.spec.ts fails first, because it holds the nations of the migrations against the
// files in public/flags.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { FLAG_SIZES, flagSrc, type FlagSize } from './flagSrc'

export function Flag({
  code,
  name,
  size = 'body',
  className = '',
}: {
  /** The server's nation code. */
  code: string
  /** The nation's name — the picture's accessible name and its tooltip. */
  name: string
  size?: FlagSize
  className?: string
}) {
  const height = FLAG_SIZES[size]
  return (
    <img
      src={flagSrc(code)}
      alt={name}
      title={name}
      width={height * 1.5}
      height={height}
      draggable={false}
      decoding="async"
      // The edge is IN the file (every flag ends in a 1.5 px mid-grey hairline along its own outline,
      // public/flags/SOURCES.md), so a white flag reads on the pale surface and a dark one on the
      // night chart, the same here and on the chart's names; `object-contain` fits any shape uncut.
      className={`inline-block shrink-0 object-contain align-[-0.15em] ${className}`}
      data-testid="flag"
      data-nation={code}
    />
  )
}

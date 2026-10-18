import { flagSrc } from '../components/ui'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CHART'S FLAGS, ONE SYMBOL PER NATION (2026-10-18, the owner: "beside the name show flag").
//
// WHAT: every nation a harbour name on the chart carries is drawn from ONE `<symbol>` in the
// chart's `<defs>` (`#bv-flag-<code>`), and each name places a `<use>` of it — so the world view's
// ~40 flagged names cost one parse per nation, not one image decode per label (an `<image>` per
// name was measured at ~30 % more frame time while panning, PR #198).
//
// WHERE THE PICTURE COMES FROM: the same bundled file the design system's Flag draws
// (`flagSrc` → public/flags/<code>.svg, sources and licences in public/flags/SOURCES.md), fetched
// once per nation and inlined. No second copy of any flag lives in code. Ids inside a file
// (ESP's `#a`, BAN's gradients) are prefixed with the nation, so two flags never share an id.
//
// UNTIL A FILE ARRIVES the `<use>` points at nothing and draws nothing — the name is set exactly
// where it would be, so nothing moves when the flag lands.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface FlagSymbol {
  readonly viewBox: string
  readonly body: string
}

const symbols = new Map<string, FlagSymbol>()
const asked = new Set<string>()
const listeners = new Set<() => void>()
let version = 0

/** The `<use href>` for a nation's symbol. */
export function flagSymbolId(code: string): string {
  return `bv-flag-${code}`
}

/** A flag file's markup → its viewBox and its body, every id in it prefixed with the nation. */
export function inlineFlag(code: string, svg: string): FlagSymbol | null {
  const open = svg.match(/<svg\b[^>]*>/)
  const viewBox = open?.[0].match(/viewBox="([^"]+)"/)?.[1]
  const end = svg.lastIndexOf('</svg>')
  if (!open || !viewBox || end < 0) return null
  const p = `${flagSymbolId(code)}-`
  const body = svg
    .slice((open.index ?? 0) + open[0].length, end)
    .replace(/\bid="([^"]+)"/g, `id="${p}$1"`)
    .replace(/\bhref="#([^"]+)"/g, `href="#${p}$1"`)
    .replace(/url\(#([^)]+)\)/g, `url(#${p}$1)`)
  return { viewBox, body }
}

export function askFlag(code: string) {
  if (asked.has(code)) return
  asked.add(code)
  fetch(flagSrc(code))
    .then((r) => (r.ok ? r.text() : Promise.reject(new Error(`${code}: ${r.status}`))))
    .then((svg) => {
      const s = inlineFlag(code, svg)
      if (!s) return
      symbols.set(code, s)
      version += 1
      for (const l of listeners) l()
    })
    // A flag that cannot be fetched is asked again on the next mount; the name is drawn without it.
    .catch(() => asked.delete(code))
}

export function subscribeFlags(l: () => void) {
  listeners.add(l)
  return () => listeners.delete(l)
}

/** Changes whenever a symbol lands (for `useSyncExternalStore`). */
export function flagsVersion(): number {
  return version
}

/** A nation's symbol, once its file has been read. */
export function flagSymbolOf(code: string): FlagSymbol | undefined {
  return symbols.get(code)
}

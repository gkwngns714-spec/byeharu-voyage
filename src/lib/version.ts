// ═══════════════════════════════════════════════════════════════════════════════════════════════
// VERSION — which build this tab runs, and which build is published (2026-10-19)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE CONCEPT: "the running build against the published build". It lives here, as a leaf under
// src/lib, because it reads nothing from the world and nothing from the store — only a constant
// the build stamped and a 60-byte file the build wrote beside index.html (vite.config.ts,
// `byeharu:build-version`, explains why both come from one value). Its one caller today is
// src/app/NewVersionToast.tsx; a second (a line on the Profile screen naming the build, say)
// reads BUILD_ID from here and never re-declares it.
//
// WHY THE OWNER NEEDED IT: he kept a tab open across deploys and reported a defect that was already
// fixed. A tab that knows its own id can ask whether a newer one is live.
//
// THE FETCH IS BUILT TO BEAT TWO CACHES. GitHub Pages serves with `max-age=600`, so (1)
// `cache: 'no-store'` keeps the browser's HTTP cache out of it, and (2) `?t=<now>` makes every
// check a distinct URL, which the CDN edge has never seen and must fetch from origin. One without
// the other serves a ten-minute-old answer, which is exactly the stale tab this exists to end.
//
// A FAILED CHECK IS SILENT, BY DESIGN. The answer to "is a newer build published?" is then "no
// idea", and the truthful lesser answer is to say nothing (docs/NO_SPAGHETTI.md §7C: a fallback
// that keeps a truthful lesser answer is correct). No toast, no error, one `console.debug` line.
// The next focus asks again.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** This build's id, `<7-char commit>+<ISO build time>`. Substituted by Vite's `define`. */
export const BUILD_ID: string = __BUILD_ID__

/** The file the build writes beside index.html, read relative to the app's base. */
export const VERSION_PATH = `${import.meta.env.BASE_URL}version.json`

/** The published build's id, or null when it could not be read (offline, a 404 while a deploy is
 *  mid-flight, a body that is not `{ id }`). Never throws. */
export async function newestBuildId(): Promise<string | null> {
  try {
    const res = await fetch(`${VERSION_PATH}?t=${Date.now()}`, { cache: 'no-store' })
    if (!res.ok) return null
    const body: unknown = await res.json()
    const id = (body as { id?: unknown } | null)?.id
    return typeof id === 'string' && id.length > 0 ? id : null
  } catch (e) {
    console.debug('[version] the published build could not be read:', e)
    return null
  }
}

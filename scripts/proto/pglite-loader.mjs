// PROTOTYPE-ONLY resolver. This worktree's `node_modules` is a junction to the main clone's, and a
// junction can go away under a concurrent agent — which is exactly what happened mid-measurement.
// The benches are throwaway measuring tools, so they ask for the package and, failing that, ask the
// sibling clone by path rather than dying half way through a run.
//
// Nothing in the game imports this. If the pathfinder ships, it imports `@electric-sql/pglite` the
// normal way like every other file in src/.
const CANDIDATES = [
  '@electric-sql/pglite',
  'file:///C:/Users/gkwng/dev/byeharu-voyage/node_modules/@electric-sql/pglite/dist/index.js',
]

export async function loadPGlite() {
  const errs = []
  for (const spec of CANDIDATES) {
    try {
      const m = await import(spec)
      if (m.PGlite) return m.PGlite
    } catch (e) { errs.push(`${spec}: ${e.message}`) }
  }
  throw new Error('could not load PGlite:\n  ' + errs.join('\n  '))
}

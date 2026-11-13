import { useT } from '../lib/i18n'
import { HullBadge } from './HullBadge'
import { JOB_WORD, hullJobOf } from './hullJobWord'

// A HULL'S JOB (0366, owner row 322): "Raider", "Gunship", "Boarder", "Line ship", "Escort", "Armed trader" or "Cargo" beside a hull's name,
// small. ONE renderer for the Codex and the build yard, as HullTech is for the tech badge, so the two can never name a hull differently.
// The job is the finer word under the served role (Trade, Combat, Support): what she is built to do, which her figures already say.
// It is the generator's (scripts/build-ships.mjs JOBS, written to ./hullJobs.generated.ts and held equal by its `--check` and
// tests/ships.more.spec.ts); no rule reads it, so the server serves none. A hull with no job (every hull before 0366, and a plain trader)
// carries no badge.

export function HullJob({ code }: { code: string | null | undefined }) {
  const t = useT()
  const job = hullJobOf(code)
  if (!job) return null
  return (
    <HullBadge data-testid="hull-job" data-job={job}>
      {t(JOB_WORD[job])}
    </HullBadge>
  )
}

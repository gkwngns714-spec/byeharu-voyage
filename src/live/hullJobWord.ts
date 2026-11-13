import { t as tNow, type TKey } from '../lib/i18n'
import { HULL_JOBS, type HullJobCode } from './hullJobs.generated'

// The word for a hull's job (0366): one map, for the badge (HullJob), the Codex's filter and its search.
export const JOB_WORD: Readonly<Record<HullJobCode, TKey>> = {
  raider: 'codex.job_raider',
  gunship: 'codex.job_gunship',
  boarder: 'codex.job_boarder',
  line: 'codex.job_line',
  escort: 'codex.job_escort',
  armed: 'codex.job_armed',
  carrier: 'codex.job_carrier',
}

/** The job of a class code, or null. */
export const hullJobOf = (code: string | null | undefined): HullJobCode | null => (code ? (HULL_JOBS[code] ?? null) : null)
/** The word for a job, in the locale in force. */
export const hullJobWord = (job: HullJobCode): string => tNow(JOB_WORD[job])

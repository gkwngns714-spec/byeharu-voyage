import { Chip, Icon, NeedChip, Note } from '../../../components/ui'
import { formatInt } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetJobKind, FleetJobParams, FleetJobRow } from '../../../lib/rpc'
import { clearFleetJob, setFleetJob, useJobEdits } from '../../../live/useAwayReport'
import { JOB_ICON, JOB_STATE_TONE, JOB_STATE_WORD, JOB_KIND_WORD } from './jobMarks'

// 0481 (docs/design/hq-command-2026-11-23.md v2): A FLEET'S STANDING JOB, ON HER ROW. The mark says what she does by herself and how it
// goes (the kind's glyph in the tone of its state, the runs since she last read the away report); the setter is the kinds as chips: the
// one on is her job (press it again: no job). A fixed route is set from a trade card's Repeat (RepeatChip), so it only shows here once set.
// A refusal stands under the row in the server's own words.

/** The kinds a fleet row sets by itself (a fixed route needs a trade card's good and harbours). */
const ROW_KINDS: readonly FleetJobKind[] = ['best', 'land']

export function JobMark({ job }: { job: FleetJobRow }) {
  const t = useT()
  return (
    <span data-testid="hq-job" data-kind={job.kind} data-state={job.state} className="inline-flex">
      <NeedChip icon={JOB_ICON[job.kind]} tone={JOB_STATE_TONE[job.state]} label={`${t(JOB_KIND_WORD[job.kind])} · ${t(JOB_STATE_WORD[job.state])}`}>
        {job.runs > 0 ? `×${formatInt(job.runs)}` : t(JOB_STATE_WORD[job.state])}
      </NeedChip>
    </span>
  )
}

export function JobControl({ fleet, job }: { fleet: string; job: FleetJobRow | null }) {
  const t = useT()
  const pending = useJobEdits((s) => s.pending === fleet)
  const refusal = useJobEdits((s) => s.refused[fleet] ?? null)
  const kinds = job?.kind === 'fixed' ? [...ROW_KINDS, 'fixed' as const] : ROW_KINDS
  const press = (k: FleetJobKind) => {
    if (pending) return
    if (job?.kind === k) void clearFleetJob(fleet)
    else if (k !== 'fixed') void setFleetJob(fleet, k)
  }
  return (
    <div className="flex flex-col gap-1" data-testid="hq-job-control" data-fleet={fleet}>
      <div className="flex flex-wrap items-center gap-2" role="group" aria-label={t('hq.job')}>
        {job && <JobMark job={job} />}
        {kinds.map((k) => (
          <Chip key={k} on={job?.kind === k} onClick={() => press(k)} data-testid={`hq-job-set-${k}`}>
            <Icon name={JOB_ICON[k]} size={16} aria-hidden />
            {t(JOB_KIND_WORD[k])}
          </Chip>
        ))}
      </div>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="hq-job-refusal">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}

/** A trade card's REPEAT: her fleet runs this trip as a fixed route (buy here, sell there, back again) until she says otherwise. `send`:
 *  a served card's own act, sent first (the trip goes now, and its voyage under way is the course the route keeps: 0481's
 *  fleet_job_course); null where the card cannot send it here (v1's card: the route alone is set). On when that is her job already.
 *  A refusal (the server's: no course sailed yet, a fleet on a route) stands under the card. */
export function RepeatChip({
  id,
  fleet,
  params,
  on,
  send,
}: {
  id: string
  fleet: string
  params: Required<Pick<FleetJobParams, 'good' | 'buy' | 'sell'>> & FleetJobParams
  on: boolean
  send: (() => Promise<boolean>) | null
}) {
  const t = useT()
  const key = `repeat:${id}`
  const busy = useJobEdits((s) => s.pending !== null)
  const refusal = useJobEdits((s) => s.refused[key] ?? null)
  const press = async () => {
    if (busy) return
    if (on) {
      await clearFleetJob(fleet, key)
      return
    }
    if (send && !(await send())) return
    await setFleetJob(fleet, 'fixed', params, key)
  }
  return (
    <span className="flex flex-col items-end gap-1">
      <Chip on={on} onClick={() => void press()} data-testid="hq-move-repeat">
        <Icon name={JOB_ICON.fixed} size={16} aria-hidden />
        {t('hq.repeat')}
      </Chip>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="hq-move-repeat-refusal">
          {refusal.sentence}
        </Note>
      )}
    </span>
  )
}

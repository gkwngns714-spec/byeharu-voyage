import { Button, Figure, Icon, KEEP_WORDS_CLASS, NeedChip, SheetSection } from '../../../components/ui'
import { formatDucatsDelta, formatInt } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import type { FleetJobsReport, SeaChoice } from '../../../lib/rpc'
import { SEA_KIND_ICON, SEA_KIND_WORD, seaOptionWord } from '../../../live/seaChoiceOf'
import { seenAwayReport, useJobEdits } from '../../../live/useAwayReport'
import { JOB_ICON, JOB_STATE_TONE, JOB_STATE_WORD, JOB_KIND_WORD } from './jobMarks'

// 0481 (docs/design/hq-command-2026-11-23.md v2, "She comes back to a report and re-plans"): WHILE YOU WERE AWAY. One line a job: her
// ship's job glyph in the tone of its state, her whole name, the runs it started and the coin her fleet made since she last pressed OK,
// and the code it stopped on. OK marks it read (cmd.fleet_jobs_seen): the tallies start again. Shown only when something happened.
// 0486: and each choice at sea settled since then (her pick or the default, and the coin it moved), one line each.

export function JobsAway({ report, sea = [] }: { report: Extract<FleetJobsReport, { company: true }>; sea?: SeaChoice[] }) {
  const t = useT()
  const pending = useJobEdits((s) => s.pending === 'seen')
  const news = report.jobs.filter((j) => j.runs > 0 || j.earned !== 0 || j.state === 'stopped')
  const since = report.since === null ? null : Date.parse(report.since)
  const ends = sea.filter((c) => c.outcome !== null && c.settled_at !== null && (since === null || Date.parse(c.settled_at) > since))
  if (news.length === 0 && ends.length === 0) return null
  return (
    <SheetSection
      heading={t('hq.away')}
      trailing={<Figure value={formatDucatsDelta(report.earned)} tone={report.earned < 0 ? 'danger' : 'success'} />}
    >
      <ul className="flex flex-col gap-2" data-testid="hq-away">
        {news.map((j) => (
          <li key={j.fleet} className="flex items-center gap-3" data-testid="hq-away-job" data-kind={j.kind} data-state={j.state}>
            <Icon name={JOB_ICON[j.kind]} size={20} aria-label={t(JOB_KIND_WORD[j.kind])} role="img" />
            <span className={`${KEEP_WORDS_CLASS} min-w-0 flex-1 text-t-body text-ink`}>{j.fleet_name}</span>
            {j.runs > 0 && (
              <NeedChip icon="history" label={t('hq.runs', { n: formatInt(j.runs) })}>
                ×{formatInt(j.runs)}
              </NeedChip>
            )}
            {j.state === 'stopped' ? (
              <NeedChip icon="close" tone={JOB_STATE_TONE.stopped} label={t(JOB_STATE_WORD.stopped)}>
                {j.paused ?? t(JOB_STATE_WORD.stopped)}
              </NeedChip>
            ) : (
              <Figure value={formatDucatsDelta(j.earned)} tone={j.earned < 0 ? 'danger' : 'success'} />
            )}
          </li>
        ))}
        {ends.map((c) => {
          const o = c.outcome!
          const word = seaOptionWord(o.option)
          return (
            <li key={c.id} className="flex items-center gap-3" data-testid="hq-away-sea" data-kind={c.kind} data-by={o.by}>
              <Icon name={SEA_KIND_ICON[c.kind]} size={20} aria-label={t(SEA_KIND_WORD[c.kind])} role="img" />
              <span className={`${KEEP_WORDS_CLASS} min-w-0 flex-1 text-t-body text-ink`}>{c.fleet_name}</span>
              <NeedChip icon={o.by === 'default' ? 'shield' : 'helm'} tone={o.good ? 'success' : 'danger'} label={o.by === 'default' ? t('hq.seaDefault') : t('hq.seaPicked')}>
                {word ? t(word) : o.option}
              </NeedChip>
              <Figure value={formatDucatsDelta(o.amount)} tone={o.amount < 0 ? 'danger' : o.amount > 0 ? 'success' : 'muted'} />
            </li>
          )
        })}
      </ul>
      <div className="mt-3 flex justify-end">
        <Button variant="secondary" onClick={() => void seenAwayReport()} disabled={pending} data-testid="hq-away-seen">
          {t('hq.seen')}
        </Button>
      </div>
    </SheetSection>
  )
}

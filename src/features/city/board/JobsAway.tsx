import { Button, Figure, Icon, KEEP_WORDS_CLASS, NeedChip, SheetSection } from '../../../components/ui'
import { formatDucatsDelta, formatInt } from '../../../lib/format'
import { translateMaybe, useLocale, useT, type Locale } from '../../../lib/i18n'
import type { FleetJobsReport, SeaChoice } from '../../../lib/rpc'
import { SEA_KIND_ICON, SEA_KIND_WORD, seaOptionWord } from '../../../live/seaChoiceOf'
import { seenAwayReport, useJobEdits } from '../../../live/useAwayReport'
import { useWorld } from '../../../live/worldStore'
import { fixOf } from '../../../domain/fleet'
import { WorkerFixButton } from '../../../live/FixButton'
import { RoundsAway } from '../corp/RoundCard'
import { jobCode } from '../corp/workerRows'
import { JOB_ICON, JOB_STATE_TONE, JOB_STATE_WORD, JOB_KIND_WORD } from './jobMarks'

// 0481 (docs/design/hq-command-2026-11-23.md v2, "She comes back to a report and re-plans"): WHILE YOU WERE AWAY. One line a job: her
// ship's job glyph in the tone of its state, her whole name, the runs it started and the coin her fleet made since she last pressed OK,
// and the code it stopped on. OK marks it read (cmd.fleet_jobs_seen): the tallies start again. Shown only when something happened.
// SAID ONCE (the join, 2026-11-24): these tallies stand here and nowhere else on HQ (her worker row says her action, not her tally).
// With one fleet her row has already named her, so a line here is headed by its job's word; and a sum of one line is that line again,
// so the total heads the block only when it adds up more than one.
// 0486: and each choice at sea settled since then (her pick or the default, and the coin it moved), one line each.
//
// A STOPPED JOB SAYS WHY IN PLAIN WORDS, NEVER ITS CODE (owner row 381: the chip read "E_LEG_TOO_FAR"). The chip is the code's short
// label (dict/codes.ts `lab_<code>`: "Range") and the code's sentence stands under her name ("Leg too far."). A code with no label
// reads "Stopped"; one with no sentence adds no line. The code itself is only the row's `data-code`.
// 0499: A STOPPED JOB WHOSE CODE ONE PRESS MENDS HAS THAT PRESS under its sentence (live/FixButton.tsx; the table is domain/fleet
// `fixOf`): Repair at the server's price, Assign, Storage. Else none.

/** A code's entry in dict/codes.ts, in her language, else its English one; null when the code has none. */
function codeWord(locale: Locale, name: string): string | null {
  return translateMaybe(locale, 'codes', name) ?? translateMaybe('en', 'codes', name)
}

export function JobsAway({ report, sea = [] }: { report: Extract<FleetJobsReport, { company: true }>; sea?: SeaChoice[] }) {
  const t = useT()
  const locale = useLocale()
  const pending = useJobEdits((s) => s.pending === 'seen')
  const manyFleets = useWorld((s) => s.fleets.length > 1)
  const news = report.jobs.filter((j) => j.runs > 0 || j.earned !== 0 || j.state === 'stopped')
  const since = report.since === null ? null : Date.parse(report.since)
  const ends = sea.filter((c) => c.outcome !== null && c.settled_at !== null && (since === null || Date.parse(c.settled_at) > since))
  if (news.length === 0 && ends.length === 0) return null
  return (
    <SheetSection
      heading={t('hq.away')}
      trailing={news.length + ends.length > 1 ? <Figure value={formatDucatsDelta(report.earned)} tone={report.earned < 0 ? 'danger' : 'success'} /> : undefined}
    >
      <ul className="flex flex-col gap-2" data-testid="hq-away">
        {news.map((j) => {
          const why = j.state === 'stopped' && j.paused ? codeWord(locale, j.paused) : null
          return (
            <li key={j.fleet} className="flex flex-col gap-0.5" data-testid="hq-away-job" data-kind={j.kind} data-state={j.state} data-code={j.paused ?? undefined}>
              <div className="flex items-center gap-3">
                <Icon name={JOB_ICON[j.kind]} size={20} aria-label={t(JOB_KIND_WORD[j.kind])} role="img" />
                <span className={`${KEEP_WORDS_CLASS} min-w-0 flex-1 text-t-body text-ink`}>{manyFleets ? j.fleet_name : t(JOB_KIND_WORD[j.kind])}</span>
                {j.runs > 0 && (
                  <NeedChip icon="history" label={t('hq.runs', { n: formatInt(j.runs) })}>
                    ×{formatInt(j.runs)}
                  </NeedChip>
                )}
                {j.state === 'stopped' ? (
                  <span className="inline-flex" data-testid="hq-away-stopped">
                    <NeedChip icon="close" tone={JOB_STATE_TONE.stopped} label={t(JOB_STATE_WORD.stopped)}>
                      {(j.paused ? codeWord(locale, `lab_${j.paused}`) : null) ?? t(JOB_STATE_WORD.stopped)}
                    </NeedChip>
                  </span>
                ) : (
                  <Figure value={formatDucatsDelta(j.earned)} tone={j.earned < 0 ? 'danger' : 'success'} />
                )}
              </div>
              {why && (
                <span className="break-words pl-8 text-t-caption text-ink-muted" data-testid="hq-away-why">
                  {why}
                </span>
              )}
              {j.kind === 'round' && <RoundsAway fleet={j.fleet} />}
              {j.state === 'stopped' && fixOf(jobCode(j)) && (
                <span className="flex flex-col items-start gap-2 pl-8 pt-1" data-testid="hq-away-fix">
                  <WorkerFixButton fix={fixOf(jobCode(j))} worker={j.fleet} />
                </span>
              )}
            </li>
          )
        })}
        {ends.map((c) => {
          const o = c.outcome!
          const word = seaOptionWord(o.option)
          return (
            <li key={c.id} className="flex items-center gap-3" data-testid="hq-away-sea" data-kind={c.kind} data-by={o.by}>
              <Icon name={SEA_KIND_ICON[c.kind]} size={20} aria-label={t(SEA_KIND_WORD[c.kind])} role="img" />
              <span className={`${KEEP_WORDS_CLASS} min-w-0 flex-1 text-t-body text-ink`}>{manyFleets ? c.fleet_name : t(SEA_KIND_WORD[c.kind])}</span>
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

import { useState } from 'react'
import { Button, Note, Row, Skeleton, refusalWords } from '../components/ui'
import { formatInt } from '../lib/format'
import { cmdCaptainSkillUp } from '../lib/rpc'
import type { CaptainSkill, Refusal } from '../lib/rpc'
import { useLocale, useT } from '../lib/i18n'
import { skillWord } from './skillWords'
import { useCaptainSkills } from './useCaptainSkills'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CAPTAIN SKILLS — a step of one skill, bought with Reputation (0355, docs/REPUTATION.md section 3; owner row 317)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `world.captain_skills` serves every skill she knows with its step, her grade's ceiling, what the steps add and what the next one costs:
//
//   Navigator · 2 / 5 · +8 %          [ Upgrade · 300 ]
//   항해사 · 2 / 5 · +8 %             [ 강화 · 300 ]
//
// The step has no noun: `2 / 5` only (docs/WORDS.md: rank, level, grade and tier are all taken). Nothing is computed here. Whether the button may be pressed
// is the server's `can`, read from the one rule its door refuses by; when it may not, the button is greyed and the server's own sentence stands under it
// (in Korean, the code's entry in the refusal dictionary, with the figures it served). A press that the server still refuses prints that refusal as a Note.
// The absolute figures (+9.72% speed) stay on the stat lines above: this block prints the steps and their own bonus, never a second value of a skill.
//
// While the first ask is on the wire a block stands in its place (the Skeleton), so the rows under it do not jump when the answer lands.

export function CaptainSkills({ code }: { code: string }) {
  const t = useT()
  const { view, loading } = useCaptainSkills(code)
  const refresh = useWorld((s) => s.refresh)
  const [busy, setBusy] = useState<string | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  if (!view && !loading) return null

  const press = (trait: string) => {
    if (busy !== null) return
    setBusy(trait)
    setRefusal(null)
    void (async () => {
      const r = await cmdCaptainSkillUp(code, trait)
      if (r.ok) await refresh()
      else setRefusal(r.refusal)
      setBusy(null)
    })()
  }

  return (
    <div data-testid="captain-skills" data-reputation={view?.reputation}>
      <h4 className="pb-1 pt-4 text-t-caption text-ink-faint">{t('books.captainSkills')}</h4>
      {view ? (
        view.skills.map((s, i) => (
          <SkillRow key={s.trait} skill={s} busy={busy === s.trait} locked={busy !== null} last={i === view.skills.length - 1} onPress={() => press(s.trait)} />
        ))
      ) : (
        <Skeleton className="mt-1 h-52 w-full" />
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2" data-testid="captain-skill-refused">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}

function SkillRow({ skill, busy, locked, last, onPress }: { skill: CaptainSkill; busy: boolean; locked: boolean; last: boolean; onPress: () => void }) {
  const t = useT()
  const locale = useLocale()
  const why = skill.can || skill.why === null ? null : ((skill.why_code && refusalWords(locale, skill.why_code, skill.figures)) || skill.why)
  return (
    <Row
      label={`${skillWord(skill.trait, skill.word)} · ${formatInt(skill.rank)} / ${formatInt(skill.max)} · +${formatInt(skill.pct_now)} %`}
      value={
        <Button
          disabled={!skill.can || locked}
          busy={busy}
          busyLabel={t('books.upgrading')}
          onClick={onPress}
          data-testid={`captain-skill-up-${skill.trait}`}
        >
          {skill.cost === null ? t('books.upgradeTop') : t('books.upgrade', { cost: formatInt(skill.cost) })}
        </Button>
      }
      end
      tone={skill.in_use ? 'default' : 'muted'}
      hairline={!last}
      data-testid={`captain-skill-${skill.trait}`}
      data-rank={skill.rank}
      data-max={skill.max}
      data-can={skill.can}
    >
      {why !== null && (
        // the button is a control on the line: it hangs 10 px under it (Row.tsx), so the reason starts 12 px lower and clears it
        <span className="mt-3 block text-right text-t-caption text-ink-faint" data-testid={`captain-skill-why-${skill.trait}`}>
          {why}
        </span>
      )}
    </Row>
  )
}

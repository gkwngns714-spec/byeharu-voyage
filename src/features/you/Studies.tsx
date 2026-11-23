import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Card, Countdown, Icon, Note, Ring, Skeleton, Tile, TileField } from '../../components/ui'
import { useShellState } from '../../app/shellState'
import { formatInt } from '../../lib/format'
import { properName, useLocale, useT } from '../../lib/i18n'
import { FROM, useLevelGate } from '../../live/levelGate'
import { openAcademy } from '../../live/levelWays'
import { levelName } from '../../live/levelWords'
import { useWorld } from '../../live/worldStore'

// THE ACADEMY'S SKILLS AS CAPTAIN STUDIES (roadmap 2026-11-23, X6 and slice 10). The Academy's book (`world.skills()`, 0131: every
// skill, its group, its level, the training queue) stands on the Levels page from Trading 5, by the ONE level gate
// (live/levelGate.ts): held, the card is a dimmed plate whose figure is the level that opens it, as HQ's held doors are. Open, it is
// what is training now and each group as a ringed tile (its skills studied of its skills), and a press opens the Academy, where a
// skill is enrolled and trained. Nothing here is worked out but a count of served rows.

export function Studies() {
  const t = useT()
  const locale = useLocale()
  const gate = useLevelGate()
  const navigate = useNavigate()
  const book = useWorld((s) => s.skills)
  const loadSkills = useWorld((s) => s.loadSkills)
  const { nowMs } = useShellState()
  const held = gate.shut('academy')

  useEffect(() => {
    if (!held && !book) void loadSkills()
  }, [held, book, loadSkills])

  const go = () => navigate(openAcademy())

  if (held)
    return (
      <Card icon="books" title={t('town.f_academy')} data-testid="studies" data-held="">
        <span className="flex min-h-11 items-center gap-2 text-t-body text-ink-faint" data-testid="studies-held">
          <Icon name="levelUp" size={16} />
          <span className="tabular-nums">
            {levelName(locale, FROM.track)} {formatInt(FROM.level)}
          </span>
        </span>
      </Card>
    )

  const studied = book ? book.skills.filter((s) => s.level > 0).length : 0
  const head = book?.queue[0] ?? null
  return (
    <Card
      icon="books"
      title={t('town.f_academy')}
      aside={book ? <span className="tabular-nums text-ink-muted" data-testid="studies-count">{`${formatInt(studied)} / ${formatInt(book.skills.length)}`}</span> : undefined}
      data-testid="studies"
    >
      {!book ? (
        <Skeleton className="h-24 w-full" />
      ) : book.skills.length === 0 ? (
        <Note tone="neutral">{t('command.lvGivesNothing')}</Note>
      ) : (
        <>
          {/* TRAINING NOW: the queue's head, its level and its clock (the Academy's own row) */}
          {head && (
            <button
              type="button"
              onClick={go}
              className="mb-2 flex min-h-11 w-full items-center gap-2 rounded-control text-left text-t-body hover:text-accent"
              data-testid="studies-training"
            >
              <Icon name="history" size={16} className="shrink-0 text-accent" />
              <span className="min-w-0 flex-1 break-words">{t('port.queued', { name: properName('skill', head.code, head.name), level: head.level })}</span>
              <Countdown untilMs={Date.parse(head.finishes_at)} nowMs={nowMs} dueText={t('port.done')} className="shrink-0 tabular-nums text-ink-muted" />
            </button>
          )}
          <TileField data-testid="studies-groups">
            {book.groups.map((g) => {
              const all = book.skills.filter((s) => s.group === g.code)
              if (all.length === 0) return null
              const done = all.filter((s) => s.level > 0).length
              return (
                <Tile
                  key={g.code}
                  tap="whole"
                  onClick={go}
                  state={done > 0 ? 'selected' : 'rest'}
                  className="min-h-0! gap-1! p-2!"
                  mark={
                    <Ring pct={(done / all.length) * 100} size={32} label={`${g.name} ${done} / ${all.length}`}>
                      <span className={done > 0 ? 'text-accent' : 'text-ink-faint'}>
                        <Icon name="books" size={16} />
                      </span>
                    </Ring>
                  }
                  name={g.name}
                  meta={<span className="tabular-nums">{`${formatInt(done)} / ${formatInt(all.length)}`}</span>}
                  data-testid={`studies-group-${g.code}`}
                />
              )
            })}
          </TileField>
        </>
      )}
    </Card>
  )
}

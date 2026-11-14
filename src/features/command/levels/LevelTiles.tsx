import { useState } from 'react'
import { Bar, Icon, Note, Tray, type TrayDetent } from '../../../components/ui'
import { formatInt, formatRelative } from '../../../lib/format'
import { translateMaybe, useLocale, useT } from '../../../lib/i18n'
import type { LevelSkill, LevelSkillsCard } from '../../../lib/rpc'
import { useShellState } from '../../../app/shellState'
import { activityLine, everyLevelLine, levelFill, levelGives, levelMark, levelName } from '../../../live/levelWords'

// THE LEVELS, AS TILES (0411, docs/LEVELS.md; the owner, 2026-11-14: "like rs3, i want diverse skills related to this game" and
// "with exp table, exp info, with benefits when leveling up, what activity needs done etc.").
//
// ONE READ, NO SUM: everything here is `world.levels().level_skills` (`public.level_skills_card`). A tile is a level's mark, name,
// level and its bar to the next. Pressed, a level shows four things, all served: her experience (now, into this level, today
// against the day's limit, the newest grants), what raises it and by how much, what every level gives, and the whole experience
// table with her own level marked and the next one lit. No figure, threshold or reward is worked out or typed in the client.
//
// THE PRESS LAW: a press selects. On a phone the level opens in a tray docked over the page; on a wide glass it stands in the
// middle pane. No tile moves.

/** A level's mark, in the kit's own stroke. */
function Mark({ code, size = 20 }: { code: string; size?: number }) {
  const m = levelMark(code)
  if ('icon' in m) return <Icon name={m.icon} size={size} />
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {m.paths.map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  )
}

/** The Reputation of the next level, from the served gift a level (the `gift` benefit): gift x (level + 1). 0: none, or the top level. */
const nextGift = (s: LevelSkill): number => {
  if (s.next_at === null) return 0
  const g = s.benefits.find((b) => b.level === null && b.kind === 'gift')
  return g && g.kind === 'gift' ? g.n * (s.level + 1) : 0
}

/** Every level as a tile: two to a line on a phone and in the desk's left pane. */
export function LevelTiles({ card, selected, onSelect }: { card: LevelSkillsCard; selected: string | null; onSelect: (code: string) => void }) {
  const t = useT()
  const locale = useLocale()
  return (
    <div className="grid grid-cols-2 gap-2" data-testid="level-tiles">
      {card.skills.map((s) => {
        const name = levelName(locale, s.code, s.word)
        const gift = nextGift(s)
        const on = selected === s.code
        return (
          <button
            key={s.code}
            type="button"
            onClick={() => onSelect(s.code)}
            aria-pressed={on}
            data-testid={`levels-${s.code}`}
            data-level={s.level}
            className={`flex min-h-tile min-w-0 flex-col gap-1 rounded-tile border p-2 text-left transition ${
              on ? 'border-accent bg-accent-soft' : 'border-transparent bg-surface-2'
            } ${s.counted ? '' : 'text-ink-faint'}`}
          >
            <span className="flex items-center justify-between gap-2">
              <span className={s.counted ? 'text-accent' : 'text-ink-faint'}>
                <Mark code={s.code} size={22} />
              </span>
              <span className="text-t-title tabular-nums" data-testid="level-tile-level">
                {formatInt(s.level)}
              </span>
            </span>
            <span className="block break-words text-t-body">{name}</span>
            <Bar pct={levelFill(s)} label={t('you.levelOf', { name })} tone={s.counted ? 'accent' : 'neutral'} />
            <span className="flex flex-wrap gap-x-2 text-t-caption text-ink-faint">
              {!s.counted ? (
                t('command.lvCombatDark')
              ) : s.next_at === null ? (
                t('command.lvTop')
              ) : (
                <>
                  <span className="whitespace-nowrap">{t('command.lvExpOf', { a: formatInt(s.points), b: formatInt(s.next_at) })}</span>
                  {gift > 0 && (
                    <span className="whitespace-nowrap text-accent" data-testid="levels-gift" data-value={gift}>
                      {t('command.lvNextGift', { n: formatInt(gift) })}
                    </span>
                  )}
                </>
              )}
            </span>
          </button>
        )
      })}
    </div>
  )
}

function Heading({ children }: { children: string }) {
  return <h4 className="mb-1 mt-4 text-t-caption font-semibold text-ink-faint">{children}</h4>
}

/** One level, whole: her experience, what raises it, what levels give, and the experience table. */
export function LevelDetail({ card, skill, titled = true }: { card: LevelSkillsCard; skill: LevelSkill; titled?: boolean }) {
  const t = useT()
  const locale = useLocale()
  const { nowMs } = useShellState()
  const name = levelName(locale, skill.code, skill.word)
  const every = skill.benefits.map((b) => everyLevelLine(locale, b, name)).filter((x): x is string => x !== null)
  const levels = Array.from({ length: card.top }, (_, i) => i + 1)
  return (
    <section className="min-w-0" data-testid="level-detail" data-level-code={skill.code}>
      {titled && (
        <h3 className="flex items-center gap-2 text-t-title">
          <span className="text-accent">
            <Mark code={skill.code} size={22} />
          </span>
          {name}
        </h3>
      )}

      {/* 1. HER EXPERIENCE */}
      <div className="mt-2 flex items-baseline justify-between gap-3">
        <span className="text-t-card" data-testid="level-detail-level">
          {t('command.lvLevel', { n: skill.level })}
        </span>
        <span className="text-t-body tabular-nums text-ink-muted" data-testid="level-detail-exp">
          {t('command.lvExp', { n: formatInt(skill.points) })}
        </span>
      </div>
      <Bar pct={levelFill(skill)} label={t('you.levelOf', { name })} tone="accent" className="mt-1" />
      <span className="mt-1 block text-t-caption text-ink-faint" data-testid="level-detail-progress">
        {skill.next_at === null
          ? t('command.lvTop')
          : [
              t('command.lvInLevel', { a: formatInt(skill.points - skill.from), b: formatInt(skill.next_at - skill.from) }),
              t('command.lvToGo', { n: formatInt(Math.ceil(skill.next_at - skill.points)), next: skill.level + 1 }),
            ].join(' · ')}
      </span>
      {!skill.counted && (
        <Note tone="neutral" className="mt-2">
          {t('command.lvCombatDark')}
        </Note>
      )}
      {skill.kept === 'record' ? (
        <span className="mt-1 block text-t-caption text-ink-faint">{t('command.lvFromRecord')}</span>
      ) : (
        <>
          <span className="mt-1 block text-t-caption text-ink-muted" data-testid="level-detail-today">
            {t('command.lvTodayCap', { a: formatInt(skill.today ?? 0), b: formatInt(skill.cap ?? 0) })}
          </span>
          <Heading>{t('command.lvRecent')}</Heading>
          {skill.recent === null || skill.recent.length === 0 ? (
            <span className="block text-t-caption text-ink-faint">{t('command.lvNoRecent')}</span>
          ) : (
            <ul data-testid="level-detail-recent">
              {skill.recent.map((r) => (
                <li key={r.at + r.activity} className="flex items-baseline justify-between gap-3 py-0.5 text-t-caption">
                  <span className="min-w-0 break-words text-ink-muted">
                    <span className="tabular-nums text-accent">{t('command.lvGain', { n: formatInt(r.xp) })}</span>{' '}
                    {translateMaybe(locale, 'command', `lvAct_${r.activity}`) ?? skill.activities.find((a) => a.code === r.activity)?.word ?? r.activity}
                  </span>
                  <span className="shrink-0 whitespace-nowrap text-ink-faint">{formatRelative(Date.parse(r.at), nowMs)}</span>
                </li>
              ))}
            </ul>
          )}
        </>
      )}

      {/* 2. WHAT RAISES IT */}
      <Heading>{t('command.lvHow')}</Heading>
      <ul data-testid="level-detail-activities">
        {skill.activities.map((a) => (
          <li key={a.code} className="break-words py-0.5 text-t-body text-ink">
            {activityLine(locale, a)}
          </li>
        ))}
      </ul>
      <span className="mt-1 block text-t-caption text-ink-faint" data-testid="level-detail-cap">
        {skill.cap === null ? t('command.lvNoCap') : t('command.lvDayCap', { n: formatInt(skill.cap) })}
      </span>

      {/* 3. WHAT LEVELS GIVE */}
      <Heading>{t('command.lvGives')}</Heading>
      {every.length === 0 ? (
        <span className="block text-t-caption text-ink-faint">{t('command.lvGivesNothing')}</span>
      ) : (
        <ul data-testid="level-detail-benefits">
          {every.map((line) => (
            <li key={line} className="break-words py-0.5 text-t-body text-ink">
              {line}
            </li>
          ))}
        </ul>
      )}

      {/* 4. THE EXPERIENCE TABLE, with what each level gives: reached, her own, the next one lit, the later ones to aim for */}
      <Heading>{t('command.lvTable')}</Heading>
      <table className="w-full table-fixed border-collapse text-left" data-testid="level-detail-table">
        <thead>
          <tr className="text-t-caption text-ink-faint">
            <th className="w-[3.25rem] py-1 font-normal">{t('command.lvColLevel')}</th>
            <th className="w-[4.5rem] py-1 text-right font-normal">{t('command.lvColExp')}</th>
            <th className="py-1 pl-3 font-normal">{t('command.lvColGives')}</th>
          </tr>
        </thead>
        <tbody>
          {levels.map((l) => {
            const mine = l === skill.level
            const next = l === skill.level + 1
            const gives = levelGives(locale, l, skill.benefits)
            return (
              <tr
                key={l}
                data-testid="level-row"
                data-level={l}
                data-state={mine ? 'mine' : next ? 'next' : l < skill.level ? 'reached' : 'later'}
                className={`border-t border-edge align-top text-t-caption ${mine ? 'bg-accent-soft' : ''} ${l < skill.level ? 'text-ink-faint' : 'text-ink'}`}
              >
                <td className="py-1 pl-1 tabular-nums">
                  <span className={next ? 'font-semibold text-accent' : ''}>{formatInt(l)}</span>
                  {mine && <span className="block text-ink-muted">{t('command.lvYou')}</span>}
                  {next && <span className="block text-accent">{t('command.lvNext')}</span>}
                </td>
                <td className="py-1 text-right tabular-nums">
                  {formatInt(card.curve[l - 1] ?? 0)}
                  {next && skill.next_at !== null && (
                    <span className="block whitespace-nowrap text-accent" data-testid="level-row-togo">
                      {t('command.lvLeft', { n: formatInt(Math.ceil(skill.next_at - skill.points)) })}
                    </span>
                  )}
                </td>
                <td className="break-words py-1 pl-3">
                  {gives.length === 0
                    ? '—'
                    : gives.map((g) => (
                        <span key={g} className="block">
                          {g}
                        </span>
                      ))}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </section>
  )
}

/** A phone's tray for the pressed level: docked over the page, so no tile moves. */
export function LevelTray({ card, code, onClose }: { card: LevelSkillsCard; code: string | null; onClose: () => void }) {
  const locale = useLocale()
  const skill = card.skills.find((s) => s.code === code) ?? null
  // how tall she left it: a level opens whole, and a drag down to half is kept for the next level pressed
  const [held, setHeld] = useState<TrayDetent>('full')
  return (
    <Tray
      detent={skill ? held : 'closed'}
      onDetentChange={(d) => {
        if (d === 'closed') onClose()
        else setHeld(d)
      }}
      title={skill ? levelName(locale, skill.code, skill.word) : ''}
      data-testid="level-tray"
    >
      {skill && (
        <div className="pb-6">
          <LevelDetail card={card} skill={skill} titled={false} />
        </div>
      )}
    </Tray>
  )
}

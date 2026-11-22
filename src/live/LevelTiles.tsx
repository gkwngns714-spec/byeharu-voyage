import { useEffect, useState } from 'react'
import { Bar, GroupHeading, Icon, Ring, Tile, Tray, type TrayDetent } from '../components/ui'
import { formatInt, formatRelative } from '../lib/format'
import { translateMaybe, useLocale, useT } from '../lib/i18n'
import type { LevelSkill, LevelSkillsCard } from '../lib/rpc'
import { useShellState } from '../app/shellState'
import { activityLine, everyLevelLine, giftAt, levelFill, levelGives, levelMark, levelName, perksNow } from './levelWords'

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

/** A level's mark, in the kit's own stroke. Also a captain's level rings' (captainLook.tsx): one mark a track. */
export function Mark({ code, size = 20 }: { code: string; size?: number }) {
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

/** The Reputation of the next level, from the served gift (the `gift` benefit) and the skill's `gift_every` (giftAt). 0: none, the top. */
const nextGift = (s: LevelSkill): number => {
  if (s.next_at === null) return 0
  const g = s.benefits.find((b) => b.level === null && b.kind === 'gift')
  return g && g.kind === 'gift' ? giftAt(g.n, s.level + 1, s.gift_every ?? 1) : 0
}

/** Every level as a tile, two to a line (the You page's levels card, 2026-11-16). 0455: while the land is lit the card serves land
 *  skills too, and the tiles stand in two groups, Sea and Land, each tile saying its own top in its tray. Dark, one group as before. */
export function LevelTiles({
  card,
  selected,
  onSelect,
}: {
  card: LevelSkillsCard
  selected: string | null
  onSelect: (code: string) => void
}) {
  const t = useT()
  const sea = card.skills.filter((s) => s.side !== 'land')
  const land = card.skills.filter((s) => s.side === 'land')
  if (land.length === 0) return <TileGroup skills={sea} selected={selected} onSelect={onSelect} testid="level-tiles" />
  return (
    <>
      <GroupHeading>{t('command.lvSea')}</GroupHeading>
      <TileGroup skills={sea} selected={selected} onSelect={onSelect} testid="level-tiles" />
      <GroupHeading className="mt-3">{t('command.lvLand')}</GroupHeading>
      <TileGroup skills={land} selected={selected} onSelect={onSelect} testid="level-tiles-land" />
    </>
  )
}

function TileGroup({
  skills,
  selected,
  onSelect,
  testid,
}: {
  skills: readonly LevelSkill[]
  selected: string | null
  onSelect: (code: string) => void
  testid: string
}) {
  return (
    <div className="grid grid-cols-2 gap-2" data-testid={testid}>
      {skills.map((s) => (
        <LevelTile key={s.code} s={s} on={selected === s.code} onSelect={onSelect} />
      ))}
    </div>
  )
}

/** THE LEVEL EACH TILE LAST SHOWED, for the session (the visual overhaul's slice 9). A tile whose served level is higher than the
 *  one it last drew plays the level-up moment once: so a level that rose while she was on another tab greets her when she comes
 *  back to You. A page load starts it empty, so nothing plays on the first sight of a level. Nothing is worked out here: it
 *  compares two served levels. */
const shown = new Map<string, number>()

/** How many times this level has risen in front of her (0: never): the moment's key, so each rise plays it afresh. */
function useRises(code: string, level: number): number {
  // the first sight: a rise since this tile last stood on the page (another tab, the same session)
  const [seen, setSeen] = useState(() => {
    const before = shown.get(code)
    return { level, rises: before !== undefined && level > before ? 1 : 0 }
  })
  // a rise while she looks: the served level moved under the drawn one (React's adjust-state-while-rendering pattern)
  if (seen.level !== level) setSeen({ level, rises: level > seen.level ? seen.rises + 1 : seen.rises })
  useEffect(() => {
    shown.set(code, level)
  }, [code, level])
  return seen.rises
}

/** One level as a Melvor-style tile: its mark in a ring filling to the next level, the level figure, its name, the 6-px bar to the
 *  next, and the experience against the next level with the next level's gift. */
function LevelTile({ s, on, onSelect }: { s: LevelSkill; on: boolean; onSelect: (code: string) => void }) {
  const t = useT()
  const locale = useLocale()
  const name = levelName(locale, s.code, s.word)
  const gift = nextGift(s)
  const fill = levelFill(s)
  const rises = useRises(s.code, s.level)
  return (
    // THE KIT'S TILE (2026-11-15; tests/duplication.spec.ts "no inline border+bg skin"): its skin, its selected wash and hairline;
    // the body is the level's own (no head). A level tile is tighter than a catalogue tile and stands inset on its sheet.
    <Tile
      tap="whole"
      state={on ? 'selected' : 'rest'}
      onClick={() => onSelect(s.code)}
      aria-pressed={on}
      data-testid={`levels-${s.code}`}
      data-level={s.level}
      data-rose={rises > 0 ? rises : undefined}
      className={`relative min-w-0 gap-1! p-2! ${on ? '' : 'bg-surface-2!'} ${s.counted ? '' : 'text-ink-faint'}`}
    >
      {/* THE LEVEL-UP MOMENT: a gold glow round the tile and a chevron rising off the ring, once (1.4 s). Keyed by the rise, so a
          second rise plays it again; under reduced motion it is not drawn at all (index.css `.bv-level-*`). */}
      {rises > 0 && <span key={`glow-${rises}`} aria-hidden="true" className="bv-level-glow pointer-events-none absolute inset-0 rounded-tile" />}
      <span className="flex items-center justify-between gap-2">
        <span className="relative inline-flex">
          <Ring pct={fill} size={40} track="edge" tone={s.counted ? 'accent' : 'muted'} label={t('books.levelRing', { track: name, n: formatInt(s.level) })}>
            <span key={`mark-${rises}`} className={`inline-flex ${s.counted ? 'text-accent' : 'text-ink-faint'} ${rises > 0 ? 'bv-level-pop' : ''}`}>
              <Mark code={s.code} size={20} />
            </span>
          </Ring>
          {rises > 0 && (
            <span key={`up-${rises}`} aria-hidden="true" className="bv-level-up pointer-events-none absolute -top-1 left-1/2 -ml-2 text-accent">
              <Icon name="levelUp" size={16} />
            </span>
          )}
        </span>
        <span key={`level-${rises}`} className={`text-t-title tabular-nums ${rises > 0 ? 'bv-level-pop text-accent' : ''}`} data-testid="level-tile-level">
          {formatInt(s.level)}
        </span>
      </span>
      <span className="block break-words text-t-body">{name}</span>
      <Bar pct={fill} label={t('you.levelOf', { name })} tone={s.counted ? 'accent' : 'neutral'} />
      <span className="flex flex-wrap gap-x-2 text-t-caption text-ink-faint">
        {/* a level not counted yet (Combat) says nothing: "Not counted yet" was a builder's note (2026-11-22, P0) */}
        {!s.counted ? null : s.next_at === null ? (
          t('command.lvTop')
        ) : (
          <>
            <span className="whitespace-nowrap tabular-nums">{t('command.lvExpOf', { a: formatInt(s.points), b: formatInt(s.next_at) })}</span>
            {gift > 0 && (
              <span className="whitespace-nowrap text-accent" data-testid="levels-gift" data-value={gift}>
                {t('command.lvNextGift', { n: formatInt(gift) })}
              </span>
            )}
          </>
        )}
      </span>
    </Tile>
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
  const every = skill.benefits.map((b) => everyLevelLine(locale, b, name, skill.gift_every ?? 1)).filter((x): x is string => x !== null)
  // 0417: her level's own benefits as they stand now (the served step at her level), or the level each begins at
  const now = perksNow(locale, skill.level, skill.benefits)
  // 0455: a skill's own top and table (a land skill runs to 100 on its own curve); the card's are the sea's
  const top = skill.top ?? card.top
  const curve = skill.curve ?? card.curve
  const levels = Array.from({ length: top }, (_, i) => i + 1)
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
      {skill.kept === 'record' ? null : (
        <>
          {/* 0455: a land skill has no limit a day (its job's clock is its limit): no "today against the cap" line */}
          {skill.cap !== null && (
            <span className="mt-1 block text-t-caption text-ink-muted" data-testid="level-detail-today">
              {t('command.lvTodayCap', { a: formatInt(skill.today ?? 0), b: formatInt(skill.cap) })}
            </span>
          )}
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
      {now.length > 0 && (
        <ul data-testid="level-detail-perks">
          {now.map((p) => (
            <li key={p.perk} data-perk={p.perk} data-has={p.has} className={`break-words py-0.5 text-t-body ${p.has ? 'text-accent' : 'text-ink-muted'}`}>
              {p.line}
            </li>
          ))}
        </ul>
      )}
      {every.length === 0 && now.length === 0 ? (
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
            const gives = levelGives(locale, l, skill.benefits, skill.gift_every ?? 1)
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
                  {formatInt(curve[l - 1] ?? 0)}
                  {next && skill.next_at !== null && (
                    <span className="block whitespace-nowrap text-accent" data-testid="level-row-togo">
                      {t('command.lvLeft', { n: formatInt(Math.ceil(skill.next_at - skill.points)) })}
                    </span>
                  )}
                </td>
                <td className="break-words py-1 pl-3">
                  {/* a level that gives nothing (level 1) leaves the cell empty: a bare dash is a placeholder (consistency.spec) */}
                  {gives.map((g) => (
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

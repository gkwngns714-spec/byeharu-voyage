import { useState } from 'react'
import { Bar, Button, Card, GroupHeading, Icon, Note, Row, Tile, TileField, Tray, goodIcon, type TrayDetent } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { properName, translate, useLocale, useT } from '../../lib/i18n'
import { cmdLandSend, type LandJob, type LandView, type Refusal } from '../../lib/rpc'
import { levelFill, levelName } from '../../live/levelWords'
import { portNameOf, useWorld } from '../../live/worldStore'
import { inputsWord, regionWord, spanWord } from './landWords'

type Lit = Extract<LandView, { company: true }>

// ONE FACE A SKILL (docs/design/land-2026-11.md 4.2, `SkillFace`): the skill's level and its bar, then every job the server serves,
// each with the level it asks, a turn, the experience, and its land: the home land, or the far land and its passage. A row short of
// its level stays in its place, grey, with "Mining 4 / 5" (the server's have / need). A press opens the Send tray over the page:
// the terms public.land_terms gives, and Send. A new skill is new rows on the server, not a new face here.
// 0461: a MAKE job (the smith) is done at home from the home Storage: its row says what one unit uses, its tray what Storage holds of
// each, how many it can make and how long all of them take; Send makes as many as the inputs allow (the server's `make.can`).
// 2026-11-23 (the visual overhaul's slice 10): THE JOBS ARE TILES, not a list of rows: each is the good's mark, its name, where it is
// worked (the quiet line), one figure (the experience, or "Mining 1 / 96" while short of its level) and a bar of the skill's level
// against the level the job asks (full and gold once she may take it; the served have / need while short). A press opens the same
// Send tray over the field, which moves nothing.

export function SkillFace({ v }: { v: Lit }) {
  const t = useT()
  const locale = useLocale()
  const goods = useWorld((s) => s.goodByCode)
  const [open, setOpen] = useState<LandJob | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const name = levelName(locale, v.skill.code)
  const goodName = (code: string) => properName('good', code, goods[code]?.name ?? code)

  return (
    <div data-testid="land-skill" data-skill={v.skill.code}>
      <Card data-testid="land-level">
        <div className="flex items-baseline justify-between gap-3">
          <span className="text-t-card" data-testid="land-level-n" data-level={v.skill.level}>
            {`${name} ${formatInt(v.skill.level)}`}
          </span>
          <span className="text-t-body tabular-nums text-ink-muted">
            {v.skill.next_at === null ? t('land.top') : t('land.expOf', { a: formatInt(v.skill.points), b: formatInt(v.skill.next_at) })}
          </span>
        </div>
        <Bar pct={levelFill(v.skill)} label={name} tone="accent" className="mt-1" />
      </Card>
      {/* the field stands on the page, not in a card: a card's own margin left a phone one tile across */}
      <div className="mt-4" data-testid="land-jobs">
        <GroupHeading>{t('land.jobs')}</GroupHeading>
        <TileField>
          {v.jobs.map((j) => (
            <Tile
              key={j.code}
              tap="whole"
              state={j.open ? 'rest' : 'muted'}
              mark={<Icon name={goodIcon(j.good, goods[j.good]?.category ?? '')} size={22} className={j.open ? 'text-accent' : 'text-ink-faint'} />}
              name={goodName(j.good)}
              meta={
                <span data-testid="land-job-land">
                  {j.make
                    ? `${t('land.uses')} ${inputsWord(j.make.inputs, goodName)} · ${t('land.turn')} ${spanWord(j.a)}`
                    : j.home
                      ? `${t('land.atHome')} · ${t('land.turn')} ${spanWord(j.a)}`
                      : `${t('land.far')} · ${regionWord(locale, j.region, v.regions)} · ${t('land.trip')} ${spanWord(j.trip)}`}
                </span>
              }
              figure={
                <span className={`text-t-label tabular-nums ${j.open ? 'text-ink' : 'text-ink-faint'}`} data-testid="land-job-level">
                  {j.short?.code === 'E_NEEDS_SKILL'
                    ? t('land.levelOf', { name, a: formatInt(v.skill.level), b: formatInt(j.level) })
                    : t('land.xpN', { n: formatInt(j.xp) })}
                </span>
              }
              bar={
                <Bar
                  pct={j.level > 0 ? (v.skill.level / j.level) * 100 : 100}
                  tone={j.open ? 'accent' : 'neutral'}
                  label={t('land.levelOf', { name, a: formatInt(v.skill.level), b: formatInt(j.level) })}
                />
              }
              onClick={() => {
                setDetent('half')
                setOpen(j)
              }}
              data-testid="land-job"
              data-job={j.code}
              data-open={j.open}
            />
          ))}
        </TileField>
      </div>
      <Tray
        detent={open ? detent : 'closed'}
        onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
        title={open ? goodName(open.good) : ''}
        data-testid="land-send-tray"
      >
        {open && <SendTray job={open} v={v} onSent={() => setOpen(null)} />}
      </Tray>
    </div>
  )
}

/** The Send tray: what the server would do (public.land_terms, served as the job's row), and Send. */
function SendTray({ job, v, onSent }: { job: LandJob; v: Lit; onSent: () => void }) {
  const t = useT()
  const locale = useLocale()
  const refresh = useWorld((s) => s.refresh)
  const ports = useWorld((s) => s.portByCode)
  const goods = useWorld((s) => s.goodByCode)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const send = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdLandSend(job.code)
      setBusy(false)
      if (r.ok) {
        await refresh()
        onSent()
      } else setRefusal(r.refusal)
    })()
  }
  const goodName = (code: string) => properName('good', code, goods[code]?.name ?? code)
  if (job.make) {
    // 0461: a make job: what each input Storage holds against what one unit uses, how many it can make, and all of it
    const can = job.make.can
    return (
      <div className="pb-6" data-testid={`land-send-${job.code}`} data-kind="make">
        <Row label={t('land.turn')} value={<span className="tabular-nums">{spanWord(job.a)}</span>} />
        {job.make.inputs.map((i) => (
          <Row
            key={i.code}
            label={`${t('land.uses')} · ${goodName(i.code)}`}
            value={<span className={`tabular-nums ${i.have < i.qty ? 'text-ink-faint' : 'text-ink'}`} data-testid="land-send-input">{`${formatInt(i.have)} / ${formatInt(i.qty)}`}</span>}
          />
        ))}
        <Row label={t('land.canMake')} value={<span className="tabular-nums" data-testid="land-send-can">{formatInt(can)}</span>} />
        <Row label={t('land.allTime')} value={<span className="tabular-nums">{spanWord(job.a * Math.max(can, 1))}</span>} />
        <Row label={t('land.exp')} value={<span className="tabular-nums">{formatInt(job.xp * Math.max(can, 1))}</span>} />
        {job.sold_at.length > 0 && (
          <Row label={t('land.soldAt')} value={<span className="break-words text-t-label">{job.sold_at.map((c) => (c ? portNameOf(ports, c) : '')).join(', ')}</span>} hairline={false} />
        )}
        <SendFoot job={job} v={v} refusal={refusal} busy={busy} send={send} />
      </div>
    )
  }
  return (
    <div className="pb-6" data-testid={`land-send-${job.code}`}>
      <Row label={t('land.turn')} value={<span className="tabular-nums">{spanWord(job.a)}</span>} />
      {!job.home && (
        <Row
          label={t('land.passage')}
          value={<span className="tabular-nums" data-testid="land-send-passage">{t('land.eachWay', { t: spanWord(job.s) })}</span>}
        >
          <span className="block break-words text-t-caption text-ink-faint">{`${regionWord(locale, job.region, v.regions)} · ${(job.via ? portNameOf(ports, job.via) : '')}`}</span>
        </Row>
      )}
      <Row label={t('land.packs')} value={<span className="tabular-nums">{formatInt(job.p)}</span>} />
      <Row
        label={t('land.trip')}
        value={
          <span className="tabular-nums" data-testid="land-send-trip">
            {job.over_cap ? `${t('land.overCap')} · ${spanWord(job.trip)}` : spanWord(job.trip)}
          </span>
        }
      />
      <Row label={t('land.exp')} value={<span className="tabular-nums">{t('land.perTrip', { n: formatInt(job.xp * job.p) })}</span>} />
      {/* 0458: the rare finds of the land this job is worked on: none where no gem lies */}
      {job.finds.length > 0 && (
        <Row
          label={t('land.finds')}
          value={
            <span className="break-words text-t-label" data-testid="land-send-finds">
              {job.finds.map((f) => goodName(f.code)).join(', ')}
            </span>
          }
        >
          <span className="block text-t-caption text-ink-faint">
            {[...new Set(job.finds.map((f) => f.one_in))].map((n) => t('land.oneIn', { n: formatInt(n) })).join(' · ')}
          </span>
        </Row>
      )}
      {job.crowd > 0 && <Row label={t('land.company')} value={t('land.plusPct', { n: formatInt(job.crowd) })} />}
      {job.sold_at.length > 0 && (
        <Row label={t('land.soldAt')} value={<span className="break-words text-t-label">{job.sold_at.map((c) => (c ? portNameOf(ports, c) : '')).join(', ')}</span>} hairline={false} />
      )}
      <SendFoot job={job} v={v} refusal={refusal} busy={busy} send={send} />
    </div>
  )
}

/** The tray's foot, the same for every kind of job: the refusal's place (always there) and Send. */
function SendFoot({ job, v, refusal, busy, send }: { job: LandJob; v: Lit; refusal: Refusal | null; busy: boolean; send: () => void }) {
  const t = useT()
  const locale = useLocale()
  return (
    <>
      <div className="mt-3 min-h-6">
        {(refusal ?? job.short) && (
          <Note
            tone={refusal ? 'danger' : 'neutral'}
            code={(refusal ?? job.short)!.code}
            figures={(refusal ?? job.short)!.figures}
            data-testid="land-send-short"
          >
            {refusal
              ? refusal.sentence
              : job.short?.code === 'E_NEEDS_SKILL'
                ? translate(locale, 'land.levelOf', { name: levelName(locale, v.skill.code), a: formatInt(v.skill.level), b: formatInt(job.level) })
                : job.short?.sentence}
          </Note>
        )}
      </div>
      <Button variant="primary" className="mt-2 w-full" busy={busy} disabled={busy || !job.open} onClick={send} data-testid="land-send">
        {t('land.send')}
      </Button>
    </>
  )
}

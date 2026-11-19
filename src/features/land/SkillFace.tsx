import { useState } from 'react'
import { Bar, Button, Card, Note, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { properName, translate, useLocale, useT } from '../../lib/i18n'
import { cmdLandSend, type LandJob, type LandView, type Refusal } from '../../lib/rpc'
import { levelFill, levelName } from '../../live/levelWords'
import { portNameOf, useWorld } from '../../live/worldStore'
import { regionWord, spanWord } from './landWords'

type Lit = Extract<LandView, { company: true }>

// ONE FACE A SKILL (docs/design/land-2026-11.md 4.2, `SkillFace`): the skill's level and its bar, then every job the server serves,
// each with the level it asks, a turn, the experience, and its land: the home land, or the far land and its passage. A row short of
// its level stays in its place, grey, with "Mining 4 / 5" (the server's have / need). A press opens the Send tray over the page:
// the terms public.land_terms gives, and Send. A new skill is new rows on the server, not a new face here.

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
      <Card title={t('land.jobs')} className="mt-3" data-testid="land-jobs">
        {v.jobs.map((j, i) => (
          <Row
            key={j.code}
            label={goodName(j.good)}
            wholeName
            chevron
            tone={j.open ? undefined : 'muted'}
            hairline={i < v.jobs.length - 1}
            onClick={() => {
              setDetent('half')
              setOpen(j)
            }}
            value={
              <span className={`text-t-label tabular-nums ${j.open ? 'text-ink' : 'text-ink-faint'}`} data-testid="land-job-level">
                {j.open ? t('land.xpN', { n: formatInt(j.xp) }) : t('land.levelOf', { name, a: formatInt(v.skill.level), b: formatInt(j.level) })}
              </span>
            }
            data-testid="land-job"
            data-job={j.code}
            data-open={j.open}
          >
            <span className="block break-words text-t-caption text-ink-faint" data-testid="land-job-land">
              {j.home
                ? `${t('land.atHome')} · ${t('land.turn')} ${spanWord(j.a)}`
                : `${t('land.far')} · ${regionWord(locale, j.region, v.regions)} · ${t('land.trip')} ${spanWord(j.trip)}`}
            </span>
          </Row>
        ))}
      </Card>
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
              {job.finds.map((f) => properName('good', f.code, goods[f.code]?.name ?? f.code)).join(', ')}
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
    </div>
  )
}

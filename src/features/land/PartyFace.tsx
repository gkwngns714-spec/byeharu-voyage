import { useState } from 'react'
import { Bar, Button, Card, Countdown, Figure, Note, PageSplit, Row } from '../../components/ui'
import { formatDucats, formatInt } from '../../lib/format'
import { properName, useLocale, useT } from '../../lib/i18n'
import { cmdLandCollect, cmdLandHome, cmdLandTool, type LandView, type Refusal } from '../../lib/rpc'
import { useShellState } from '../../app/shellState'
import { portNameOf, useWorld } from '../../live/worldStore'
import { phaseWord, regionWord, siteWord } from './landWords'

type Lit = Extract<LandView, { company: true }>

// THE PARTY FACE (docs/design/land-2026-11.md 6.7): where the party is and what it is doing, what has come home and Collect, Call
// home; beside it the home Storage of the skill's goods, the tools, and who else is on that land. Every figure is `world.land`'s.

/** A good's name in the reader's language: the catalogue's (the snapshot's English, names/goods.ts in Korean), else the code. */
function useGoodName(): (code: string | null) => string {
  const goods = useWorld((s) => s.goodByCode)
  return (code) => (code ? properName('good', code, goods[code]?.name ?? code) : '')
}

export function PartyFace({ v }: { v: Lit }) {
  const t = useT()
  const locale = useLocale()
  const { nowMs } = useShellState()
  const goodName = useGoodName()
  const refresh = useWorld((s) => s.refresh)
  const ports = useWorld((s) => s.portByCode)
  const [busy, setBusy] = useState<'collect' | 'home' | 'tool' | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const p = v.party
  const pr = p.progress
  const terms = p.terms
  const out = p.action !== null && terms !== null

  const press = (which: 'collect' | 'home' | 'tool', act: () => Promise<{ ok: boolean; refusal?: Refusal }>) => {
    if (busy) return
    setBusy(which)
    setRefusal(null)
    void (async () => {
      const r = await act()
      if (r.ok) await refresh()
      else if (r.refusal) setRefusal(r.refusal)
      setBusy(null)
    })()
  }

  // where it stands in this trip, as a fill of the served figures (`u` of `trip`); called home or at home, none
  const fill = out && pr.state === 'out' && pr.u !== undefined && pr.trip ? (pr.u / pr.trip) * 100 : out ? 100 : 0
  const homeAt = pr.state === 'returning' ? pr.home_at : pr.next_home_at
  const site = siteWord(locale, p.region ?? v.home.region, 'mines', v.regions)

  const main = (
    <Card title={`${t('land.party')} · ${site}`} data-testid="land-party">
      <Row
        label={<span data-testid="land-phase" data-phase={pr.phase}>{pr.stopped ? t('land.stopped') : phaseWord(locale, pr.phase)}</span>}
        value={out ? <span className="text-t-body text-ink">{goodName(p.good)}</span> : undefined}
        hairline={false}
      >
        <Bar pct={fill} label={t('land.trip')} tone="accent" className="mt-1" />
      </Row>
      <Row
        label={t('land.packs')}
        value={<span className="tabular-nums" data-testid="land-packs">{terms ? `${formatInt(pr.in_packs)} / ${formatInt(terms.p)}` : '0'}</span>}
      />
      <Row
        label={t('land.homeIn')}
        value={
          homeAt && out ? (
            <Countdown untilMs={Date.parse(homeAt)} nowMs={nowMs} className="tabular-nums" />
          ) : (
            <span className="text-ink-muted">{t('land.idle')}</span>
          )
        }
      />
      <Row
        label={t('land.toBook')}
        value={
          <span className="tabular-nums" data-testid="land-to-book">
            {formatInt(pr.new + p.waiting)} {pr.new + p.waiting > 0 ? goodName(p.good ?? p.waiting_good) : ''}
          </span>
        }
        hairline={false}
      />
      <div className="mt-3 grid grid-cols-2 gap-2">
        <Button
          variant="primary"
          busy={busy === 'collect'}
          disabled={busy !== null}
          onClick={() => press('collect', () => cmdLandCollect())}
          data-testid="land-collect"
        >
          {t('land.collect')}
        </Button>
        <Button
          variant="secondary"
          busy={busy === 'home'}
          disabled={busy !== null || !out || pr.state === 'returning'}
          onClick={() => press('home', () => cmdLandHome())}
          data-testid="land-home"
        >
          {t('land.home')}
        </Button>
      </div>
      {/* the refusal's place is always there, so a refusal never moves what is under it */}
      <div className="mt-2 min-h-6" data-testid="land-refusal-slot">
        {refusal && (
          <Note tone="danger" code={refusal.code} figures={refusal.figures}>
            {refusal.sentence}
          </Note>
        )}
      </div>
      {out && terms && !terms.home && (
        <p className="mt-1 break-words text-t-caption text-ink-faint" data-testid="land-far-line">
          {`${t('land.far')} · ${regionWord(locale, p.region, v.regions)} · ${t('land.passage')} ${(terms.via ? portNameOf(ports, terms.via) : '')}`}
        </p>
      )}
    </Card>
  )

  const stored = Object.entries(v.stored).filter(([, n]) => n > 0)
  const side = (
    <>
      <Card title={t('land.stored')} data-testid="land-stored">
        {stored.length === 0 ? (
          <Row label={<span className="text-ink-muted">0</span>} hairline={false} />
        ) : (
          stored.map(([code, n], i) => (
            <Row key={code} label={goodName(code)} value={<span className="tabular-nums">{formatInt(n)}</span>} hairline={i < stored.length - 1} />
          ))
        )}
        <p className="mt-1 text-t-caption text-ink-faint">{`${v.home.name} · ${t('land.awayHours', { n: v.away_hours })}`}</p>
      </Card>
      <Card title={t('land.tools')} data-testid="land-tools">
        {v.tools.map((tool, i) => (
          <Row
            key={tool.code}
            label={t('land.faster', { n: tool.speed_pct })}
            end
            hairline={i < v.tools.length - 1}
            value={
              tool.owned ? (
                <span className="text-t-label text-success">{t('land.owned')}</span>
              ) : (
                <Button
                  size="sm"
                  variant="secondary"
                  busy={busy === 'tool'}
                  disabled={busy !== null}
                  onClick={() => press('tool', () => cmdLandTool(tool.code))}
                  data-testid={`land-tool-${tool.code}`}
                >
                  {`${t('land.buy')} ${formatDucats(tool.price)}`}
                </Button>
              )
            }
          />
        ))}
        <p className="mt-1 text-t-caption text-ink-faint">
          <Figure value={formatDucats(v.purse)} />
        </p>
      </Card>
      <Card title={`${t('land.here')} · ${regionWord(locale, v.site.region, v.regions)}`} data-testid="land-here">
        {v.site.parties.filter((x) => !x.mine).length === 0 ? (
          <Row label={<span className="text-ink-muted">{t('land.nobody')}</span>} hairline={false} />
        ) : (
          v.site.parties
            .filter((x) => !x.mine)
            .map((x, i, all) => <Row key={x.company} label={x.company} value={phaseWord(locale, x.phase)} hairline={i < all.length - 1} />)
        )}
      </Card>
    </>
  )

  return <PageSplit main={main} side={side} data-testid="land-party-face" />
}

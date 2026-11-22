import { useState } from 'react'
import { Bar, Button, Card, Countdown, Figure, Icon, Note, PageSplit, Row, Segmented, goodIcon } from '../../components/ui'
import { formatDucats, formatInt } from '../../lib/format'
import { properName, useLocale, useT } from '../../lib/i18n'
import { cmdLandCollect, cmdLandHome, cmdLandPack, cmdLandRepeat, cmdLandTool, type LandDone, type LandView, type Refusal } from '../../lib/rpc'
import { useShellState } from '../../app/shellState'
import { portNameOf, useWorld } from '../../live/worldStore'
import { foundWord, phaseWord, regionWord, siteWord } from './landWords'
import { LandSite } from './LandSite'

type Lit = Extract<LandView, { company: true }>

// THE PARTY FACE (docs/design/land-2026-11.md 6.7): where the party is and what it is doing, what has come home and Collect, Call
// home; beside it the home Storage of the skill's goods, the tools, and who else is on that land. Every figure is `world.land`'s.
// 0458: Repeat (On / Off, the party goes again by itself), the mules (the next one bought from the Tools card), and the rare finds:
// what a Collect found is said in the slot that is always there under the buttons, so nothing below it moves.
// 0461: a MAKE job (the smith) works at home: the card says the home city, "Making", and how many of the units it was sent for are
// made; what a Collect gave back of a make's inputs is said in the same slot.
// 2026-11-23 (the visual overhaul's slice 10): the card opens on a drawing of the site (./LandSite.tsx), the party on its road as far
// along as the trip bar under it; the Storage lists each good by its mark.

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
  const goods = useWorld((s) => s.goodByCode)
  const [busy, setBusy] = useState<'collect' | 'home' | 'tool' | 'pack' | 'repeat' | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  // what the last Collect found (0458), said in the refusal's slot
  const [found, setFound] = useState<Record<string, number> | null>(null)
  // 0461: what the last Collect gave back of a make job's inputs
  const [back, setBack] = useState<Record<string, number> | null>(null)
  const p = v.party
  const pr = p.progress
  const terms = p.terms
  const out = p.action !== null && terms !== null

  const press = (
    which: 'collect' | 'home' | 'tool' | 'pack' | 'repeat',
    act: () => Promise<{ ok: true; value: LandDone } | { ok: false; refusal: Refusal }>,
  ) => {
    if (busy) return
    setBusy(which)
    setRefusal(null)
    setFound(null)
    setBack(null)
    void (async () => {
      const r = await act()
      if (r.ok) {
        const got = r.value.found
        if (got && Object.keys(got).length > 0) setFound(got)
        const gave = r.value.given_back
        if (gave && Object.keys(gave).length > 0) setBack(gave)
        await refresh()
      }
      else if (r.refusal) setRefusal(r.refusal)
      setBusy(null)
    })()
  }

  // where it stands in this trip, as a fill of the served figures (`u` of `trip`); called home or at home, none
  const fill = out && pr.state === 'out' && pr.u !== undefined && pr.trip ? (pr.u / pr.trip) * 100 : out ? 100 : 0
  const homeAt = pr.state === 'returning' ? pr.home_at : pr.next_home_at
  const make = !!terms?.take   // 0461: a make job, at home
  const site = make ? v.home.name : siteWord(locale, p.region ?? v.home.region, 'mines', v.regions)

  const main = (
    <Card title={`${t('land.party')} · ${site}`} data-testid="land-party">
      <div className="mb-2 overflow-hidden rounded-tile border border-edge">
        <LandSite at={fill} out={out} far={out && terms !== null && !terms.home} make={make} />
      </div>
      <Row
        label={<span data-testid="land-phase" data-phase={pr.phase}>{pr.stopped ? t('land.stopped') : phaseWord(locale, pr.phase, make)}</span>}
        value={out ? <span className="text-t-body text-ink">{goodName(p.good)}</span> : undefined}
        hairline={false}
      >
        <Bar pct={fill} label={t('land.trip')} tone="accent" className="mt-1" />
      </Row>
      <Row
        label={make ? t('land.made') : t('land.packs')}
        value={
          <span className="tabular-nums" data-testid="land-packs">
            {terms ? (make ? `${formatInt(pr.turns)} / ${formatInt(terms.last ?? 0)}` : `${formatInt(pr.in_packs)} / ${formatInt(terms.p)}`) : '0'}
          </span>
        }
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
            {Object.keys(p.found_waiting).length > 0 ? ` · ${foundWord(p.found_waiting, goodName)}` : ''}
          </span>
        }
      />
      {/* 0458: Repeat, the party goes out again by itself (on) or comes home after the trip under way (off) */}
      <Row
        label={t('land.repeat')}
        end
        hairline={false}
        value={
          <span data-testid="land-repeat" data-on={p.repeat ? 'true' : 'false'}>
            <Segmented<'on' | 'off'>
              segments={[
                { id: 'on', label: t('land.on') },
                { id: 'off', label: t('land.off') },
              ]}
              value={p.repeat ? 'on' : 'off'}
              onChange={(next) => {
                if ((next === 'on') !== p.repeat) press('repeat', () => cmdLandRepeat(next === 'on'))
              }}
              label={t('land.repeat')}
              columns={2}
            />
          </span>
        }
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
        {refusal ? (
          <Note tone="danger" code={refusal.code} figures={refusal.figures}>
            {refusal.sentence}
          </Note>
        ) : found ? (
          <Note tone="success" data-testid="land-found">
            {t('land.found', { list: foundWord(found, goodName) })}
          </Note>
        ) : back ? (
          <Note tone="neutral" data-testid="land-back">
            {t('land.back', { list: foundWord(back, goodName) })}
          </Note>
        ) : null}
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
            <Row
              key={code}
              mark={<Icon name={goodIcon(code, goods[code]?.category ?? '')} size={20} className="text-accent" />}
              label={goodName(code)}
              value={<span className="tabular-nums">{formatInt(n)}</span>}
              hairline={i < stored.length - 1}
            />
          ))
        )}
        <p className="mt-1 text-t-caption text-ink-faint">{`${v.home.name} · ${t('land.awayHours', { n: v.away_hours })}`}</p>
      </Card>
      <Card title={t('land.tools')} data-testid="land-tools">
        {v.tools.map((tool) => (
          <Row
            key={tool.code}
            label={t('land.faster', { n: tool.speed_pct })}
            end
            hairline
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
        {/* 0458: the mules: what a trip carries now, and the next mule for coin (the last bought, "Full") */}
        <Row
          label={t('land.mules')}
          end
          hairline={false}
          data-testid="land-mules"
          value={
            v.packs.next ? (
              <Button
                size="sm"
                variant="secondary"
                busy={busy === 'pack'}
                disabled={busy !== null}
                onClick={() => press('pack', () => cmdLandPack())}
                data-testid="land-mule-buy"
              >
                {`${t('land.buy')} ${formatDucats(v.packs.next.price)}`}
              </Button>
            ) : (
              <span className="text-t-label text-success">{t('land.full')}</span>
            )
          }
        >
          <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="land-packs-now">
            {v.packs.next
              ? t('land.packsTo', { a: formatInt(v.packs.now), b: formatInt(v.packs.next.packs) })
              : t('land.packsN', { n: formatInt(v.packs.now) })}
          </span>
        </Row>
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

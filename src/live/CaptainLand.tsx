import { useState } from 'react'
import { Button, Chip, Figure, Note, Row, Skeleton, Stepper } from '../components/ui'
import { formatDucats, formatFixed, formatInt, formatRealShort, instantMs } from '../lib/format'
import { useT } from '../lib/i18n'
import {
  cmdCaptainDismiss,
  cmdCaptainLand,
  cmdCaptainPlace,
  cmdCaptainUpgrade,
  cmdLandExpedition,
  ok,
  worldLandExpedition,
  type CaptainPlaces,
  type LandAsk,
  type LandCard,
  type LandExpeditionView,
  type LandRun,
  type LandShort,
  type Refusal,
  type RpcResult,
  type YourCaptain,
} from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CAPTAIN ASHORE: her works, her land expedition, her HONOR BADGES, her place (0527 to 0534; the owner's R4)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Everything here is a served answer, and EVERY BLOCK IS ABSENT WHILE ITS SWITCH IS DARK, by the server's own key: `works` (captain works),
// `world.land_expedition().on`, `upgrades` and `honor` (the badges), `places`. No block draws a press its door would refuse for being dark.
// The expedition's card is the Send's own quote (public.land_expedition_terms): what a round costs and brings, how many rounds and what stops
// them, the bill. NO CHANCE OF WINNING is served and none is drawn. One press, one request.

type Press = () => Promise<RpcResult<unknown>>

/** One press at a time, its refusal kept by the block that pressed, the world read again after. */
function usePress() {
  const refresh = useWorld((s) => s.refresh)
  const [busy, setBusy] = useState<string | null>(null)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const press = (key: string, run: Press, done?: () => void) => {
    if (busy !== null) return
    setBusy(key)
    setRefusal(null)
    void (async () => {
      const r = await run()
      if (r.ok) {
        done?.()
        await refresh()
      } else setRefusal(r.refusal)
      setBusy(null)
    })()
  }
  return { busy, refusal, press }
}

function Refused({ refusal, id }: { refusal: Refusal | null; id: string }) {
  return refusal ? (
    <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2" data-testid={id}>
      {refusal.sentence}
    </Note>
  ) : null
}

const H = ({ children }: { children: string }) => <h4 className="pb-1 pt-4 text-t-caption text-ink-faint">{children}</h4>

/** HER WORKS: a level each on the long curve, a bar to the next. Absent while the works are dark. */
export function CaptainWorks({ captain }: { captain: YourCaptain }) {
  const t = useT()
  // a work nothing raises yet (wood: no land job gathers it) is drawn only once she has some of it
  const works = (captain.works ?? []).filter((w) => w.xp > 0 || w.work !== 'woodcutting')
  if (works.length === 0) return null
  return (
    <div data-testid="captain-works">
      <H>{t('books.works')}</H>
      {works.map((w, i) => {
        const span = w.next_at === null ? 1 : Math.max(1, w.next_at - w.from)
        const fill = w.next_at === null ? 100 : Math.max(0, Math.min(100, ((w.xp - w.from) / span) * 100))
        return (
          <Row
            key={w.work}
            label={w.word}
            value={
              <span className="inline-flex items-center gap-2">
                <span className="h-1 w-20 overflow-hidden rounded-full bg-surface-2">
                  <span className="block h-full bg-accent" style={{ width: `${fill}%` }} />
                </span>
                <Figure value={formatInt(w.level)} />
              </span>
            }
            hairline={i < works.length - 1}
            data-testid={`captain-work-${w.work}`}
          />
        )
      })}
    </div>
  )
}

/** HER UPGRADES, bought with HONOR BADGES. Absent while the badges are dark. */
export function CaptainUpgrades({ captain, honor }: { captain: YourCaptain; honor: number | undefined }) {
  const t = useT()
  const { busy, refusal, press } = usePress()
  if (!captain.upgrades || honor === undefined) return null
  return (
    <div data-testid="captain-upgrades" data-honor={honor}>
      <H>{t('books.upgrades', { n: formatInt(honor) })}</H>
      {captain.upgrades.map((u, i) => (
        <Row
          key={u.upgrade}
          label={`${u.word} · ${formatInt(u.rank)} / ${formatInt(u.top)}`}
          value={
            u.cost === null ? (
              <span className="text-ink-muted">+{formatInt(u.pct)} %</span>
            ) : (
              <Button
                disabled={busy !== null || u.cost > honor || !captain.can_change}
                busy={busy === u.upgrade}
                busyLabel={t('books.upgrading')}
                onClick={() => press(u.upgrade, () => cmdCaptainUpgrade(captain.code, u.upgrade))}
                data-testid={`captain-upgrade-${u.upgrade}`}
              >
                {t('books.badgesFor', { n: formatInt(u.cost) })}
              </Button>
            )
          }
          hairline={i < captain.upgrades!.length - 1}
        />
      ))}
      <Refused refusal={refusal} id="captain-upgrade-refused" />
    </div>
  )
}

const isShort = (c: LandCard | LandShort): c is LandShort => 'short' in c

function Runs({ run, nowMs }: { run: LandRun; nowMs: number }) {
  const t = useT()
  const homeMs = instantMs(run.home_at)
  const gathers = run.work === 'land_gather'
  return (
    <div data-testid="land-run" data-state={run.state} data-ended={run.ended ?? undefined}>
      <Row label={run.word ?? ''} value={<Figure value={`${formatInt(run.rounds)} / ${formatInt(run.most)}`} unit={t('land.rounds')} />} data-testid="land-run-rounds" />
      <Row label={t('land.crew')} value={<Figure value={formatInt(run.crew)} />} />
      <Row label={t('land.stores')} value={<Figure value={formatFixed(run.stores, 1)} unit="t" />} />
      {run.state === 'out' && homeMs !== null && (
        <Row label={t('land.homeIn')} value={<Figure value={formatRealShort(Math.max(0, homeMs - nowMs))} />} data-testid="land-run-home" />
      )}
      <Row label={t('land.inHand')} value={<Figure value={gathers ? formatInt(run.carry.units ?? 0) : formatInt(run.carry.xp ?? 0)} unit={gathers ? t('ui.unitUnits') : t('land.exp')} />} />
      {run.log.length > 0 && (
        <ul className="max-h-40 overflow-y-auto py-1 text-t-caption text-ink-muted" data-testid="land-log">
          {[...run.log].reverse().map((l) => (
            <li key={l.r} className="flex justify-between gap-2 py-0.5">
              <span>{t('land.roundN', { n: formatInt(l.r) })}</span>
              <span className="tabular-nums">
                {[gathers ? `+${formatInt(l.units)}` : t(l.result === 1 ? 'land.beaten' : 'land.heldOff'), l.crew > 0 ? t('land.lost', { n: formatInt(l.crew) }) : null, l.fed ? t('land.foraged') : null]
                  .filter(Boolean)
                  .join(' · ')}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/** WHERE SHE IS SENT: the targets, the hands, the provisions, the stop, and the Send's own card under them. */
function Plan({ captain, view }: { captain: YourCaptain; view: LandExpeditionView }) {
  const t = useT()
  const { busy, refusal, press } = usePress()
  const open = (view.targets ?? []).filter((x) => x.open)
  const [work, setWork] = useState<LandAsk['work']>('land_gather')
  const [target, setTarget] = useState<string | null>(null)
  const [crew, setCrew] = useState(Math.max(1, view.cap ?? 1))
  const [stores, setStores] = useState<number | null>(null)
  const [rounds, setRounds] = useState(0)
  const [then, setThen] = useState<'home' | 'repeat'>('home')
  const list = open.filter((x) => x.work === work)
  const picked = list.find((x) => x.target === target) ?? list[0] ?? null
  const ask: LandAsk | null = picked
    ? { work, target: picked.target, crew, then, ...(stores !== null ? { stores } : {}), ...(rounds > 0 ? { stop: { rounds } } : {}) }
    : null
  const key = ask ? JSON.stringify(ask) : null
  const quote = useServedRead<{ card: LandCard | LandShort | null }>(
    ask ? `land-quote:${captain.code}` : null,
    async () => {
      const r = await worldLandExpedition(captain.code, ask)
      return r.ok ? ok({ card: r.value.card ?? null }) : r
    },
    { question: key, name: 'landQuote', cache: false },
  )
  const served = quote.view?.card ?? null
  const card = served && !isShort(served) ? served : null
  const short = served && isShort(served) ? served.short : null
  const cap = view.cap ?? 1
  const why: Record<string, string> = { food: t('land.whyFood'), crew: t('land.whyCrew'), load: t('land.whyLoad'), rounds: t('land.whyRounds'), cap: t('land.whyCap') }
  return (
    <div data-testid="land-plan">
      <div className="flex flex-wrap gap-2 pb-2">
        <Chip on={work === 'land_gather'} onClick={() => { setWork('land_gather'); setTarget(null); setStores(null) }} data-testid="land-work-gather">
          {t('land.gather')}
        </Chip>
        {view.raids && (
          <Chip on={work === 'land_raid'} onClick={() => { setWork('land_raid'); setTarget(null); setStores(null) }} data-testid="land-work-raid">
            {t('land.raid')}
          </Chip>
        )}
      </div>
      <div className="flex flex-wrap gap-2 pb-2" data-testid="land-targets">
        {list.map((x) => (
          <Chip key={x.target} on={picked?.target === x.target} onClick={() => { setTarget(x.target); setStores(null) }} data-testid={`land-target-${x.target}`}>
            {x.word}
          </Chip>
        ))}
      </div>
      {picked === null ? (
        <Note tone="neutral">{t('land.noTarget')}</Note>
      ) : (
        <>
          <H>{t('land.crew')}</H>
          <Stepper value={crew} onChange={setCrew} max={cap} min={1} step={1} unit={t('land.hands')} label={t('land.crew')} data-testid="land-crew" />
          <H>{t('land.stores')}</H>
          <Stepper
            value={Math.round(stores ?? card?.stores ?? 0)}
            onChange={(n) => setStores(n)}
            max={Math.max(1, Math.round(card?.carry ?? crew))}
            min={0}
            step={1}
            unit="t"
            label={t('land.stores')}
            data-testid="land-stores"
          />
          <H>{t('land.stopAfter')}</H>
          <Stepper value={rounds} onChange={setRounds} max={72} min={0} step={1} unit={rounds === 0 ? t('land.noStop') : t('land.rounds')} label={t('land.stopAfter')} data-testid="land-stop" />
          <div className="flex gap-2 py-2">
            <Chip on={then === 'home'} onClick={() => setThen('home')} data-testid="land-then-home">
              {t('land.stayHome')}
            </Chip>
            <Chip on={then === 'repeat'} onClick={() => setThen('repeat')} data-testid="land-then-repeat">
              {t('land.again')}
            </Chip>
          </div>
          {/* THE CARD keeps its height while a figure is asked again */}
          <div className="min-h-[300px]" data-testid="land-card" data-total={card?.total}>
            {card ? (
              <div className={quote.stale ? 'opacity-60' : undefined}>
                <Row label={t('land.roundsWord')} value={<Figure value={formatInt(card.most)} unit={why[card.why] ?? ''} />} data-testid="land-card-rounds" />
                <Row label={t('land.aRound')} value={<Figure value={formatRealShort(card.seconds * 1000)} />} />
                <Row label={t('land.storesRound')} value={<Figure value={formatFixed(card.use, 2)} unit="t" />} />
                <Row label={t('land.crewRound')} value={<Figure value={formatFixed(card.cost.hands, 2)} />} data-testid="land-card-hands" />
                <Row label={t('land.brings')} value={<Figure value={card.units !== undefined ? `${formatInt(card.units)} ${picked.word}` : formatInt(card.xp)} unit={card.units !== undefined ? '' : t('land.exp')} />} />
                <Row label={t('land.bill')} value={<Figure value={formatDucats(card.total)} />} hairline={false} data-testid="land-card-bill" />
              </div>
            ) : short ? (
              <Note tone="warning" code={short.code ?? short.error_code} figures={short.figures ?? undefined} data-testid="land-card-short">
                {short.sentence ?? short.error_message ?? ''}
              </Note>
            ) : (
              <Skeleton className="h-[280px] w-full" />
            )}
          </div>
          <Button
            variant="primary"
            className="min-h-11 w-full"
            disabled={card === null || quote.stale || busy !== null}
            busy={busy === 'send'}
            busyLabel={t('ui.sending')}
            onClick={() => press('send', () => cmdLandExpedition(captain.code, ask))}
            data-testid="land-send"
          >
            {t('land.send')}
          </Button>
          <Refused refusal={refusal} id="land-send-refused" />
        </>
      )}
    </div>
  )
}

/** HER LAND EXPEDITION, and her place ashore. Absent while the works are dark; the expedition while its own switch is. */
export function CaptainAshore({ captain }: { captain: YourCaptain }) {
  const t = useT()
  const { busy, refusal, press } = usePress()
  const lit = captain.works !== undefined
  const read = useServedRead<LandExpeditionView>(lit ? `land-expedition:${captain.code}` : null, () => worldLandExpedition(captain.code, null), { name: 'worldLandExpedition' })
  const [planning, setPlanning] = useState(false)
  if (!lit) return null
  const view = read.view
  const on = view?.on === true && view.company === true
  const run = view?.runs?.find((r) => r.captain === captain.code) ?? null
  const out = run !== null && run.state === 'out'
  const nowMs = view?.now ? (instantMs(view.now) ?? 0) : 0
  const onLand = captain.party !== null && captain.party !== undefined
  return (
    <div data-testid="captain-ashore" data-party={captain.party ?? undefined}>
      <H>{t('land.ashoreTitle')}</H>
      <Row
        label={onLand ? t('land.leads') : captain.ship ? captain.ship : t('books.ashore')}
        value={
          captain.can_change && !out ? (
            <Button
              disabled={busy !== null}
              busy={busy === 'seat'}
              busyLabel={t('ui.sending')}
              onClick={() => press('seat', () => cmdCaptainLand(captain.code, onLand ? null : 1))}
              data-testid="captain-land-seat"
            >
              {onLand ? t('land.leaveParty') : t('land.leadParty')}
            </Button>
          ) : undefined
        }
        hairline={on}
      />
      {on && view && run && (
        <>
          <H>{t('land.expedition')}</H>
          <Runs run={run} nowMs={nowMs} />
          {out && (
            <Button
              className="min-h-11 w-full"
              disabled={busy !== null || run.ended === 'called'}
              busy={busy === 'home'}
              busyLabel={t('ui.sending')}
              onClick={() => press('home', () => cmdLandExpedition(captain.code, null))}
              data-testid="land-call-home"
            >
              {t('land.home')}
            </Button>
          )}
        </>
      )}
      {on && view && !out && captain.can_change && (
        planning ? (
          <Plan captain={captain} view={view} />
        ) : (
          <Button variant="primary" className="mt-2 min-h-11 w-full" onClick={() => setPlanning(true)} data-testid="land-plan-open">
            {t('land.expedition')}
          </Button>
        )
      )}
      <Refused refusal={refusal} id="captain-ashore-refused" />
    </div>
  )
}

/** LET HER GO: shown only with the places lit (before, no door dismissed a captain); pressed twice. */
export function CaptainDismiss({ captain, places }: { captain: YourCaptain; places: CaptainPlaces | undefined }) {
  const t = useT()
  const { busy, refusal, press } = usePress()
  const [sure, setSure] = useState(false)
  if (!places || !captain.can_change) return null
  return (
    <div className="pt-4" data-testid="captain-dismiss-block">
      <Button
        variant="quiet"
        className="min-h-11 w-full"
        disabled={busy !== null}
        busy={busy === 'go'}
        busyLabel={t('ui.sending')}
        onClick={() => (sure ? press('go', () => cmdCaptainDismiss(captain.code)) : setSure(true))}
        data-testid="captain-dismiss"
      >
        {sure ? t('books.dismissSure') : t('books.dismiss')}
      </Button>
      <Refused refusal={refusal} id="captain-dismiss-refused" />
    </div>
  )
}

/** THE COMPANY'S CAPTAIN PLACES AND ITS BADGES, at the head of the roster. A place that is not priced says so and has no press. */
export function CaptainPlacesLine({ places, honor }: { places: CaptainPlaces | undefined; honor: number | undefined }) {
  const t = useT()
  const { busy, refusal, press } = usePress()
  if (!places && honor === undefined) return null
  const next = places?.next ?? null
  return (
    <div data-testid="captain-places" data-used={places?.used} data-places={places?.places}>
      {honor !== undefined && <Row label={t('books.badges')} value={<Figure value={formatInt(honor)} />} data-testid="honor-balance" />}
      {places && <Row label={t('books.places')} value={<Figure value={`${formatInt(places.used)} / ${formatInt(places.places)}`} />} hairline={next !== null} />}
      {next && !next.open && <Row label={t('books.placeN', { n: formatInt(next.place) })} value={<span className="text-ink-muted">{t('books.placeShut')}</span>} data-testid="captain-place-shut" />}
      {next && next.open && (
        <Row
          label={t('books.placeAsks', { level: formatInt(next.total_level), rep: formatInt(next.reputation), coin: formatDucats(next.ducats) })}
          value={
            <Button
              disabled={busy !== null || next.have.total_level < next.total_level || next.have.reputation < next.reputation || next.have.ducats < next.ducats}
              busy={busy === 'place'}
              busyLabel={t('ui.sending')}
              onClick={() => press('place', () => cmdCaptainPlace())}
              data-testid="captain-place-open"
            >
              {t('books.openPlace')}
            </Button>
          }
        />
      )}
      <Refused refusal={refusal} id="captain-place-refused" />
    </div>
  )
}

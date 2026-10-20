import { useState } from 'react'
import {
  Button,
  Field,
  Figure,
  Hint,
  Icon,
  Note,
  Row,
  Tile,
  TileField,
  Tray,
  type TrayDetent,
} from '../components/ui'
import { HullCountry } from './HullCountry'
import { HullTech } from './HullTech'
import { useBuildingYard } from './useBuildingYard'
import { useWorld } from './worldStore'
import { formatDucats, formatInt, formatTons } from '../lib/format'
import type { FleetView, HullMaterial, Refusal, YardHull } from '../lib/rpc'
import { useT, t as tNow } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE YARD — where a hull is laid down (0072), as a field of tiles.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"i want another building - a 건조소 in korean, where you can create ships. Building
// ships will require not only some of the trading goods, but some items."*
//
// ── THE ONE THING THIS SCREEN HAS TO MAKE OBVIOUS ──────────────────────────────────────────────
// The materials come out of THIS CITY — its storage for timber, your store for fittings — and
// never out of her hold. A player who does not understand that will carry 40 tuns of timber to the
// yard, watch the order refuse, and conclude the game is broken. So every material row prints what
// is ashore HERE against what she wants.
//
// ── NO DRAFT WARNING (0139) ────────────────────────────────────────────────────────────────────
// Migration 0139 removed the E_DRAFT sailing gate: any hull enters any harbour, so a hull laid down
// here can never be too deep for this quay, and the yard says nothing about depth.
//
// ── A BORDER THAT NEVER RENDERED ───────────────────────────────────────────────────────────────
// The name box was `rounded border border-line bg-surface`. There has never been a `--color-line`
// token in `src/index.css` — the border was invisible from the day it was written, which is what a
// hand-drawn skin buys you (§3 rule 4). It is a `Field` now: one recipe, one focus ring, one 44px
// floor, and no token that has to exist for it to look right.
//
// ── A HULL'S COUNTRY (0130) ────────────────────────────────────────────────────────────────────
// Every hull belongs to a country's shipbuilding line and shows that country's flag. A hull is
// built only at build yards in its line's countries (some, like the three first hulls, at any).
// The server serves both halves of `buildable` — `tier_ok` and `wrong_yard`, the very sentence
// cmd.do_build refuses with (E_WRONG_YARD) — and the tray prints them as served.
//
// ── WHAT A HULL NEEDS OF YOU (0133) ────────────────────────────────────────────────────────────
// A hull may need a skill ("Nau / Carrack needs Portuguese Medium Hulls IV"). The server serves that
// sentence as `needs` — the very one cmd.do_build refuses with (E_NEEDS_SKILL) — and folds it into
// `buildable`; the tray prints it as served. null (nothing printed) while skills do not bite.
//
// ── WHAT THIS FILE DOES NOT KNOW ───────────────────────────────────────────────────────────────
// Whether a hull can be built here. All of that is `cmd.do_build`'s and arrives answered.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** What is missing, in the server's own numbers, or null when everything is to hand. */
function shortfall(hull: YardHull): string | null {
  const short = [...hull.goods, ...hull.items].filter((m) => m.have < m.qty)
  if (short.length === 0) return null
  return short.map((m) => `${m.name} ${formatInt(m.have)}/${formatInt(m.qty)}`).join(' · ')
}

export function PortYard({
  portId,
  fleet,
  tier,
}: {
  portId: string
  /** A fleet of yours lying here, or null — a new hull joins the fleet that ordered her. */
  fleet: FleetView | null
  /** This city's building-yard tier, from the port's own building row. */
  tier: number
}) {
  const t = useT()
  const { view, loading } = useBuildingYard(portId)
  const [open, setOpen] = useState<YardHull | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [name, setName] = useState('')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const issue = useWorld((s) => s.issue)

  const build = (hull: YardHull) => {
    if (!fleet || sending || name.trim().length < 3) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const okay = await issue(fleet.id, `BUILD ${hull.class} ${name.trim()}`, null)
      setSending(false)
      if (okay) {
        setOpen(null)
        setName('')
      } else {
        setRefusal(useWorld.getState().refusal)
      }
    })()
  }

  if (loading && !view) return <Note tone="neutral">{t('yard.loading')}</Note>
  if (!view) return <Note tone="neutral">{t('yard.noYard')}</Note>

  // 0135 — 55 hulls, most of them another country's: the ones THIS port's country builds first (the
  // server's own `wrong_yard` is null for them), the rest after, under one caption. A split of the
  // served list, not a rule — the server already said which is which.
  const here = view.hulls.filter((h) => !h.wrong_yard)
  const elsewhere = view.hulls.filter((h) => h.wrong_yard)
  const short = open ? shortfall(open) : null
  const ready = open !== null && open.buildable && fleet !== null && short === null

  return (
    <div data-testid="port-yard">
      {!fleet && (
        <Note tone="warning" className="mb-3">
          {t('yard.noFleetYard')}
        </Note>
      )}

      {[here, elsewhere].map((group, gi) =>
        group.length === 0 ? null : (
          <div
            key={gi}
            className={gi === 1 ? 'mt-4' : undefined}
            data-testid={gi === 0 ? 'yard-here' : 'yard-elsewhere'}
          >
            {gi === 1 && <Hint className="mb-2">{t('yard.elsewhere')}</Hint>}
            <TileField>
              {group.map((hull) => (
                <Tile
                  key={hull.class}
                  mark={<Icon name="ship" size={20} />}
                  name={hull.name}
                  meta={
                    <>
                      <HullCountry nation={hull.line_nation} compact />
                      {hull.line_nation ? ' ' : ''}
                      <HullTech tech={hull.tech} />
                      {formatTons(hull.hold)}
                    </>
                  }
                  state={hull.buildable ? 'rest' : 'muted'}
                  tap="whole"
                  onClick={() => {
                    setRefusal(null)
                    setDetent('half')
                    setOpen(hull)
                  }}
                  figure={<Figure value={formatDucats(hull.ducats)} unit={t('yard.toBuild')} />}
                  data-testid={`hull-${hull.class}`}
                />
              ))}
            </TileField>
          </div>
        ),
      )}

      {open && (
        <Tray
          detent={detent}
          onDetentChange={(next) => (next === 'closed' ? setOpen(null) : setDetent(next))}
          title={open.name}
          data-testid="yard-tray"
          action={
            ready ? (
              <Button
                variant="primary"
                className="w-full"
                busy={sending}
                busyLabel={t('yard.building')}
                disabled={name.trim().length < 3}
                onClick={() => build(open)}
                data-testid={`lay-down-${open.class}`}
              >
                {t('yard.layDown')}
              </Button>
            ) : undefined
          }
        >
          {/* 0166 (S17): a famous ship carries her history line — the hull's served note, printed as served */}
          {open.tech === 'F' && (
            <Hint className="mb-2" data-testid="yard-history">
              {open.note}
            </Hint>
          )}
          {open.line_nation && <Row label={t('yard.country')} value={<HullCountry nation={open.line_nation} />} />}
          <Row label={t('yard.cargo')} value={<Figure value={formatInt(open.hold)} unit={t('yard.tons')} />} />
          <Row label={t('yard.speed')} value={<Figure value={open.speed_kn} unit={t('yard.knots')} />} />
          <Row label={t('yard.crewNeeded')} value={<Figure value={formatInt(open.crew_required)} />} />
          <Materials label={t('yard.materials')} list={open.goods} />
          <Materials label={t('yard.parts')} list={open.items} />

          {open.wrong_yard && (
            <Note tone="warning" data-testid="yard-country">
              {open.wrong_yard}
            </Note>
          )}
          {open.needs && (
            <Note tone="warning" data-testid="yard-needs">
              {open.needs}
            </Note>
          )}
          {open.unmade && (
            <Note tone="warning" data-testid="yard-unmade">
              {open.unmade}
            </Note>
          )}
          {open.famous_held && (
            <Note tone="warning" data-testid="yard-famous-held">
              {open.famous_held}
            </Note>
          )}
          {open.tier_ok === false && (
            <Note tone="warning">
              {t('yard.yardTier', { have: formatInt(tier), need: formatInt(open.yard_tier) })}
            </Note>
          )}
          {open.buildable && short !== null && (
            <Note tone="warning">{t('yard.missing', { list: short })}</Note>
          )}

          {ready && (
            /* THE NAME IS THE PLAYER'S, and it is asked for before the order is sent rather than
               invented — a ship you did not name is not yours. */
            <Field
              icon={null}
              value={name}
              maxLength={24}
              placeholder={t('yard.shipName')}
              onChange={(e) => setName(e.target.value)}
              className="mt-3"
              aria-label={t('yard.shipName')}
              data-testid="yard-name"
            />
          )}
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures}>
              {refusal.sentence}
            </Note>
          )}
        </Tray>
      )}
    </div>
  )
}

/** One material line: what she wants, against what is ashore in this city. */
function Materials({ label, list }: { label: string; list: readonly HullMaterial[] }) {
  if (list.length === 0) return null
  return (
    <>
      {list.map((m, i) => (
        <Row
          key={m.name}
          label={i === 0 ? `${label} · ${m.name}` : m.name}
          value={
            <Figure
              value={formatInt(m.qty)}
              unit={tNow('yard.inStorageN', { n: formatInt(m.have) })}
              tone={m.have < m.qty ? 'warning' : 'ink'}
            />
          }
        />
      ))}
    </>
  )
}

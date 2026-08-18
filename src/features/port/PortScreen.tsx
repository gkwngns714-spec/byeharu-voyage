import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Card,
  CardHeader,
  Meter,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  StatRow,
  TD,
  TH,
  Table,
} from '../../components/ui'
import {
  formatDucats,
  formatInt,
  formatNm,
  formatPct,
  formatTuns,
  formatVoyageDays,
} from '../../lib/format'
import { useWorld } from '../../fixtures/useWorld'
import type { PortCode } from '../../fixtures/types'
import { gcDistanceNm } from '../command/geo'
import { useCommandDraft } from '../command/commandDraft'
import { holdUsed } from '../fleets/fleetMath'
import { midPrice, rowKey } from '../market/prices'

// PORT — E.3. Where you are, what is here, and what you can do about it.
//
// THE TEACHING MOVE: every action on this screen is printed AS THE COMMAND IT WOULD ISSUE. There
// is no "Provision" button that does a thing; there is a line that reads `PROVISION Gaivota FULL`
// and loads exactly that string into the CMD input. A player who taps ten of these has read the
// grammar ten times without being taught it, and when they eventually type one themselves nothing
// behaves differently — F.4's "one grammar, two input methods", applied to a third surface.
//
// It also keeps law 2 intact: commands live on their own tab. This screen never issues anything.
//
// DARK AT V0, and labelled as such rather than faked: the Bureau (investment, H), the Inn's
// officers (C.6), nation shares and the weekly Mayor (H.3). K.1 puts all of them outside the V0
// slice, so they are named, dated and left unlit — not drawn with invented numbers.

export function PortScreen() {
  const model = useWorld()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const draftFleetId = useCommandDraft((s) => s.fleetId)
  const [portCode, setPortCode] = useState<PortCode>(model.world.currentPort)

  const port = model.portOf(portCode)
  const docked = model.fleetViews.filter((v) => v.fleet.portCode === portCode)
  const acting = docked[0] ?? model.fleetViews.find((v) => v.fleet.id === draftFleetId) ?? model.fleetViews[0]

  const command = (text: string) => {
    handOff(text, acting?.fleet.id)
    navigate('/command')
  }

  const oneLeg = [...(model.graph.edges.get(portCode)?.keys() ?? [])]
    .map((code) => ({
      port: model.portOf(code),
      nm: gcDistanceNm(port.lat, port.lon, model.portOf(code).lat, model.portOf(code).lon),
    }))
    .sort((a, b) => a.nm - b.nm)

  return (
    <Screen>
      <PageHeader
        eyebrow="Harbour"
        title={`Port · ${port.name}`}
        subtitle={`${port.country} · ${port.culture} · ${port.sea}`}
        actions={<Badge tone="neutral">draft {port.maxDraft}</Badge>}
      />

      {portCode !== model.world.currentPort && (
        <Notice tone="warning" className="text-xs">
          You are not lying in {port.name} — this is what your factors report from there. Your house
          is at {model.portOf(model.world.currentPort).name}.
        </Notice>
      )}

      <Card>
        <CardHeader eyebrow="The city" title={port.name} subtitle={`Nation: ${port.nation}`} />
        <dl className="space-y-2">
          <StatRow
            label="Development"
            value={`industry ${port.devIndustry} · commerce ${port.devCommerce} · military ${port.devMilitary}`}
          />
          <StatRow label="Market tax" value={formatPct(port.marketTaxRate, 1)} hint="set by the Mayor, banded 0–8%" />
          <StatRow
            label="You pay"
            value={formatPct(Math.max(0, port.marketTaxRate - model.world.player.taxRelief), 1)}
            hint={`reputation ${formatInt(model.world.player.reputation)} (${model.world.player.reputationLabel})`}
          />
          <StatRow label="Spread" value={formatPct(Math.max(0.02, 0.06 - 0.002 * port.devCommerce), 1)} />
          <StatRow label="Languages" value={port.languages.join(', ')} plain />
          <StatRow
            label="Specialties"
            value={port.specialties.map((c) => model.goodOf(c).name).join(' · ')}
            plain
          />
        </dl>
      </Card>

      <Card>
        <CardHeader eyebrow="Services" title="What is on this quay" />
        <dl className="space-y-2">
          <StatRow
            label="Harbour"
            value={`${port.fleetsDocked} fleets docked · max draft ${port.maxDraft}`}
            plain
          />
          <StatRow
            label="Yard"
            value={port.hasYard ? `tier ${port.yardTier} · ${port.repairRate.toFixed(1)} d./point` : 'none'}
            plain
          />
          <StatRow label="Provisions" value={`water ${port.waterPrice} d./t · food ${port.foodPrice} d./t`} plain />
          <StatRow label="Inn" value={`${formatInt(port.crewPool)} / ${formatInt(port.crewPoolMax)} hands · ${port.crewRate} d. each`} plain />
        </dl>
        <div className="mt-2">
          <Meter pct={(port.crewPool / port.crewPoolMax) * 100} tone={port.crewPool / port.crewPoolMax < 0.3 ? 'warning' : 'neutral'} />
          <p className="mt-1 font-mono text-[11px] text-ink-faint">
            Beyond the pool, hands cost 2.5x — urgent recruitment (F.2).
          </p>
        </div>
        <Notice tone="neutral" className="mt-3 text-xs">
          Bureau (investment), officers at the Inn, the weekly Mayor and nation shares are V1 (K.1).
          They are not drawn here because there is nothing behind them yet.
        </Notice>
      </Card>

      <Card>
        <CardHeader
          eyebrow="Your ships"
          title={docked.length === 0 ? 'Nothing of yours alongside' : 'Alongside'}
          subtitle={docked.length === 0 ? undefined : 'Every hull you have in this harbour.'}
        />
        {docked.length === 0 ? (
          <p className="text-sm text-ink-muted">
            You have no fleet in {port.name}.{' '}
            {model.fleetViews
              .filter((v) => v.fleet.status === 'SAILING')
              .map((v) => `${v.fleet.name} is at sea.`)
              .join(' ')}
          </p>
        ) : (
          <Table>
            <thead>
              <tr>
                <TH>Ship</TH>
                <TH>Fleet</TH>
                <TH align="num">Hull</TH>
                <TH align="num">Crew</TH>
                <TH align="num">Hold</TH>
              </tr>
            </thead>
            <tbody>
              {docked.flatMap((view) =>
                view.ships.map((ship) => {
                  const cls = model.classOf(ship)
                  return (
                    <tr key={ship.id}>
                      <TD>
                        {ship.name}
                        {ship.isFlagship && <span className="ml-1 text-accent">⚑</span>}
                        <span className="ml-2 text-xs text-ink-faint">{cls.name}</span>
                      </TD>
                      <TD>{view.fleet.name}</TD>
                      <TD align="num">{formatPct(ship.durability / cls.maxDurability)}</TD>
                      <TD align="num">
                        {formatInt(ship.crew)}/{formatInt(cls.crewMax)}
                      </TD>
                      <TD align="num">
                        {formatTuns(holdUsed(ship), 1)} / {formatTuns(cls.hold)}
                      </TD>
                    </tr>
                  )
                }),
              )}
            </tbody>
          </Table>
        )}
      </Card>

      {/* ── ACTIONS, WRITTEN AS COMMANDS ─────────────────────────────────────────────────── */}
      <Card tone="accent">
        <CardHeader
          eyebrow="Actionable here"
          title="What you can do in this harbour"
          subtitle={
            acting
              ? `Each of these loads onto Command as ${acting.fleet.name}'s order. Nothing is issued here.`
              : 'Nothing is issued here.'
          }
        />
        {acting && (
          <div className="space-y-4">
            <ActionGroup
              label="Stores and hands"
              actions={[
                {
                  command: `PROVISION ${acting.fleet.name} FULL`,
                  note: `now ${formatVoyageDays(acting.enduranceDays)} · water ${port.waterPrice} d./t, food ${port.foodPrice} d./t`,
                },
                {
                  command: `HIRE ${Math.max(1, Math.min(port.crewPool, acting.crewMax - acting.crew))} CREW FOR ${acting.fleet.name}`,
                  note: `${formatInt(acting.crew)} of ${formatInt(acting.crewMax)} berths filled · ${formatDucats(port.crewRate)} each`,
                },
                ...(port.hasYard
                  ? [
                      {
                        command: `REPAIR ${acting.fleet.name} TO 100`,
                        note: `worst hull ${formatPct(acting.worstHullFraction)} · tier ${port.yardTier} yard`,
                      },
                    ]
                  : []),
              ]}
              onPick={command}
            />

            <ActionGroup
              label="Trade the specialties"
              actions={port.specialties.map((code) => {
                const good = model.goodOf(code)
                const row = model.priceIndex.rows.get(rowKey(portCode, code))
                const mid = row ? midPrice(good, port, row) : null
                return {
                  command: `BUY ${good.name} ${Math.max(10, Math.floor(acting.holdFree))}`,
                  note: mid === null ? 'not traded here' : `about ${formatInt(mid)} d./t · ${formatTuns(acting.holdFree, 0)} free`,
                }
              })}
              onPick={command}
            />

            <ActionGroup
              label="One leg from here"
              actions={oneLeg.slice(0, 6).map(({ port: p, nm }) => ({
                command: `SAIL ${acting.fleet.name} TO ${p.name}`,
                note: `${formatNm(nm)} · ${p.maxDraft < acting.maxDraft ? 'too shallow for this fleet' : 'draft ' + p.maxDraft}`,
              }))}
              onPick={command}
            />
          </div>
        )}
      </Card>

      <Card>
        <CardHeader eyebrow="Elsewhere" title="Other ports" subtitle="Read a harbour before you sail to it." />
        <div className="flex flex-wrap gap-1.5">
          {model.world.ports.map((p) => (
            <button
              key={p.code}
              type="button"
              onClick={() => setPortCode(p.code)}
              className={[
                'min-h-11 rounded-md px-3 font-mono text-xs transition',
                p.code === portCode
                  ? 'bg-accent text-app'
                  : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
              ].join(' ')}
            >
              {p.name}
            </button>
          ))}
        </div>
      </Card>
    </Screen>
  )
}

function ActionGroup({
  label,
  actions,
  onPick,
}: {
  label: string
  actions: readonly { command: string; note?: string }[]
  onPick: (command: string) => void
}) {
  if (actions.length === 0) return null
  return (
    <div>
      <SectionLabel>{label}</SectionLabel>
      <ul className="space-y-1">
        {actions.map((a) => (
          <li key={a.command}>
            <button
              type="button"
              onClick={() => onPick(a.command)}
              className="min-h-11 w-full rounded-md border border-edge bg-surface px-3 py-2 text-left transition hover:border-accent/60"
            >
              <code className="block break-words font-mono text-xs text-accent">{a.command}</code>
              {a.note && <span className="mt-0.5 block font-mono text-[11px] text-ink-faint">{a.note}</span>}
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}

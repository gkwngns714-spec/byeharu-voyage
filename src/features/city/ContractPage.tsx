import { useMemo, useState } from 'react'
import { Button, DetailPage, Field, Figure, NeedChip, Note, Row, Skeleton, SummaryRow, goodIcon } from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt } from '../../lib/format'
import { properName, useT, type TKey } from '../../lib/i18n'
import type { CourierContract, SnapshotPort, StoredGood } from '../../lib/rpc'
import { fold, foldedMatch } from '../../lib/text'
import { PortFlag } from '../../live/PortFlag'
import { cancelContract, failContract, litContracts, postContract, useContractEdits, useCourierContracts } from '../../live/useCourierContracts'
import { useStorage } from '../../live/useStorage'
import { portNameOf, useWorld } from '../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// POST A CONTRACT (0483, docs/design/roadmap-2026-11-23.md slice 14: "the 'Place a request' verb that nobody used becomes 'Post a contract'").
// Lit (contracts_enabled), the Requests face's door. Three steps on one page, each a list of marks: a good in her shed here → the harbour
// it goes to → units, reward, collateral, hours → Post. The server is the gate (cmd.post_contract: her goods here, the harbour's shed, the
// purse, the hours); a refusal stands under Post in its own words. Taking and delivering are HQ's board cards; HER CONTRACTS (posted and
// carried) stand under the Requests face, each with its one press (take down an open post; give up a carried one).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** How many harbours the "Send to" list shows before a search narrows it. */
const HARBOURS_SHOWN = 40

export function ContractPostPage({ port, onClose }: { port: SnapshotPort; onClose: () => void }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const shed = useStorage(port.id, null)
  const refusal = useContractEdits((s) => s.refused.post ?? null)
  const pending = useContractEdits((s) => s.pending === 'post')
  const [good, setGood] = useState<StoredGood | null>(null)
  const [to, setTo] = useState<SnapshotPort | null>(null)
  const [q, setQ] = useState('')
  const [qty, setQty] = useState('')
  const [reward, setReward] = useState('')
  const [collateral, setCollateral] = useState('')
  const [hours, setHours] = useState('6')
  const goodName = (code: string) => properName('good', code, goodByCode[code]?.name ?? code)

  const harbours = useMemo(() => {
    const f = fold(q.trim())
    return Object.values(portByCode)
      .filter((p) => p.kind === 'HARBOUR' && p.code !== port.code && foldedMatch(f, p.name, p.code, p.country))
      .sort((a, b) => a.name.localeCompare(b.name))
      .slice(0, HARBOURS_SHOWN)
  }, [portByCode, port.code, q])

  const n = (v: string) => (v.trim() === '' ? NaN : Number(v))
  const ready = good !== null && to !== null && n(qty) > 0 && n(reward) > 0 && n(collateral) >= 0 && n(hours) > 0
  const post = () => {
    if (!ready || !good || !to || pending) return
    const id = goodByCode[good.good]?.id
    if (!id) return
    void postContract({ from: port.id, to: to.id, good: id, qty: n(qty), reward: n(reward), collateral: n(collateral), hours: n(hours) }).then((ok) => {
      if (ok) onClose()
    })
  }

  return (
    <DetailPage title={t('city.contractPost')} onClose={onClose} data-testid="city-contract-page">
      <div className="mx-auto w-full max-w-2xl">
        {good === null ? (
          shed.view === null ? (
            <Skeleton className="h-20 w-full" />
          ) : shed.view.stored.length === 0 ? (
            <Note tone="neutral">{t('city.contractNothing')}</Note>
          ) : (
            <div data-testid="city-contract-goods">
              {shed.view.stored.map((g) => (
                <SummaryRow
                  key={g.good}
                  icon={goodIcon(g.good, goodByCode[g.good]?.category ?? '')}
                  title={goodName(g.good)}
                  figure={formatInt(g.qty)}
                  onClick={() => {
                    setGood(g)
                    setQty(String(g.qty))
                  }}
                  data-testid={`city-contract-good-${g.good}`}
                />
              ))}
            </div>
          )
        ) : to === null ? (
          <div data-testid="city-contract-harbours">
            <Field
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onClear={() => setQ('')}
              aria-label={t('city.contractTo')}
              placeholder={t('city.contractTo')}
              spellCheck={false}
              autoCorrect="off"
            />
            {harbours.map((p) => (
              <SummaryRow key={p.code} icon="anchor" title={p.name} figure={<PortFlag code={p.code} />} onClick={() => setTo(p)} data-testid={`city-contract-to-${p.code}`} />
            ))}
            <Row label={t('common.back')} chevron onClick={() => setGood(null)} hairline={false} />
          </div>
        ) : (
          <div className="flex flex-col gap-2" data-testid="city-contract-terms">
            <span className="flex flex-wrap gap-1.5">
              <NeedChip icon={goodIcon(good.good, goodByCode[good.good]?.category ?? '')} label={goodName(good.good)}>
                {formatInt(good.qty)}
              </NeedChip>
              <NeedChip icon="anchor" label={to.name}>
                <span className="inline-flex items-center gap-1">
                  <PortFlag code={to.code} />
                  {to.name}
                </span>
              </NeedChip>
            </span>
            <div className="grid grid-cols-2 gap-2">
              {(
                [
                  ['contractUnits', qty, setQty],
                  ['contractReward', reward, setReward],
                  ['contractCollateral', collateral, setCollateral],
                  ['contractHours', hours, setHours],
                ] as const
              ).map(([word, value, set]) => (
                <Field
                  key={word}
                  value={value}
                  onChange={(e) => set(e.target.value)}
                  onClear={() => set('')}
                  aria-label={t(`city.${word}`)}
                  placeholder={t(`city.${word}`)}
                  inputMode="numeric"
                  spellCheck={false}
                  data-testid={`city-contract-${word}`}
                />
              ))}
            </div>
            {refusal && (
              <Note tone="danger" code={refusal.code} figures={refusal.figures}>
                {refusal.sentence}
              </Note>
            )}
            <Button onClick={post} disabled={!ready || pending} data-testid="city-contract-send">
              {t('city.contractSend')}
            </Button>
            <Row label={t('common.back')} chevron onClick={() => setTo(null)} hairline={false} />
          </div>
        )}
      </div>
    </DetailPage>
  )
}

const STATUS_WORD: Record<CourierContract['status'], TKey> = {
  open: 'city.contract_open',
  taken: 'city.contract_taken',
  delivered: 'city.contract_delivered',
  failed: 'city.contract_failed',
  lapsed: 'city.contract_lapsed',
  cancelled: 'city.contract_cancelled',
}

/** Her contracts, posted and carried, the live first: each one line (good, units, the harbour), its reward, its state and its one press. */
export function ContractRows() {
  const t = useT()
  const view = litContracts(useCourierContracts().view)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const pending = useContractEdits((s) => s.pending)
  const refused = useContractEdits((s) => s.refused)
  if (!view) return null
  const rows: { c: CourierContract; mine: 'posted' | 'carried' }[] = [
    ...view.posted.map((c) => ({ c, mine: 'posted' as const })),
    ...view.carried.map((c) => ({ c, mine: 'carried' as const })),
  ]
  if (rows.length === 0) return null
  return (
    <div className="mt-4" data-testid="city-contracts">
      <div className="text-t-caption text-ink-faint">{t('city.contractsHeading')}</div>
      {rows.map(({ c, mine }) => {
        const act = mine === 'posted' && c.status === 'open' ? 'cancel' : mine === 'carried' && c.status === 'taken' ? 'fail' : null
        const r = refused[c.id] ?? null
        return (
          <div key={`${mine}:${c.id}`} className="py-1" data-testid={`city-contract-${c.id}`} data-status={c.status} data-mine={mine}>
            <Row
              label={
                <span className="inline-flex items-center gap-1">
                  <PortFlag code={c.to} />
                  {t('city.contractRoute', { good: properName('good', c.good, goodByCode[c.good]?.name ?? c.good), n: formatInt(c.qty), port: portNameOf(portByCode, c.to) })}
                </span>
              }
              value={<Figure value={mine === 'carried' ? formatDucatsDelta(c.reward) : formatDucats(c.reward)} tone={c.status === 'failed' ? 'danger' : 'ink'} />}
            />
            <div className="flex min-h-11 flex-wrap items-center gap-x-2">
              <NeedChip icon="pact" tone={c.status === 'failed' ? 'danger' : c.status === 'delivered' ? 'success' : 'muted'} label={t(STATUS_WORD[c.status])}>
                {t(STATUS_WORD[c.status])}
              </NeedChip>
              {c.collateral > 0 && (
                <NeedChip icon="shield" label={t('hq.collateral', { n: formatDucats(c.collateral) })}>
                  {formatDucats(c.collateral)}
                </NeedChip>
              )}
              {act && (
                <Button
                  className="ml-auto"
                  onClick={() => void (act === 'cancel' ? cancelContract(c.id) : failContract(c.id))}
                  disabled={pending === c.id}
                  data-testid={`city-contract-${act}`}
                >
                  {t(act === 'cancel' ? 'city.contractCancel' : 'city.contractGiveUp')}
                </Button>
              )}
            </div>
            {r && (
              <Note tone="danger" code={r.code}>
                {r.sentence}
              </Note>
            )}
          </div>
        )
      })}
    </div>
  )
}

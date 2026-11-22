import { Card, Figure, Hint, ListPanel, PageSplit, Row, Skeleton } from '../../components/ui'
import { GoToLink } from '../../chart'
import { formatInt } from '../../lib/format'
import type { BountyRow, PirateBounties } from '../../lib/rpc'
import { properName, useLocale, useT } from '../../lib/i18n'
import { bountyName } from '../../live/bountyWords'
import { portNameOf, useWorld } from '../../live/worldStore'

// RANK → BOUNTIES (0471, docs/design/playable-2026-11-22.md P2): the named pirates still free, each with the bounty on her now, the sea
// she hunts (or "At home"), the harbour that posts it, how many ships she has taken and a link that rings her on the map; beside them,
// the last bounties collected and the rule in one line. ONE read, `world.pirate_bounties()`, asked by RankScreen (it decides whether
// this face exists: dark, the server answers {on: false} and the face is not offered). Every figure is served; nothing is summed here.

export function BountyBoard({ read }: { read: PirateBounties | null }) {
  const t = useT()
  const locale = useLocale()
  const portByCode = useWorld((s) => s.portByCode)

  if (!read || !read.on || !read.bounties) {
    return (
      <ListPanel look="card" title={t('bounty.wanted')} data-testid="rank-bounties">
        <div className="space-y-2 py-1">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      </ListPanel>
    )
  }

  const port = (code: string | null) => {
    if (code === null) return ''
    const served = portNameOf(portByCode, code)
    return properName('port', served, served, locale)
  }
  const where = (b: BountyRow) =>
    b.laid_up ? t('bounty.laidUp') : b.sea !== null ? `${t('bounty.hunts')} ${properName('sea', b.sea, b.sea, locale)}` : t('bounty.atHome')

  const row = (b: BountyRow) => (
    <Row
      key={b.fleet}
      label={<GoToLink to={{ kind: 'fleet', id: b.fleet }}>{bountyName(locale, b, portByCode)}</GoToLink>}
      value={<Figure value={formatInt(b.value)} tone="accent" />}
      hairline={false}
      data-testid="bounty-row"
    >
      <span className="block text-t-caption text-ink-faint">
        {[where(b), t('bounty.taken', { n: b.taken }), b.poster ? `${t('bounty.poster')} ${port(b.poster)}` : null].filter(Boolean).join(' · ')}
      </span>
    </Row>
  )

  const rates = read.rates
  return (
    <PageSplit
      data-testid="rank-bounties-page"
      stickySide
      main={
        <ListPanel
          look="card"
          columns="fit"
          title={t('bounty.wanted')}
          count={formatInt(read.bounties.length)}
          // the rule speaks of "her": only under a pirate it can mean (2026-11-22 second play-test: it stood under "No bounties posted.")
          footer={read.bounties.length > 0 ? <Hint>{t('bounty.rule')}</Hint> : undefined}
          data-testid="rank-bounties"
        >
          {read.bounties.length === 0 && <Row label={t('bounty.none')} tone="muted" hairline={false} />}
          {read.bounties.map(row)}
        </ListPanel>
      }
      side={
        <Card title={t('bounty.claims')} data-testid="rank-bounty-claims">
          {(read.claims ?? []).length === 0 ? (
            <Row label={t('bounty.noClaims')} tone="muted" hairline={false} />
          ) : (
            (read.claims ?? []).map((c) => (
              <Row
                key={`${c.at}-${c.given}`}
                label={bountyName(locale, c, portByCode)}
                tone={c.is_you ? 'accent' : 'default'}
                hairline={false}
                data-testid="bounty-claim"
              >
                <span className="block text-t-caption text-ink-faint">{t('bounty.claimedBy', { house: c.house ?? '—', n: formatInt(c.paid) })}</span>
              </Row>
            ))
          )}
          {rates && (
            <p className="mt-3 text-t-caption text-ink-faint" data-testid="bounty-rates">
              {t('bounty.rates', { base: formatInt(rates.base), hour: formatInt(rates.per_hour), ship: formatInt(rates.per_ship), cap: formatInt(rates.cap) })}
            </p>
          )}
        </Card>
      }
    />
  )
}

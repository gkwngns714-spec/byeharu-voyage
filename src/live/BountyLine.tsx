import { formatInt } from '../lib/format'
import { useLocale, useT } from '../lib/i18n'
import { bountyName } from './bountyWords'
import { bountyOfBattle } from './bountyPaid'
import { useWorld } from './worldStore'

// "BOUNTY CLAIMED +17,000" (0471) under a finished fight: the bounty this battle paid, read off its BATTLE_REPORT in the ledger the world
// store already holds (./bountyPaid.ts). Nothing when the battle paid none, which is every battle while the bounties are dark.
export function BountyLine({ battleId, className = '' }: { battleId: string | null | undefined; className?: string }) {
  const t = useT()
  const locale = useLocale()
  const events = useWorld((s) => s.events)
  const portByCode = useWorld((s) => s.portByCode)
  const b = bountyOfBattle(events, battleId)
  if (!b) return null
  return (
    <p className={`text-t-body font-semibold text-accent ${className}`} data-testid="bounty-claimed" data-paid={b.paid}>
      {t('bounty.claimed', { n: formatInt(b.paid) })}
      <span className="block text-t-caption font-normal text-ink-faint">{bountyName(locale, b, portByCode)}</span>
    </p>
  )
}

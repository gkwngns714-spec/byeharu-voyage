import type { ReactNode } from 'react'
import { Button } from '../../components/ui'
import { useT } from '../../lib/i18n'

// PLACEHOLDER (battle-map branch): the real battle screen (docs/design/tick-combat.md section 11) is another builder's
// PR on `tick-combat`, with this exact path and signature. This stand-in only lets the map open it from the red circle
// and carry the Join bar in `actions`; the battle-screen PR replaces this whole file.
export function BattleScreen({ battleId, onClose, actions }: { battleId: string; onClose: () => void; actions?: ReactNode }) {
  const t = useT()
  return (
    <div
      role="dialog"
      aria-label={t('fight.battle')}
      data-testid="battle-screen"
      data-battle={battleId}
      className="fixed inset-0 z-50 flex flex-col gap-3 overflow-y-auto bg-bg p-4 md:inset-x-4 md:top-4 md:bottom-auto md:rounded-control"
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-t-title text-ink">{t('fight.battle')}</span>
        <Button onClick={onClose} data-testid="battle-screen-close">
          {t('common.close')}
        </Button>
      </div>
      {actions}
    </div>
  )
}

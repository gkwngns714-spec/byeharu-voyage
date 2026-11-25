import { useState } from 'react'
import { useT, type TKey } from '../../../lib/i18n'
import { formatInt } from '../../../lib/format'
import type { FleetJobParams, JobRoom } from '../../../lib/rpc'
import { FoldPress, SettingBox } from './assignParts'
import { SETTINGS, type JobSettingsDraft } from './settingsDraft'

// A FIXED JOB'S SETTINGS (0516, the owner's PASSIVE METHOD): what the Assign sheet sends with a run. An empty box sends nothing. The
// server judges every number (public.job_settings_param) and its refusal stands in the sheet's foot; nothing is worked out here.

const WORDS: Record<(typeof SETTINGS)[number]['code'], TKey> = {
  under: 'corp.buyUnder',
  over: 'corp.sellOver',
  crew: 'corp.crew',
  days: 'corp.days',
  stop_profit: 'corp.minProfit',
  stop_damage: 'corp.maxDamage',
} satisfies Partial<Record<keyof FleetJobParams, TKey>>

export function JobSettings({ draft, room, onChange, sells }: { draft: JobSettingsDraft; room: JobRoom; onChange: (d: JobSettingsDraft) => void; sells: boolean }) {
  const t = useT()
  const [open, setOpen] = useState(() => Object.keys(draft).length > 0)
  return (
    <div className="mb-4">
      <FoldPress open={open} onToggle={() => setOpen(!open)} testid="corp-settings-open">
        {t('corp.settings')}
      </FoldPress>
      {open && (
        <div className="grid grid-cols-2 gap-2" data-testid="corp-settings">
          {SETTINGS.filter((s) => sells || !s.sale).map((s) => (
            <SettingBox
              key={s.code}
              word={
                <>
                  {t(WORDS[s.code])}
                  {s.code === 'crew' && <span className="ml-1 tabular-nums text-ink-faint">{`${formatInt(room.crew_min)}–${formatInt(room.crew_max)}`}</span>}
                </>
              }
              value={draft[s.code] ?? ''}
              onChange={(v) => onChange({ ...draft, [s.code]: v })}
              mode="decimal"
              testid={`corp-setting-${s.code}`}
            />
          ))}
          <p className="col-span-2 text-t-caption tabular-nums text-ink-muted" data-testid="corp-settings-left" data-left={room.left}>
            {t('corp.spaceLeft')} {formatInt(room.left)} / {formatInt(room.hold)}
          </p>
        </div>
      )}
    </div>
  )
}

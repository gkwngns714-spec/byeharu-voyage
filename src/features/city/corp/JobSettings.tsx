import { useState } from 'react'
import { useT, type TKey } from '../../../lib/i18n'
import { formatInt } from '../../../lib/format'
import type { FleetJobParams, JobRoom } from '../../../lib/rpc'
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
      <button type="button" aria-expanded={open} onClick={() => setOpen(!open)} className="flex min-h-11 w-full items-center text-left text-t-caption text-ink-muted" data-testid="corp-settings-open">
        {t('corp.settings')}
      </button>
      {open && (
        <div className="grid grid-cols-2 gap-2" data-testid="corp-settings">
          {SETTINGS.filter((s) => sells || !s.sale).map((s) => (
            <label key={s.code} className="flex min-w-0 flex-col gap-1 text-t-caption text-ink-muted">
              <span>
                {t(WORDS[s.code])}
                {s.code === 'crew' && <span className="ml-1 tabular-nums text-ink-faint">{`${formatInt(room.crew_min)}–${formatInt(room.crew_max)}`}</span>}
              </span>
              <input
                inputMode="decimal"
                autoComplete="off"
                value={draft[s.code] ?? ''}
                onChange={(e) => onChange({ ...draft, [s.code]: e.target.value })}
                className="min-h-11 w-full min-w-0 rounded-control bg-surface px-3 text-base tabular-nums text-ink ring-1 ring-inset ring-edge focus:ring-accent"
                data-testid={`corp-setting-${s.code}`}
              />
            </label>
          ))}
          <p className="col-span-2 text-t-caption tabular-nums text-ink-muted" data-testid="corp-settings-left" data-left={room.left}>
            {t('corp.spaceLeft')} {formatInt(room.left)} / {formatInt(room.hold)}
          </p>
        </div>
      )}
    </div>
  )
}

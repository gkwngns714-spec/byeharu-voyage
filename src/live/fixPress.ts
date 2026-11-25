import { openHq, useHqPlace } from '../app/hqPlace'
import type { WorkerFix } from '../domain/fleet'
import { formatDucats } from '../lib/format'
import { useT } from '../lib/i18n'

// THE WORDS AND THE UNPAID PRESSES OF A FIX (0499; live/FixButton.tsx draws the button, features/city/corp/WorkerFix.tsx the worker
// row). Which fix a code has is domain/fleet `fixOf`'s; nothing here reads a code.

/** The fixes that are paid for where she lies, each quoted by its building. */
export type PaidFix = 'repair' | 'hire'
export const isPaidFix = (fix: WorkerFix | null): fix is PaidFix => fix === 'repair' || fix === 'hire'

/** The press's word: "Repair 736", "Hire crew 100", "Assign", "Storage". */
export function useFixWord(): (fix: WorkerFix, cost?: number | null) => string {
  const t = useT()
  return (fix, cost) =>
    fix === 'repair'
      ? cost != null
        ? t('corp.repairFor', { n: formatDucats(cost) })
        : t('corp.repair')
      : fix === 'hire'
        ? cost != null
          ? t('corp.hireFor', { n: formatDucats(cost) })
          : t('corp.hire')
        : fix === 'assign'
          ? t('corp.assign')
          : t('corp.warehouse')
}

/** Assign and Storage: one press each, no read. */
export function fixPressOf(fix: Exclude<WorkerFix, PaidFix>, worker: string): () => void {
  return fix === 'assign' ? () => openHq({ sheet: 'assign', worker }) : () => useHqPlace.getState().openStorage()
}

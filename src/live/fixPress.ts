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
          : fix === 'wreck'
            ? t('corp.tow')
            : t('corp.warehouse')
}

/** A wreck's press, in words (0497; live/WreckFix.tsx names the step): "Sell cargo", "Tow 14,366", "Tow"; and the line that says
 *  where the tow goes, "Tow to Colombo". */
export function useWreckWord(): (step: { kind: 'tow' | 'sell'; fee: number | null; to: string | null }) => { pill: string; note: string | undefined } {
  const t = useT()
  return (step) =>
    step.kind === 'sell'
      ? { pill: t('corp.sellCargo'), note: undefined }
      : { pill: step.fee !== null ? t('corp.towFor', { n: formatDucats(step.fee) }) : t('corp.tow'), note: step.to ? t('corp.towTo', { port: step.to }) : undefined }
}

/** Assign and Storage: one press each, no read. */
export function fixPressOf(fix: Exclude<WorkerFix, PaidFix | 'wreck'>, worker: string): () => void {
  return fix === 'assign' ? () => openHq({ sheet: 'assign', worker }) : () => useHqPlace.getState().openStorage()
}

// WHAT MENDS A REFUSAL (0499 `fit-to-sail`): the one press a server code has. Her worker row, her sheet, While away and her queue's
// note read this table; a code is never printed. Whether a refusal is still news is derive.ts `fleetNewRefusal`.

/** The one press that mends a code: the yard's repair, the Inn's hire, a new assignment, Storage. */
export type WorkerFix = 'repair' | 'hire' | 'assign' | 'storage'

export function fixOf(code: string | null | undefined): WorkerFix | null {
  return code === 'E_FLAGSHIP_DISABLED' ? 'repair' : code === 'E_CREW_SHORT' ? 'hire' : code === 'E_LEG_TOO_FAR' ? 'assign' : code === 'E_SHED_FULL' ? 'storage' : null
}

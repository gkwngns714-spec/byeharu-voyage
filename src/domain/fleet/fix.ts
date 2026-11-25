// WHAT MENDS A REFUSAL (0499 `fit-to-sail`): the one press a server code has. Her worker row, her sheet, While away and her queue's
// note read this table; a code is never printed. Whether a refusal is still news is derive.ts `fleetNewRefusal`.

/** The one press that mends a code: the yard's repair, the Inn's hire, a new assignment, Storage. And, by her served state where no
 *  code says it (`wreckFix`): `wreck`, a fleet that cannot sail and lies in a port: her next press is the server's to name
 *  (live/WreckFix.tsx: Sell cargo, then Tow). */
export type WorkerFix = 'repair' | 'hire' | 'assign' | 'storage' | 'wreck'

export function fixOf(code: string | null | undefined): WorkerFix | null {
  return code === 'E_FLAGSHIP_DISABLED' || code === 'E_STOP_DAMAGE' ? 'repair' : code === 'E_CREW_SHORT' ? 'hire' : code === 'E_LEG_TOO_FAR' ? 'assign' : code === 'E_SHED_FULL' ? 'storage' : null
}

/** THE PRESS A FLEET'S OWN SERVED STATE ASKS FOR, where no job's code names one (0497; the owner's fleet lay wrecked at Diego Garcia
 *  with nothing to press): `wreck` while her status is UNABLE_TO_SAIL, she lies in a port and has a ship (an empty fleet is no
 *  wreck, 0321); `repair` once a tow has laid her DOCKED with a flagship that has no hull. Null for every other fleet. A reading of
 *  the served status and hulls: whether she may sell, be towed or be repaired stays the server's (each press is its own dry run). */
export function wreckFix(fleet: { status: string; port?: string | null; ships: readonly { is_flagship: boolean; durability: number }[] } | null): WorkerFix | null {
  if (!fleet || fleet.ships.length === 0) return null
  if (fleet.status === 'UNABLE_TO_SAIL') return fleet.port ? 'wreck' : null
  if (fleet.status === 'DOCKED' && !fleet.ships.some((s) => s.is_flagship && s.durability > 0)) return 'repair'
  return null
}

/** THE HARBOUR WHERE HER CARGO CAN BE LANDED NOW, or null: the port she lies docked in; or (0497) the port a fleet that cannot sail
 *  lies in, while she has a ship: her hulls are wrecked, her cargo is not, and the server sells and stores it there
 *  (public.fleet_alongside). The sell face reads "is she HERE" from this, so a wreck's coral is sold where she lies, not offered as
 *  a voyage she cannot make. Whether the order runs is the server's (0497 dark: it does not, and HQ does not draw the press). */
export function cargoPort(fleet: { status: string; port: string | null; ships: readonly unknown[] }): string | null {
  if (fleet.status === 'DOCKED') return fleet.port
  return fleet.status === 'UNABLE_TO_SAIL' && fleet.ships.length > 0 ? fleet.port : null
}

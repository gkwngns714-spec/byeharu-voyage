import { useState } from 'react'
import { Button, Figure, Icon, Note } from '../components/ui'
import { fleetCrew, whereabouts } from '../domain/fleet'
import { formatInt } from '../lib/format'
import { useT } from '../lib/i18n'
import type { FleetView, Refusal } from '../lib/rpc'
import { useWorld } from './worldStore'

// THE RED CREW LINE'S NEXT STEP (2026-11-23, the roadmap's slice 6; play-test 3 finding 26: "Crew 8/38" stood red with no word of
// what to do). Under a crew line that is short of hands: the crew glyph, the hands she lacks, and ONE press that hires them.
//
//   · SHORT is `fleetCrew(fleet).short` (domain/fleet): the hands under each ship's served `crew_required`, the same figure the
//     yard's "Hire crew · 8" press counts. Nothing else is added up here.
//   · IN A HARBOUR the press sends `HIRE n` through the store's one `issue` door (the line the Inn's stepper sends for the same
//     count); the server prices it, judges the harbour's crew pool and the purse, and a refusal is printed in its words. The world is
//     read back, the fleet is no longer short, and the line goes.
//   · AT SEA there is nothing to press: the line says "Hire in port".
// Not the Inn's stepper (tests/verbHomes.spec.ts keeps StepQuestion / useStepOrder to the Inn, the Shipyard and the quay): this is a
// fixed line with nothing to choose, as the yard's BUILD and the workstation's MAKE are.
export function CrewHint({ fleet, className = '' }: { fleet: FleetView; className?: string }) {
  const t = useT()
  const issue = useWorld((s) => s.issue)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const short = fleetCrew(fleet).short
  if (short <= 0) return null
  const docked = whereabouts(fleet).kind === 'docked'
  const hire = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const okay = await issue(fleet.id, `HIRE ${short}`, null)
      setBusy(false)
      if (!okay) setRefusal(useWorld.getState().refusal)
    })()
  }
  return (
    <div className={className} data-testid="crew-hint" data-short={short}>
      <div className="flex items-center gap-3 py-2">
        <span className="inline-flex items-center gap-1 text-danger">
          <Icon name="crew" size={18} />
          <Figure value={`−${formatInt(short)}`} tone="danger" />
        </span>
        {docked ? (
          <Button variant="tonal" size="sm" className="ml-auto" busy={busy} onClick={hire} data-testid="crew-hint-hire">
            {t('yard.hireCrewN', { n: formatInt(short) })}
          </Button>
        ) : (
          <span className="ml-auto text-t-caption text-ink-muted" data-testid="crew-hint-port">
            {t('fleets.hireInPort')}
          </span>
        )}
      </div>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="crew-hint-refusal">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}

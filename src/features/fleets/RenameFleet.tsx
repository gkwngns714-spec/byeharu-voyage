import { useState } from 'react'
import { Button, DetailPage, Field, Note } from '../../components/ui'
import { cmdRenameFleet } from '../../lib/rpc'
import type { FleetView, Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { useT } from '../../lib/i18n'

// A FLEET TAKES A NEW NAME (0354). The server judges the name (`cmd.rename_fleet`: 3 to 24 letters, not one she already uses) and this prints its answer. It works whatever
// the fleet is doing, and whether fleet room is lit or not. The field stands on a pop-up page, so the press moves nothing on the page behind it (the owner's press law).

export function RenameFleet({ fleet, className = '' }: { fleet: Pick<FleetView, 'id' | 'name'>; className?: string }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  return (
    <>
      <Button variant="secondary" className={className} onClick={() => setOpen(true)} data-testid="fleet-rename">
        {t('fleets.rename')}
      </Button>
      {open && <RenamePage fleet={fleet} onClose={() => setOpen(false)} />}
    </>
  )
}

function RenamePage({ fleet, onClose }: { fleet: Pick<FleetView, 'id' | 'name'>; onClose: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const [name, setName] = useState(fleet.name)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const save = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdRenameFleet(fleet.id, name.trim())
      setBusy(false)
      if (r.ok) {
        await refresh()
        onClose()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  return (
    <DetailPage title={t('fleets.renameTo', { name: fleet.name })} onClose={onClose} data-testid="fleet-rename-page">
      <Field
        icon={null}
        value={name}
        maxLength={24}
        placeholder={t('fleets.moveNewName')}
        onChange={(e) => setName(e.target.value)}
        aria-label={t('fleets.moveNewName')}
        data-testid="fleet-rename-name"
      />
      <Button className="mt-3 w-full" busy={busy} disabled={name.trim().length < 3 || name.trim() === fleet.name} onClick={save} data-testid="fleet-rename-save">
        {t('fleets.renameSave')}
      </Button>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </DetailPage>
  )
}

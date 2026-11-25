import { useState } from 'react'
import { Button, DetailPage, Field, Hint, Note } from '../../components/ui'
import { cmdRenameCompany } from '../../lib/rpc'
import type { Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { useT } from '../../lib/i18n'
import { COMPANY_NAME_MAX, companyNameToSend } from '../found/companyName'

// A COMPANY TAKES A NEW NAME (0503; the owner's specification, 2026-11-25: "you can change your name again for free (1st time), but
// later ... you will have to pay (real money currency - not decided yet)"). The server judges the name (`cmd.rename_company`, the one
// rule a founding is judged by) and this prints its answer. `free` is the server's (`world.player().rename_free`): while it is true
// the press says so; once it is used the page says, in plain words, that another rename is not available yet, and offers no field.
// Nothing here knows a price: there is none. The field stands on a pop-up page, so the press moves nothing on the page behind it.

export function RenameCompany({ name, free, className = '' }: { name: string; free: boolean; className?: string }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  return (
    <>
      <Button variant="secondary" className={className} onClick={() => setOpen(true)} data-testid="company-rename">
        {t(free ? 'profile.renameFree' : 'profile.rename')}
      </Button>
      {open && <RenamePage name={name} free={free} onClose={() => setOpen(false)} />}
    </>
  )
}

function RenamePage({ name: current, free, onClose }: { name: string; free: boolean; onClose: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const [name, setName] = useState(current)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const toSend = companyNameToSend(name)

  const save = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdRenameCompany(toSend)
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
    <DetailPage title={t('profile.renameTitle')} onClose={onClose} data-testid="company-rename-page">
      {free ? (
        <>
          <Field
            icon={null}
            value={name}
            maxLength={COMPANY_NAME_MAX}
            placeholder={t('found.nameQ')}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && toSend.length >= 3 && toSend !== current) save()
            }}
            aria-label={t('found.nameQ')}
            autoComplete="off"
            data-testid="company-rename-name"
          />
          <Hint className="mt-2">{t('found.nameRule')}</Hint>
          <Hint className="mt-1">{t('profile.renameOnce')}</Hint>
          <Button className="mt-3 w-full" busy={busy} disabled={toSend.length < 3 || toSend === current} onClick={save} data-testid="company-rename-save">
            {t('profile.renameSave')}
          </Button>
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-3">
              {refusal.sentence}
            </Note>
          )}
        </>
      ) : (
        <p className="text-t-body text-ink" data-testid="company-rename-used">
          {t('profile.renameUsed')}
        </p>
      )}
    </DetailPage>
  )
}

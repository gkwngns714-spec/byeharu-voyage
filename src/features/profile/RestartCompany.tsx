import { useState } from 'react'
import { Button, Card, DetailPage, Field, Hint, Note, TileChoice, TileGrid } from '../../components/ui'
import { cmdRestartCompany } from '../../lib/rpc'
import type { Refusal, RestartCard } from '../../lib/rpc'
import { HullCountry } from '../../live/HullCountry'
import { useWorld } from '../../live/worldStore'
import { useAuthStore } from '../../store/authStore'
import { useT } from '../../lib/i18n'
import { COMPANY_NAME_MAX, companyNameToSend } from '../../domain/company'

// RESTART (0509; the owner, 2026-11-25: "I need a way to restart the game"). The player closes their own company and founds again: her name
// typed to confirm, a new name, a country of Europe. The server decides all of it (`cmd.restart_company`) and its sentence is printed as it
// arrives; `restart` is served only while the owner's switch is on, so dark draws nothing. After a restart the page is loaded again: every
// read and draft in memory belongs to the closed company. The form stands on a pop-up page, so the press moves nothing behind it.

export function RestartCompany({ name, card }: { name: string; card: RestartCard }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  return (
    <Card title={t('profile.restartTitle')} data-testid="profile-restart">
      <Button variant="secondary" onClick={() => setOpen(true)} data-testid="restart-open">
        {t('profile.restart')}
      </Button>
      {open && <RestartPage name={name} card={card} onClose={() => setOpen(false)} />}
    </Card>
  )
}

function RestartPage({ name, card, onClose }: { name: string; card: RestartCard; onClose: () => void }) {
  const t = useT()
  const [confirm, setConfirm] = useState('')
  const [next, setNext] = useState('')
  const [nation, setNation] = useState(card.nations[0] ?? '')
  const [busy, setBusy] = useState(false)
  const refresh = useWorld((s) => s.refresh)
  const authMode = useAuthStore((s) => s.mode)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const typed = companyNameToSend(confirm)
  const ready = typed === companyNameToSend(name) && companyNameToSend(next).length >= 3 && nation !== ''

  const press = () => {
    if (busy || !ready) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdRestartCompany(typed, companyNameToSend(next), nation)
      if (r.ok) {
        // signed in: the page is loaded again, so nothing read for the closed company is left. A world kept in this browser is read again in
        // place (a load straight after a write could be ahead of its own saving).
        if (authMode === 'local') {
          await refresh()
          onClose()
        } else window.location.reload()
        return
      }
      setRefusal(r.refusal)
      setBusy(false)
    })()
  }

  return (
    <DetailPage title={t('profile.restartTitle')} onClose={onClose} data-testid="restart-page">
      {card.refusal ? (
        <p className="text-t-body text-ink" data-testid="restart-refused">
          {card.refusal.sentence}
        </p>
      ) : (
        <div className="flex flex-col gap-4">
          <p className="text-t-body text-ink" data-testid="restart-warning">
            {t('profile.restartWarning')}
          </p>
          <div>
            <p className="text-t-label text-ink-muted">{t('found.nameQ')}</p>
            <Field
              icon={null}
              className="mt-2"
              value={next}
              maxLength={COMPANY_NAME_MAX}
              onChange={(e) => setNext(e.target.value)}
              aria-label={t('found.nameQ')}
              autoComplete="off"
              data-testid="restart-name"
            />
            <Hint className="mt-2">{t('found.nameRule')}</Hint>
          </div>
          <div>
            <p className="mb-2 text-t-label text-ink-muted">{t('found.countryQ')}</p>
            <TileGrid label={t('found.country')} words={2} wordsWide={3} data-testid="restart-nations">
              {card.nations.map((code) => (
                <TileChoice key={code} on={code === nation} onClick={() => setNation(code)} data-testid={`restart-nation-${code}`}>
                  <HullCountry nation={code} />
                </TileChoice>
              ))}
            </TileGrid>
          </div>
          <div>
            <p className="text-t-label text-ink-muted">{t('profile.restartConfirm', { name })}</p>
            <Field
              icon={null}
              className="mt-2"
              value={confirm}
              maxLength={COMPANY_NAME_MAX}
              onChange={(e) => setConfirm(e.target.value)}
              aria-label={t('profile.restartConfirm', { name })}
              autoComplete="off"
              data-testid="restart-confirm"
            />
          </div>
          {refusal && (
            <Note tone="danger" code={refusal.code} figures={refusal.figures}>
              {refusal.sentence}
            </Note>
          )}
          <Button variant="primary" className="w-full" busy={busy} disabled={!ready} onClick={press} data-testid="restart-press">
            {t('profile.restart')}
          </Button>
        </div>
      )}
    </DetailPage>
  )
}

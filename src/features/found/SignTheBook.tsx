import { useState } from 'react'
import { Button, Card, Field, Hint, LanguageSwitch, Note, PageSplit, Row, Sheet } from '../../components/ui'
import { cmdFoundHouse } from '../../lib/rpc'
import type { Refusal } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { NationPicker } from '../../live/NationPicker'
import { useSeaConditions } from '../../live/useSeaConditions'
import { useT } from '../../lib/i18n'

// SIGN THE BOOK — the first thing a captain on a real server ever sees, and until 2026-08-20 it
// did not exist.
//
// ── WHY THERE WAS NOTHING HERE ─────────────────────────────────────────────────────────────────
// Local mode founds its one captain during boot (localDb.ts calls `public.new_house()` as the
// superuser it is), so no screen was ever needed and none was ever missed. On a real project that
// function is revoked from every client role — permanently and correctly, because it takes a uid
// and a client holding it could found a house on somebody else's account. So a signed-in player
// arrived at an empty world with nothing to press. Migration 0011 gave the server side
// (`cmd.found_house(name)`, which takes NO uid and reads auth.uid() itself); this is the door.
//
// ── IT ASKS FOR TWO THINGS ─────────────────────────────────────────────────────────────────────
// A name, and (0143, owner 2026-10-17: like Uncharted Waters, every company belongs to a country)
// the country it sails for — Portugal unless chosen. Not a starting port, not a ship: DESIGN K.1
// opens every captain the same way — one Barca called Gaivota, 40,000 ducats — alongside in the
// chosen country's capital, and the server is what decides that (cmd.found_house), not this form.
// The capital's name printed here is read off the served catalogue, never kept here.
//
// ── AND IT VALIDATES NOTHING ───────────────────────────────────────────────────────────────────
// No length check, no "name taken" check, no trimming rules. `public.players` already carries
// `unique` and `check (length(btrim(company_name)) between 3 and 24)`, and 0011 turns each of those
// into a refusal with a sentence. Re-implementing them here would be a second authority that drifts
// the first time the constraint changes — so the button simply asks, and prints what comes back.

export function SignTheBook() {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const nationByCode = useWorld((s) => s.nationByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const [name, setName] = useState('')
  const [nation, setNation] = useState('PRT')
  const capitalCode = nationByCode[nation]?.capital ?? null
  const capital = capitalCode ? (portByCode[capitalCode]?.name ?? capitalCode) : null
  // WHILE THE SEA CONDITIONS BITE a company is founded in open water only: the countries whose capital's sea asks a
  // title above the first are not offered (the server's list, 0391; cmd.found_house refuses them with E_FAR_POWER).
  const sea = useSeaConditions().view
  const farPowers = sea?.bite ? sea.far_powers : undefined
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const sign = async () => {
    setBusy(true)
    setRefusal(null)
    const r = await cmdFoundHouse(name, nation)
    if (r.ok) {
      // The house exists now; the read is what makes it appear. Nothing here writes to the store.
      await refresh()
      return
    }
    setRefusal(r.refusal)
    setBusy(false)
  }

  return (
    // THE PAGE (2026-11-05, owner row 267): MAIN the form as one card, SIDE (the tray's column) how you begin and the language. One
    // column on a phone, the form first. "How you begin" was behind an (i) tray; the side column has the room, so it is printed.
    <Sheet title={t('found.title')} layout="page" data-testid="found">
      <PageSplit
        data-testid="found-page"
        side={
          <>
            <Card title={t('found.moreTitle')} data-testid="found-begin">
              <p className="text-t-body text-ink">{t('found.more', { capital: capital ?? t('found.yourCapital') })}</p>
              <p className="mt-2 text-t-caption text-ink-faint">{t('found.hint')}</p>
            </Card>
            <Card title={t('common.language')} data-testid="found-language">
              <LanguageSwitch className="w-fit" />
            </Card>
          </>
        }
        main={
          <>
      <Card data-testid="found-form">
        <label htmlFor="house-name" className="block text-t-label text-ink-muted">
          {t('found.nameQ')}
        </label>
        {/* The house's name is typed in the game's display face, not the UI face: this is the one
            field in the app that is a SIGNATURE. `Field` owns the chrome; the serif is this
            screen's own decision, passed through className (the input inherits the face). */}
        <Field
          icon={null}
          id="house-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && name.trim() && !busy) void sign()
          }}
          placeholder="Casa de Aveiro"
          autoComplete="off"
          autoFocus
          className="mt-2 font-serif"
        />
        <Hint className="mt-2">{t('found.nameRule')}</Hint>

        <p className="mt-4 text-t-label text-ink-muted">{t('found.countryQ')}</p>
        <div className="mt-2">
          <NationPicker value={nation} onChange={setNation} label={t('found.country')} closed={farPowers} />
        </div>

        {/* A refusal is DATA (DESIGN F.5): a sentence and at least one fix, printed as it arrives —
            this screen does not translate server errors into its own words. The code goes to
            console.debug (Note's own rule, the one WorldGate keeps), never to the screen. */}
        {refusal && (
          <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-3">
            {refusal.sentence}
          </Note>
        )}
        <div className="mt-4">
          <Button variant="primary" disabled={busy || name.trim().length === 0} onClick={() => void sign()}>
            {t(busy ? 'found.starting' : 'found.start')}
          </Button>
        </div>
      </Card>

      {refusal && refusal.fixes.length > 0 && (
        <Card title={t('found.try')} data-testid="found-try">
          {refusal.fixes.slice(0, 4).map((fix, i, shown) => (
            <Row key={fix} label={fix} hairline={i < shown.length - 1} />
          ))}
        </Card>
      )}
          </>
        }
      />
    </Sheet>
  )
}

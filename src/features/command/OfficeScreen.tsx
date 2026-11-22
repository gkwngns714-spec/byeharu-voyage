import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { DeskShell } from './DeskShell'
import { City } from './city/City'
import { Invest } from './invest/Invest'
import { Report } from './report/Report'
import { OFFICE_FACES, useOfficeView } from './officeView'
import { tabWord } from '../../app/navTabs'
import { useLocale, useT } from '../../lib/i18n'

// THE OFFICE TAB (owner, 2026-11-16: *"in trade, there are city invest report and levels, which aren't that related to trade.
// they should have separate tab like map you stats etc."*). City, Invest and Report were the Trade desk's faces; they MOVED
// here whole, with the desk's own shell (DeskShell.tsx: the fleet in hand, the faces, the three panes from 1024 px), so a
// face looks exactly as it did and only its door changed. The desk keeps Trade alone (officeView.ts says why). The Office
// lives in this folder beside the Trade desk: it is the desk's own shell with other faces, and a screen never imports
// another screen (tests/sections.spec.ts).

export function OfficeScreen() {
  const t = useT()
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/office')
  const face = useOfficeView((s) => s.face)
  const turnTo = useOfficeView((s) => s.turnTo)
  // HQ'S DOORS (2026-11-23, slice 2: the Office's faces stand on HQ as buildings): `?face=city|invest|report` turns to that face, once,
  // and the URL drops it, so the face strip stays the one control of which face is up.
  const [params, setParams] = useSearchParams()
  const asked = params.get('face')
  useEffect(() => {
    if (asked === null) return
    const hit = OFFICE_FACES.find((f) => f.id === asked)
    if (hit) turnTo(hit.id)
    setParams({}, { replace: true })
  }, [asked, turnTo, setParams])
  return (
    <DeskShell
      testid="office"
      title={title}
      faces={{ segments: OFFICE_FACES, value: face, onChange: turnTo, label: t('command.officeFaces') }}
      body={(fleet, layout) =>
        face === 'city' ? <City fleet={fleet} layout={layout} /> : face === 'invest' ? <Invest fleet={fleet} layout={layout} /> : <Report layout={layout} />
      }
    />
  )
}

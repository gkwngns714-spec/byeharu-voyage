import { properName, translate, translateMaybe, type Locale } from '../lib/i18n'
import type { SnapshotPort } from '../lib/rpc'
import { portNameOf } from './worldStore'

// A NAMED PIRATE'S NAME, in the viewer's language (0471). The server serves three parts: an epithet code (`BLACK`), a given name
// (`Ruy`) and her home's port CODE; this is the one place they become words: "Black Ruy of Port Royal", "포트로열의 검은 루이".
// A part the dictionary does not know prints as served (a truthful lesser answer), never a guess.

export interface BountyNameParts {
  epithet: string
  given: string
  home: string | null
}

export function bountyName(locale: Locale, parts: BountyNameParts, portByCode: Record<string, SnapshotPort>): string {
  const servedHome = parts.home === null ? '' : portNameOf(portByCode, parts.home)
  return translate(locale, 'bounty.name', {
    epithet: translateMaybe(locale, 'bounty', `ep_${parts.epithet}`) ?? parts.epithet,
    given: translateMaybe(locale, 'bounty', `g_${parts.given}`) ?? parts.given,
    home: properName('port', servedHome, servedHome, locale),
  })
}

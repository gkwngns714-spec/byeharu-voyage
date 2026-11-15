import { translateMaybe, type Locale } from '../lib/i18n'

// THE ONE WORD LIST FOR A MONEY KIND (2026-11-15 owner: shorter words; one authority). A ledger / treasury `kind` (SELL, TAX,
// TUITION…) is named by `feed.k_<KIND>` — for the Stats money log AND the Command Report, which kept its own `desk.kind*` copy
// until this file and had drifted from it (매도 / 판매, Tows / Tow). A city's side of a move reads `feed.c_<KIND>` where it
// differs (a company's sale is the city's purchase). A kind with no word keeps the server's own word.
export function moneyKindWord(locale: Locale, kind: string, served: string, holder: 'city' | string | null = null): string {
  return (holder === 'city' ? translateMaybe(locale, 'feed', `c_${kind}`) : null) ?? translateMaybe(locale, 'feed', `k_${kind}`) ?? served
}

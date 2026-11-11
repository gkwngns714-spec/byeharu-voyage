import { getLocale, translateMaybe } from '../lib/i18n'

// A CAPTAIN'S SKILL, BY ITS WORD (0355, docs/REPUTATION.md section 6, R2).
//
// The server names a skill twice: its code (`NAVIGATOR`, public.traits.code) and its English word (`Navigator`,
// public.traits.word). In English the served word is printed as it comes: the server is the one authority for it. In
// Korean the word is the dictionary's entry for the code (`books.skill_NAVIGATOR`, 항해사), and a code the dictionary
// does not know falls back to the served word rather than to nothing. One reader: the captain sheet's rows
// (YourCaptains.tsx, CaptainSkills.tsx) and History's sentence (features/ledger/headline.ts).
export function skillWord(code: string, served: string): string {
  const locale = getLocale()
  if (locale === 'en') return served
  return translateMaybe(locale, 'books', `skill_${code}`) ?? served
}

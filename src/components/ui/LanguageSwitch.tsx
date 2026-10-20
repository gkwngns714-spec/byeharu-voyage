import { Segmented } from './Chip'
import { setLocale, useLocale, useT, type Locale } from '../../lib/i18n'

// THE LANGUAGE SWITCH — 한국어 / English, each named in its own script so a player who reads only
// one of them can still find it. One control, placed on Profile and on the two pages a new player
// meets first (sign-in, sign the book). A switch re-renders the game in place.
export function LanguageSwitch({ className = '' }: { className?: string }) {
  const t = useT()
  const locale = useLocale()
  return (
    <div className={className} data-testid="language-switch">
      <Segmented<Locale>
        label={t('common.language')}
        value={locale}
        onChange={setLocale}
        segments={[
          { id: 'ko', label: t('common.korean') },
          { id: 'en', label: t('common.english') },
        ]}
      />
    </div>
  )
}

import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '../../store/authStore'
import { Button, Field, Hint, LanguageSwitch, Note } from '../../components/ui'
import { HOME_TAB } from '../../app/navTabs'
import { useT } from '../../lib/i18n'

// The sign-in / sign-up screen. Functionally identical to byeharu's: one form, two modes, the
// auth store does the work and this file only renders.
//
// DRAWN FROM THE TWELVE (2026-10-14). It was the last screen on the deprecated half — a `Card`
// with a `CardHeader`, two `Input`s and two `Notice`s. It is now the same vocabulary every tab
// speaks: one `surface` panel on the lit sea (a tone step, never a border — §4.3), the title in the
// title step, the subtitle in the caption voice (`Hint`), `Field`s and `Note`s.

type Mode = 'signin' | 'signup'

export function AuthPage() {
  const t = useT()
  const [mode, setMode] = useState<Mode>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const signIn = useAuthStore((s) => s.signIn)
  const signUp = useAuthStore((s) => s.signUp)
  const navigate = useNavigate()

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setNotice(null)
    setBusy(true)

    const action = mode === 'signin' ? signIn : signUp
    const { error } = await action(email, password)
    setBusy(false)

    if (error) {
      setError(error)
      return
    }
    if (mode === 'signup') {
      setNotice(t('shell.signedUp'))
      setMode('signin')
      return
    }
    navigate(HOME_TAB, { replace: true })
  }

  return (
    /* THE FIRST THING ANYONE SEES, so it gets the world behind it (docs/UI_DIRECTION.md rule 6).
       This was a flat `bg-app` field — the same colour as an unstyled page. It is the lit sea now,
       the same one the shell paints, so signing in and playing are visibly the same place. */
    <div className="bv-sea flex min-h-[100dvh] items-center justify-center px-4 py-8 text-ink">
      <section className="w-full max-w-sm rounded-tile bg-surface px-gutter py-6">
        <LanguageSwitch className="mb-4" />
        <h1 className="text-t-title">Byeharu Voyage</h1>
        <Hint className="mt-1">
          {mode === 'signin'
            ? t('shell.signinHint')
            : t('shell.signupHint')}
        </Hint>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <Field
            icon={null}
            type="email"
            required
            placeholder={t('shell.email')}
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <Field
            icon={null}
            type="password"
            required
            minLength={6}
            placeholder={t('shell.password')}
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />

          {error && <Note tone="danger">{error}</Note>}
          {notice && <Note tone="success">{notice}</Note>}

          <Button type="submit" variant="primary" busy={busy} busyLabel={t('shell.working')} className="w-full">
            {t(mode === 'signin' ? 'shell.signIn' : 'shell.createAccount')}
          </Button>
        </form>

        <Button
          variant="quiet"
          size="sm"
          className="mt-4 w-full"
          onClick={() => {
            setMode((m) => (m === 'signin' ? 'signup' : 'signin'))
            setError(null)
            setNotice(null)
          }}
        >
          {t(mode === 'signin' ? 'shell.toSignup' : 'shell.toSignin')}
        </Button>
      </section>
    </div>
  )
}

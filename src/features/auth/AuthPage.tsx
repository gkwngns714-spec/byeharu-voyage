import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '../../store/authStore'
import { Button, Card, CardHeader, Notice } from '../../components/ui'
import { HOME_TAB } from '../../app/navTabs'

// The sign-in / sign-up screen. Functionally identical to byeharu's: one form, two modes, the
// auth store does the work and this file only renders. Restyled as the first page of a ship's
// register — a ruled card, a mono heading rule, parchment on ink.

// Shared token-based input chrome (both fields are identical); ≥44px touch targets.
const INPUT_CLASSES =
  'min-h-11 w-full rounded-md border border-edge bg-surface-2 px-3 py-3 text-sm text-ink ' +
  'placeholder:text-ink-faint outline-none transition focus:border-accent focus:ring-1 focus:ring-accent/40'

type Mode = 'signin' | 'signup'

export function AuthPage() {
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
      setNotice('Entered in the register. Confirm your email if asked, then sign in.')
      setMode('signin')
      return
    }
    navigate(HOME_TAB, { replace: true })
  }

  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-app px-4 py-8 text-ink">
      <Card tone="accent" className="w-full max-w-sm">
        <CardHeader
          eyebrow="Register of shipping"
          title="Byeharu Voyage"
          subtitle={
            mode === 'signin'
              ? 'Sign the book and take up your command.'
              : 'Enter your name in the register and be given your first ship.'
          }
        />

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="email"
            required
            placeholder="Email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={INPUT_CLASSES}
          />
          <input
            type="password"
            required
            minLength={6}
            placeholder="Password"
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={INPUT_CLASSES}
          />

          {error && <Notice tone="danger">{error}</Notice>}
          {notice && <Notice tone="success">{notice}</Notice>}

          <Button type="submit" variant="primary" busy={busy} busyLabel="Working…" className="w-full">
            {mode === 'signin' ? 'Sign in' : 'Create account'}
          </Button>
        </form>

        <Button
          variant="ghost"
          size="sm"
          className="mt-4 w-full"
          onClick={() => {
            setMode((m) => (m === 'signin' ? 'signup' : 'signin'))
            setError(null)
            setNotice(null)
          }}
        >
          {mode === 'signin' ? 'No account yet? Sign the register' : 'Already in the register? Sign in'}
        </Button>
      </Card>
    </div>
  )
}

import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '../../store/authStore'
import { Button, Card, CardHeader, Input, Notice } from '../../components/ui'
import { HOME_TAB } from '../../app/navTabs'

// The sign-in / sign-up screen. Functionally identical to byeharu's: one form, two modes, the
// auth store does the work and this file only renders. Restyled as the first page of a ship's
// register — a ruled card, a mono heading rule, parchment on ink.

// The two fields used to share a hand-written INPUT_CLASSES string here. That string was one of
// four such recipes in the app; it is the design system's `Input` now (Input.tsx).

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
    /* THE FIRST THING ANYONE SEES, so it gets the world behind it (docs/UI_DIRECTION.md rule 6).
       This was a flat `bg-app` field — the same colour as an unstyled page. It is the lit sea now,
       the same one the shell paints, so signing in and playing are visibly the same place. */
    <div className="bv-sea flex min-h-[100dvh] items-center justify-center px-4 py-8 text-ink">
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
          <Input
            type="email"
            required
            placeholder="Email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <Input
            type="password"
            required
            minLength={6}
            placeholder="Password"
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
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

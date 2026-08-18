import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '../store/authStore'
import { Skeleton } from '../components/ui'

/** Gate that redirects unauthenticated visitors to /auth. */
export function RequireAuth({ children }: { children: ReactNode }) {
  // ONE gate field, so cloud mode and local mode cannot drift apart. See authStore.
  const authed = useAuthStore((s) => s.authed)
  const loading = useAuthStore((s) => s.loading)

  if (loading) {
    // The app-boot placeholder, on the design system: a quiet panel-shaped skeleton stack rather
    // than bare text. The sr-only status keeps the announcement for screen readers.
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-app px-4 text-ink" aria-busy="true">
        <div className="w-full max-w-sm">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="mt-3 h-28 w-full rounded-card" />
          <Skeleton className="mt-3 h-11 w-full rounded-md" />
          <span className="sr-only" role="status">
            Loading…
          </span>
        </div>
      </div>
    )
  }

  if (!authed) {
    return <Navigate to="/auth" replace />
  }

  return <>{children}</>
}

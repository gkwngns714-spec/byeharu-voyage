import { useEffect } from 'react'
import { Navigate, useParams } from 'react-router-dom'
import { SignTheBook } from './SignTheBook'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { useWorld } from '../../live/worldStore'
import type { Refusal } from '../../lib/rpc'

// THE THREE DOORS, IN THE GALLERY (2026-11-05, owner row 267). A player meets three screens that no tab shows: the BOOK a new
// captain signs (`SignTheBook`), the WORLD OPENING (`WorldLoading`) and the WORLD REFUSING (`WorldFailed`). None can be reached on
// demand in local play (the house is founded at boot, the world opens, the world does not fail), so tests/gates.design.spec.ts reads
// them here — `/ui/gates/found`, `/ui/gates/loading`, `/ui/gates/failed` — exactly as the page pattern is read at `/ui/page`.
// Inside RequireAuth (the book reads the served nations), outside the tab shell; nothing links to it.

const REFUSED: Refusal = {
  code: 'E_TRANSPORT',
  sentence: 'The server did not answer.',
  fixes: ['Check your connection.', 'Reload the page.'],
  detail: '08006',
  source: 'fault',
}

export function GatesGalleryScreen() {
  const { state } = useParams()
  const phase = useWorld((s) => s.phase)
  useEffect(() => {
    // only the book needs the world (its nations); the other two are drawn with no store at all
    if (state === 'found') void useWorld.getState().open()
  }, [state])
  if (state !== 'found' && state !== 'loading' && state !== 'failed') return <Navigate to="/ui" replace />
  return (
    <div className="bv-sea h-dvh" data-testid="gates" data-gate={state} data-world={state === 'found' ? phase : undefined}>
      {state === 'found' && phase === 'ready' && <SignTheBook />}
      {state === 'loading' && <WorldLoading title="Command" />}
      {state === 'failed' && <WorldFailed title="Command" refusal={REFUSED} />}
    </div>
  )
}

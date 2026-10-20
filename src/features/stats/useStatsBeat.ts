import { useEffect, useState } from 'react'
import { STATS_REFRESH_MS } from './statsFaces'

/** The Stats tab's own beat: a number that moves once a minute while a face is open, handed to
 *  `useServedRead` as its `trigger` so the read re-asks on THIS cadence and not the world's 3-s beat
 *  (useServedRead.ts, "WHAT RE-ASKS"). Mounted once by the screen; every face reads the same tick. */
export function useStatsBeat(): number {
  const [beat, setBeat] = useState(0)
  useEffect(() => {
    const id = window.setInterval(() => setBeat((b) => b + 1), STATS_REFRESH_MS)
    return () => window.clearInterval(id)
  }, [])
  return beat
}

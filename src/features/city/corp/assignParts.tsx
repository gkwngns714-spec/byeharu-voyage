import type { ReactNode } from 'react'
import { GroupHeading, Note } from '../../../components/ui'
import type { Refusal } from '../../../lib/rpc'

// THE PARTS OF THE ASSIGN SHEET its three actions share (AssignSheet.tsx, RoundAssign.tsx): a step, a line of the foot, the foot.

/** A step's heading and its choices. */
export function Step({ word, children }: { word: string; children: ReactNode }) {
  return (
    <div className="mb-4">
      <GroupHeading>{word}</GroupHeading>
      {children}
    </div>
  )
}

/** One line of the foot: what it is, and its figure at the edge. */
export function FootLine({ word, figure }: { word: ReactNode; figure: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="min-w-0 break-words text-t-body text-ink">{word}</span>
      <span className="shrink-0">{figure}</span>
    </div>
  )
}

/** The foot: the figures, the refusal's place and the press, standing under the choices on every glass. */
export function Foot({ figures, refusal, press }: { figures: ReactNode; refusal: Refusal | null; press: ReactNode }) {
  return (
    <div className="sticky -bottom-6 -mx-gutter bg-bg px-gutter pb-6 pt-3" data-testid="corp-assign-foot">
      <div className="flex min-h-[5.25rem] flex-col justify-center gap-0.5" data-testid="corp-assign-figures">
        {figures}
      </div>
      <div className="min-h-6">
        {refusal && (
          <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="corp-assign-refusal">
            {refusal.sentence}
          </Note>
        )}
      </div>
      {press}
    </div>
  )
}

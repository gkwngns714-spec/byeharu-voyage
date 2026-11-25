import type { ComponentProps, ReactNode } from 'react'
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

/** One choice of a list: a full-width row of 44 px, lit while it is picked. */
export function ChoiceRow({ on, ...rest }: { on: boolean } & Omit<ComponentProps<'button'>, 'className' | 'type'>) {
  return (
    <button
      type="button"
      aria-pressed={on}
      className={`flex min-h-11 w-full items-center justify-between gap-3 rounded-control px-3 text-left transition ${on ? 'bg-accent-soft ring-1 ring-inset ring-accent' : 'bg-surface hover:bg-surface-2'} disabled:opacity-45`}
      {...rest}
    />
  )
}

/** A number she sets, under its word; empty sends nothing. */
export function SettingBox({ word, value, onChange, mode = 'numeric', testid }: { word: ReactNode; value: string; onChange: (v: string) => void; mode?: 'numeric' | 'decimal'; testid: string }) {
  return (
    <label className="flex min-w-0 flex-col gap-1 text-t-caption text-ink-muted">
      <span>{word}</span>
      <input
        inputMode={mode}
        autoComplete="off"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="min-h-11 w-full min-w-0 rounded-control bg-surface px-3 text-base tabular-nums text-ink ring-1 ring-inset ring-edge focus:ring-accent"
        data-testid={testid}
      />
    </label>
  )
}

/** A quiet line that opens what stands under it. */
export function FoldPress({ open, onToggle, children, testid }: { open: boolean; onToggle: () => void; children: ReactNode; testid: string }) {
  return (
    <button type="button" aria-expanded={open} onClick={onToggle} className="flex min-h-11 w-full items-center justify-between gap-3 text-left text-t-caption text-ink-muted" data-testid={testid}>
      {children}
    </button>
  )
}

/** Small figures side by side, a word and its figure each. */
export function FigureLine({ children, testid }: { children: ReactNode; testid?: string }) {
  return (
    <p className="flex flex-wrap gap-x-3 gap-y-1 text-t-caption tabular-nums text-ink-muted" data-testid={testid}>
      {children}
    </p>
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

import type { IconName } from '../../components/ui'

// THE MARK ON A VERB'S ACTION CARD — presentation, and nothing else.
//
// It is a map from a verb NAME to an icon name, and it deliberately does not know what a verb is,
// what arguments it takes or whether it is legal. That is all the server's (F.4): the composer
// walks `world.snapshot().verbs`, and a verb this table has never heard of still draws a card —
// with its initial in place of a mark — rather than disappearing or throwing. Add a verb to the
// chain and it appears; add a line here later if it deserves a glyph.
//
// It lives in features/command because the composer is the only screen that draws a verb. The
// moment a second screen wants it, it is neither screen's and moves to src/domain/order with an
// entrance of its own (docs/SECTIONS.md).

export const VERB_ICON: Record<string, IconName | undefined> = {
  SAIL: 'compass',
  BUY: 'coin',
  SELL: 'scales',
  PROVISION: 'cask',
  HIRE: 'crew',
  REPAIR: 'mallet',
  CANCEL: 'close',
  CLEAR: 'history',
}

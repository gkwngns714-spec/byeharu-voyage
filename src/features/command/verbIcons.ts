import type { IconName } from '../../components/ui'

// THE MARK ON A VERB'S TILE — presentation, and nothing else.
//
// A map from a verb NAME to an icon name. It deliberately does not know what a verb is, what
// arguments it takes or whether it is legal — that is all the server's (F.4): the grid walks
// `world.snapshot().verbs`, and a verb this table has never heard of still draws a tile, with its
// initial in place of a mark, rather than disappearing. Add a verb to the chain and it appears; add
// a line here later if it earns a glyph.
//
// The six 0068–0074 verbs (STORE/TAKE/MAKE/BUILD/FIT/UNFIT) have no glyph in `icons.ts` yet, so
// they draw with their initial. Drawing six new marks is an icon-set change, not a COMMAND one.

export const VERB_ICON: Record<string, IconName | undefined> = {
  SAIL: 'compass',
  BUY: 'coin',
  SELL: 'scales',
  PROVISION: 'cask',
  HIRE: 'crew',
  REPAIR: 'mallet',
}

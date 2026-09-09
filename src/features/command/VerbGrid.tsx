import { Button, Icon } from '../../components/ui'
import { VERB_ICON, verbWord } from './verbIcons'
import type { VerbSpec } from '../../lib/rpc'

// THE TWELVE VERBS, AS A FIELD OF ACTION BUTTONS — icon and word, and nothing else.
//
// §6: "3×4 verb tiles, icon + word only". What died from the old grid (OrderComposer:344): the
// two-line `spec.help` sentence under every verb (read once, ever — §2 item 3), the `VERB` label
// above it, and the `bv-cut border … bg-surface-2` skin (§5's ban).
//
// A VERB IS AN ACTION, SO IT IS A `Button`, NOT THE GOODS `Tile`. The tile is 112px tall because a
// good fills it with two figures and a bar; a verb has one word, so a tile leaves it stranded in
// empty space and shears "Provision" to "Provi…". A flat `Button` is the right primitive for "a
// thing you press to choose an action": it is 44px, its word fits, its selected state is the
// accent fill §4.4 gives the one interactive colour, and — like the tile — it carries its skin
// inside the primitive, so §5's inline-skin ban is unbothered. Two across (not the sketch's three):
// at 390px a three-wide cell shears "Provision", and a word a player cannot read is a verb they
// cannot choose (nav.geometry keeps the same rule for the tab bar). Two across is six 44px rows —
// ~300px, a fifth of the 112px-tile grid it replaces, and still far above where the old first
// price sat.
//
// THE GRID NEVER RESTRUCTURES. Choosing a verb fills its button and moves nothing — all twelve stay
// the same size in the same places (the owner, three times: "when pressing sail, stop folding the
// sail"). Re-tapping the chosen verb keeps it; a DIFFERENT verb goes through `chooseVerb`, whose one
// authority discards the old arguments (`dest` means nothing to BUY — domain/order/draft.ts).

export function VerbGrid({
  verbs,
  chosen,
  onChoose,
}: {
  verbs: readonly VerbSpec[]
  chosen: string | undefined
  onChoose: (verb: string) => void
}) {
  return (
    <div className="grid grid-cols-2 gap-2">
      {verbs.map((v) => {
        const on = v.verb === chosen
        const icon = VERB_ICON[v.verb]
        return (
          <Button
            key={v.verb}
            variant={on ? 'primary' : 'secondary'}
            className="w-full justify-start"
            onClick={() => {
              if (!on) onChoose(v.verb)
            }}
          >
            {icon ? (
              <Icon name={icon} size={18} className="shrink-0" />
            ) : (
              <span className="inline-flex w-5 shrink-0 justify-center">{v.verb.charAt(0)}</span>
            )}
            <span className="min-w-0 truncate">{verbWord(v.verb)}</span>
          </Button>
        )
      })}
    </div>
  )
}

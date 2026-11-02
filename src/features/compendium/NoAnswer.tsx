import { Row } from '../../components/ui'
import { useT } from '../../lib/i18n'

/** A filter that matches nothing says so — one quiet row, the same on every face. A bare empty
 *  list is indistinguishable from a broken one. In a card list laid out in columns it spans them
 *  all (`col-span-full`): one sentence across the card, never a sentence in the first column. */
export function NoAnswer() {
  const t = useT()
  return <Row label={t('codex.noMatches')} tone="muted" hairline={false} className="col-span-full" data-testid="codex-no-match" />
}

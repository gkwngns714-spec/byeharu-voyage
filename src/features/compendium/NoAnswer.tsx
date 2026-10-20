import { Row } from '../../components/ui'
import { useT } from '../../lib/i18n'

/** A filter that matches nothing says so — one quiet row, the same on every face. A bare empty
 *  list is indistinguishable from a broken one. */
export function NoAnswer() {
  const t = useT()
  return <Row label={t('codex.noMatches')} tone="muted" hairline={false} />
}

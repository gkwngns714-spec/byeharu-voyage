import { Row } from '../../components/ui'

/** A filter that matches nothing says so — one quiet row, the same on every face. A bare empty
 *  list is indistinguishable from a broken one. */
export function NoAnswer() {
  return <Row label="No matches." tone="muted" hairline={false} />
}

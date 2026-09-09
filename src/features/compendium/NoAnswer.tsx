import { Row } from '../../components/ui'

/** A filter that matches nothing says so — one quiet row, the same on every face. A bare empty
 *  list is indistinguishable from a broken one. */
export function NoAnswer() {
  return <Row label="Nothing answers to that." tone="muted" hairline={false} />
}

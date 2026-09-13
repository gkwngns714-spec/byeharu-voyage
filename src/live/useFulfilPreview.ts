// THE DELIVERY, PRICED — `cmd.preview_fulfil` (0087) run for real and rolled back, as one answer
// that keeps standing while the next one is on the wire.
//
// docs/QUAY_LEDGER.md §3 F: a press on a request opens the one tray with the served preview —
// what you deliver, what you get, the premium as its own line, profit vs bought-at. None of those
// can be summed on this side of the wire (the sale walks a stepped book; the premium is the
// board's own figure), so the ONE reading is the dry run, asked here. A refusal (E_CONTRACT_SHORT
// with have/need, E_CONTRACT_EXPIRED, E_DAILY_CAP from the sale inside) is the answer, not the
// absence of one — `usePreviewRead` keeps it standing.
//
// The SUBJECT is (fleet, request): a re-read of the world re-asks the same subject and keeps the
// last answer on screen (row 77's rule); another request shows nothing of this one's.

import { cmdPreviewFulfil } from '../lib/rpc'
import { usePreviewRead, type PreviewRead } from './usePreviewRead'

export function useFulfilPreview(fleetId: string, contractId: string): PreviewRead {
  return usePreviewRead(`${fleetId}:fulfil:${contractId}`, () => cmdPreviewFulfil(fleetId, contractId))
}

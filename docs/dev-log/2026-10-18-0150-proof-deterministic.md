# 2026-10-18 — 0150's probes size every state from the merchant's own hull — `osn-0150-proof-deterministic`

**The red.** Main's run for #168, and PR #177, failed inside 0150 in the pglite gates (ledger,
merchants) with `ROOM — the probe did not make a stuck lap (head <NULL> <NULL>, fleet SAILING)`.
Another machine saw it pass and then fail minutes later on the same chain.

**Why.** The ROOM probe left room for half her preset's water. She stayed stuck only when the
passage needed more than that half. The preset is what the planner writes (her loop's days, or the
12 days she was founded with). The need is what the SAIL measures at her speed, and her speed moves
with the hold's fill. In some worlds and at some moments the half was enough, so she sailed and the
positive control failed. The previous version had read the world in other ways too: the first good
by id, and a parcel the size of the hold. None of these touched the function bodies; every failure
was in the probe.

Checked against the captains agent's hint: the probe reads the queue head in its own statement,
after `perform cmd.advance`. The `NULL` head was real — she had sailed.

**The fix (self-assert only).** Each quantity now comes from her own hull and her own passage:

- `v_legd` is her FNC → LIS passage on an empty hull, through `endurance_margin`. It is asserted to
  be over 2 days.
- `v_pdays` = 3 × `v_legd` + her preset + 5. A full hold slows her by at most 25 %
  (`load_speed_penalty`), so this covers anything the SAIL measures.
- **PRESET:** a 1-day preset against a passage of more than 2 days, so the refusal is certain.
- **ROOM:** her hold has no free room at all. It holds a parcel of `v_pdays` of her water, in tons,
  of the first good by code that FNC takes whole (its quote and her daily cap), and food in every
  other ton. Water is 0, so the refusal is certain, and after the cut-loss everything she needs fits
  where the parcel lay. FNC's treasury is funded so that a lit city can pay for the sale.
- **CASKS:** her preset is `v_pdays`, with no water and food for twice that. A positive control
  checks that the old split falls short.
- Each scenario also asserts that the SAIL's own need is within `v_pdays`.
- Every scenario runs twice: in the world as found, and with `city_treasury_enabled` and
  `influence_enabled` lit (prod's switches), rolled back.

The function bodies are byte-identical to prod's (each hunk's new text occurs once in prod's live
`pg_get_functiondef`; the three helpers are verbatim). Editing an applied migration is the
no-from-zero law's one exemption, so this PR's CI applies from zero.

**Determinism.** On a restored prefix through 0149, 0150 was applied 5 times, about 50 s apart:
5/5 passed, all six scenarios each time.

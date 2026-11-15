# 2026-11-15: main red on 0270's self-assert: the probe sorted rows by uuids it had drawn itself

> **CI machinery only:** `src/lib/db/frozenAsserts.ts` (six entries), its spec, one local proof script. No migration
> is touched (`supabase/migrations/` is byte for byte as on main), no cache key or snapshot key moves, prod is not touched.

## What was red

Main, run 43708858363 (commit `3dc7cee`), job `pglite-gate (merchants)`. No kept prefix existed, so the leg applied
all 400 files from zero and died after 64 minutes:

```
MIGRATION FAILED: 20260818000270_the_clear_replans_her_lines_before_the_quay.sql
  message: 0270 self-assert FAIL: the loop leaves different rows: {"name": "Nau do Trato", … / {"name": "Nau do Trato", …
  notices before the failure:
    tick_reconcile: {"merchant_upkeep": {"tend": {… "cleared": 1, … "started": 5, …}}, "players_checked": 4, …}
    tick_reconcile: {"merchant_upkeep": {"tend": {… "cleared": 1, … "started": 5, …}}, "players_checked": 4, …}
```

The ledger leg (also from zero) and disposable-chain passed on the same commit. The two receipts in the log are equal,
and so are the 1,200 characters of each digest the file prints: the difference lay further in.

## The cause

0270's probe 2 runs the hourly loop twice in rolled-back blocks, OLD body then NEW, and compares a text digest of the
rows each leaves (`pg_temp.digest_0270`). For a house's ledger rows and events the digest does this:

```sql
(select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.ledger l where …) a)
…  -- and only then, over the whole string:
regexp_replace(…, '[0-9a-f]{8}-…-[0-9a-f]{12}', 'U', 'g')
```

The rows are **sorted while they still hold their uuids**, and the uuids are blanked afterwards. A ledger row's text
is `kind, player_id, created_at, ducats_delta, ref_event_id, balance_after`. Two rows of one house with the same kind
and the same amount are therefore ordered by `ref_event_id`, a `gen_random_uuid()` the probe drew a moment before, and
they differ after it (`balance_after`). Each run draws new uuids, so the two rows swap at random: two **identical**
runs digest differently, half the time for each such pair the world holds.

Whether it holds one is the market's dice. 0270's loop starts two merchants of one house twice over (Casa da Índia:
Carreira da Índia and do Brasil; Kamer Amsterdam: Retourvloot and Oostzeevaart), and each writes BUY, PROVISION and
INSURANCE rows; what they buy and what the insurance costs follows the prices that apply dealt.

It is not the clock and not the leg. The three legs build the same world from the same chain; the wall clock is read
only for the receipt's stopwatches and the 60-second budget.

## Measured (PGlite, one world built to 0269 on PC gkwng, restored from its snapshot for every run)

| what | result |
|---|---|
| 0270 as written, as the world was dealt, 8 applies | 8 pass |
| the loop probe alone, OLD / NEW / OLD again, 25 times in one transaction | 75 runs, every digest equal: no clock, no dice between two runs |
| the loop probe on 60 random samples of six merchants (OLD / NEW / OLD) | 2 of 60 differ, **old against old**: two `PROVISION` rows of amount 0 in one house, swapped, `balance_after` 5000 / 508 |
| 0270 as written, a tied pair made (both provisioning prices 0, so Kamer Amsterdam's two merchants each write `PROVISION 0`) | **8 of 12 applies fail** with `the loop leaves different rows`; the rows that differ are the two `PROVISION` rows, swapped |
| 0274 as written, the same pair | 6 of 8 fail, the same way |
| the proof script, 0270 as written, the same pair | 9 of 12 fail; in every failure the two digests hold the same rows in another order, and every row that moved is a ledger row |
| 0270 patched, the same pair | 0 of 12 fail (and 0 of 12 again in the proof script) |
| 0274 patched, the same pair (its world built through the patched 0270, 0272, 0273) | 0 of 8 fail |
| 0270 patched, one more event written by the NEW loop (mutant) | 3 of 3 fail: the assert still sees a real difference |
| the same 60 random samples, patched | 60 of 60 equal |
| 0270 as written on 45 redrawn markets (one drift step each) | 45 pass: a tied pair is not common, which is why this stayed hidden |

What the truncated CI log cannot show is the tied pair itself (the file prints 1,200 characters of a digest of about
10,000). Everything it does show fits: the same message, equal receipts, equal leading rows, one leg red and its twin
green on one commit.

## The fix

The files are frozen (prod head is past them), so the sanctioned place is `src/lib/db/frozenAsserts.ts`. One entry
per file, built by one helper: at the head of the self-assert (before its first statement) the probe's own temp
function is re-cut from its live text, with the two row sets blanked **before** they are sorted:

```sql
regexp_replace((to_jsonb(l) - 'id')::text, '<uuid>', 'U', 'g') as x from public.ledger l
regexp_replace((to_jsonb(e) - 'id')::text, '<uuid>', 'U', 'g') as x from public.events e
```

Rows that tie are then identical, so their order cannot matter; every row still counts, so a real difference still
fails (the mutant). The re-cut checks its own effect (the body must grow by exactly 180 characters) and raises
otherwise. Nothing else in the self-assert moves: the patched text is the file plus 14 lines.

**The same class, fixed with it.** Six files carry this digest: 0266, 0269, 0270, 0272, 0273, 0274. 0270 and 0274 are
the exposed ones (their loop starts two merchants of one house); 0269's loop has the same shape but took no tied pair
here; 0266, 0272 and 0273 probe one merchant at a time and would need one merchant to write two equal rows. All six
get the entry; the spec fails if a seventh file ever carries the same sort without one. Other digests in the chain
were read and are sound: 0261 blanks before it sorts and orders its ledger rows by columns with no uuid; 0256 orders
one departure's events by kind.

## Checked

- `tests/db.frozenAsserts.spec.ts` (5 pass): each of the six files holds the two row texts exactly once, in its
  digest; the signature the patch names is the file's; the patch only adds lines before the self-assert's first
  statement; no other migration carries the sort.
- `node scripts/ops/harness/frozen-0270/proof-0270-ties.mjs` (and `--file=0274`): red first, green, mutant.
- Each patched file applied through the applier's own path: 0266 (on the 224-file snapshot plus 30 files), 0269,
  0270, 0272, 0273, 0274.
- `node scripts/ci/patch-frozen-asserts.mjs <a copy>`: all eleven entries apply to a working copy (the route the
  from-zero applies on real Postgres read).
- `tsc -b`, `eslint`. `vite build` was not run here: this worktree has its own `npm ci` and no cached prefix for the
  browser variant, so its world image would have been a local from-zero replay; CI builds it.

## What this PR's own CI does

`src/lib/db/**` is chain machinery (`select-specs.mjs`, the growth rule), so the PR is exempt from the law:
disposable-chain applies from zero on real Postgres with the patched working copy, and the push to main after the
merge is a from-zero net run too. The prefix-cache keys hash the files, which did not change, so the PGlite legs
restore whatever main has kept.

## Not fixed here

Run 43707035600's disposable-chain red (`did not start in three tries`, 19 minutes in) is `supabase start`, not the
chain.

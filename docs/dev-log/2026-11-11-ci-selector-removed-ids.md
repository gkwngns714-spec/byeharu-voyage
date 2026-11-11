# 2026-11-11: #583 went red on main after a green PR. The selector was not the cause.

## What happened

#583 removed the HQ's "Your earnings" card and its `data-testid="city-summary"`
(`src/features/city/CityScreen.tsx`). Its PR run was green. Main's full run on the squash commit
`67681824` (run 43074438997) failed four tests:

- `tests/market.shortTray.spec.ts:53` at 390 and at 1280 (it reads `getByTestId('city-summary')`, timed out)
- `tests/city.phone.spec.ts:113`, Korean, 320×640
- `tests/hq.design.spec.ts:96`, ko-KR, 320×640

The first reading was "rule I only looks at ids the head file declares, so a removed id is missed".
That is not what the code did, and not what happened.

## What was measured

1. **The selector picks all three on #583's diff, before any change.**
   `node scripts/ci/select-specs.mjs --base 67681824^1 --head 67681824` selects 84 specs, among them
   `market.shortTray.spec.ts` (`I: names data-testid "city-summary"`, read off the diff's removed
   line), `city.phone.spec.ts` (rule I: `city-screen`, `city-face-panel`, `city-info-image`) and
   `hq.design.spec.ts` (rule C, and rule I).
2. **The PR's run judged an older main.** #583 had one Acceptance run, 43033062202, started
   13:52:19 UTC, on merge commit `853ee0eb` = PR head `5ac7fabc` onto main `ffa9bf60`. It selected 83
   specs. `tests/market.shortTray.spec.ts` was not in that tree: #578 (`c7338b86`), which added the
   spec and rebuilt the HQ Market, merged at 14:48:35 UTC, 56 minutes later. #583 merged at 18:05:39
   UTC on the 13:52 green. Nothing re-ran it.
3. **The two HQ specs ran on the PR and passed.** The run's shard logs show
   `city.phone.spec.ts:113 › in Korean › … at 320×640` passed and `hq.design.spec.ts:96 › ko-KR › … at
   320×640` passed. Main with #578 and without #583 was green (run 43063070083, `f10d3300`). So each
   change was green alone and the two together were red: #578's HQ Market and #583's HQ layout meet at
   320 px in Korean.

So for each of the three, the reason no rule picked it on the PR:

| spec | on the PR's run | why |
|---|---|---|
| `market.shortTray` | not selected | the file did not exist in the judged tree (added by #578 after the run) |
| `city.phone` | selected, ran, passed | it failed only on #578 + #583 together |
| `hq.design` | selected, ran, passed | the same |

## What this PR changes

No rule was missing for #583, so none was added, and no PR runs more specs than before.

- **Rule I reads the base version of the file, not the diff's `-` lines**
  (`scripts/ci/select-specs.mjs`, `testIdsIn` / `ruleIIds`, and the rule I block in `select`). For an
  edited file the two are the same set. For a **renamed** file they are not: `git diff -- <new path>`
  shows it as all added, so an id dropped in the same commit as the move was not followed. The base
  text is now read under the old path. Probe (a throwaway commit, not pushed): `CityScreen.tsx` moved
  to `CityScreenMoved.tsx` with `city-nocity-fleet` removed. Before: no rule-I reason names that id.
  After: `city.nocity.spec.ts` carries `I: names data-testid "city-nocity-fleet"`.
- **A positive control for #583** (`67681824`): `market.shortTray` by rule I for `city-summary`,
  `city.phone` and `hq.design` selected, the selection still scoped.
- **Five fixed-text controls for rule I's id reading**: an added id (head ids only, as before), a
  removed id, a renamed id, a moved file, a new file.
- `docs/CI.md` and the header of `acceptance.yml` say what rule I reads, and state the gap that did
  cause this red.

## Selection sizes, before and after

Selector at `origin/main` against this branch's, on the last 14 merged PRs that touch the client or
a spec, and three older commits that rename `.tsx` files. Of 198 spec files:

| commit | PR | before | after |
|---|---|---|---|
| 3e1abcf7 | #593 | 94 | 94 |
| f7ca3741 | #586 | 135 | 135 |
| 66fd25e0 | #584 (renames) | 75 | 75 |
| 67681824 | #583 | 84 | 84 |
| c7338b86 | #578 | 145 | 145 |
| 56007457 | #582 | 2 | 2 |
| fc68cbac | #580 | 91 | 91 |
| ef041868 | #581 | 131 | 131 |
| 641cef66 | #576 | 105 | 105 |
| 36094611 | #577 | 98 | 98 |
| 870d9b1b | #579 | 68 | 68 |
| a0ea8bd6 | #571 | 127 | 127 |
| 559c23f6 | #574 | 139 | 139 |
| d16dd67f | #572 | 137 | 137 |
| d5e8ed54 | #399 (rename) | 68 | 68 |
| a589945f | #506 (rename) | 95 | 95 |
| cc5b6fd5 | #201 (renames) | 23 | 23 |

On all 17 the selected files and every printed reason are byte-identical. Extra specs on a typical
client PR: 0.

## The gap that is still open (decided by default: stated, not closed here)

A PR's green is a verdict on main as it stood when the run started. Auto-merge and a hand merge both
accept it however far main has moved. On 2026-11-11 main took 4 code merges between #583's run and
its merge.

What would close it, for the owner to choose (none is done in this PR; each is a repository setting
or a merge habit, not a selection rule):

1. Before merging a client PR whose last run is older than main's newest client or spec merge:
   `gh pr update-branch <n>`, which starts a fresh run on today's main. Cheapest; a habit, so it can
   be forgotten.
2. Branch protection "require branches to be up to date before merging". Enforced, but every merge
   then invalidates every other open PR's green, and `acceptance` is not a required check, so it
   would only force a fresh `build` + `disposable-chain`, and auto-merge would not wait for
   acceptance.
3. A merge queue with acceptance in it. The real fix; costs a full queue run per merge.

Until one is chosen, main's full run remains the net, as it was here.

## Not proven

- The fix for the red itself is not in this PR (the queue names #595 and #589 for it).
- Why Korean 320×640 fails with #578 + #583 together was not diagnosed here: only that each passed
  alone.
- The rename path of rule I has no real commit as a control (no commit in history moves a file and
  drops an id that only one spec names); it is held by the fixed-text control and the probe above.
- This PR's own CI did not run before this was written: GitHub Actions was in an outage.

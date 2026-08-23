# OWNER REQUESTS — the open ledger

**Why this file exists.** On 2026-08-23 the owner said: *"last time you messed up not doing
everything i told you. Do not make the same mistake again."* They were right, and the cause is
structural, not attentional: a list of instructions held in a conversation is **lost at the next
context compaction**, and this project has already lost instructions that way twice — once producing
*"what i said before to make, nothing is done"*, once *"then all the sayings that i did, you didn't
make them? what else you didn't do?"*.

So the list lives here, in the repo, where it survives compaction and can be diffed.

**The rules for this file**

1. **Every instruction from the owner gets a row, in their own words**, the moment it is given.
   Paraphrasing is how an instruction quietly narrows. Quote them.
2. A row leaves `OPEN` only when the thing is **built AND verified in the running game** — not when
   an agent reports it done. An agent report is a claim, not proof.
3. A row that is **refused or deferred** does not get deleted. It gets a state and a reason, so the
   owner can overrule it. Silently dropping something is the failure this file exists to prevent.
4. `DONE` rows stay for one release, then move to the bottom under `SHIPPED`. The file is not a
   changelog — `docs/DEV_LOG.md` is — but a request must be visibly closed rather than vanish.
5. **A repeated instruction is a bug report about this file.** If the owner has to say something
   twice, the row was wrong, or it was closed without being verified. Note it in the row.

---

## OPEN

| # | In their words | State | Notes |
|---|---|---|---|
| 1 | *"All game must be logged in so that they are safe."* / *"this is a online game, a user info and game progress should always be kept."* | **PART DONE — 2 settings left** | **Said twice.** Cause found: `deploy-pages.yml` never passed `VITE_SUPABASE_*`, so the published site was the local-PGlite build — a private world per browser, no account. Workflow now REFUSES to publish without both secrets (no silent fallback). Needs: repo secrets added, Pages Source → GitHub Actions, and migrations 0025-0029 applied to the live project. |
| 2 | *"Where it pays more does not need to be given in buy."* | **DONE — verified** | Deleting the block and the whole `routes` thread through COMMAND, including the per-port fetch. Stays on MARKET. |
| 3 | *"when pressing hire, 12, it unfolds. this is uncomfortable. keep it without unfolding, and let me hire."* | **DONE — verified** | HIRE is one number; a fold in front of one number is a door in front of a doorway. |
| 4 | *"Provision also, does not need to be fold/unfoldable."* | **DONE — verified** | Same reasoning as #3. |
| 5 | *"and hands? seriously? change it like crew or something."* | **DONE — verified** | Client screens done (galley reads `crew 8/20`). Seven strings are SERVER-authored (refusals, the pirate report, the HIRE verb help) and are getting migration 0030 — a client gloss over served copy would be a second authority. "Hands are shaken" stays: that is the handshake idiom, not crew cant. Landed as 0030; HIRE now reads "Sign on crew from the idle men in port", read off the running game. Its own self-assert went RED first and refused to let the world open with the rename half-applied — Section 7C working. |
| 6 | *"when treading buy, i see a trade good with buy sell. i want to be able to click on buy and sell itself and do trades. when pressed unfold another so that i can choose how much i buy"* | **DONE — verified** | The price cells become the action and set the verb. Must go through the ONE order authority. Replaces `Choose <good>`. **Do not flatten this fold** — it is the opposite case from #3/#4. Measured by coordinator at 390px: 140 price-cell buttons (70 goods x buy/sell), min height 75.7px, 70 sell cells disabled and each SAYING "none aboard" on the cell; 0 `Choose` buttons remain. |
| 7 | *"create a 도감, separate tab, showing all the trade goods, ships, captains that are made in this game. categorize them, make filters"* | **DONE — verified** | Reference only, commands nothing. Also has to solve 8 nav tabs → 9 without an orphan row. |
| 8 | *"i want explain icon next to everything that has long sentences for explanation"* | **DONE — verified** | **Said twice** (first as *"too long explanation. this is a game, make it so."*) — so the rule was written in `UI_DIRECTION.md` §4 and not applied everywhere. Refusal reasons stay visible. Sweep found the app already ~95% compliant (Explain is wired into the primitives); the real offenders are all in COMMAND, handed to the agent that owns it. |
| 9 | *"i want actual time shown on command, and how much left for it to change the prices live"* | **DONE — verified** | The read that serves the PRICES serves when they next move — deriving it client-side from two other served numbers would be a second authority for the cadence. Landed as 0029 (`world.market().clock`). Coordinator drove it: clock 11:24:40 to 11:24:44, countdown 5:19 to 5:15. **The re-ask at zero is also what STEPS the market** on any deployment without cron - never optimise it into a conditional fetch. |
| 10 | *"do the map layer and finish it"* | **DONE — verified** | Chart legibility and the act-from-map handoff both landed and were driven. Awaiting the final gate with everything else. |
| 11 | *"use fable also for better performance"* | STANDING | **Said twice.** Every `Agent` call passes `model: 'fable'`; omitting it silently inherits Opus, which is how it slipped. The main-loop model is the owner's to set via `/model`. |
| 13 | *"nope A, lets make it public"* (after first choosing B) | **DONE 2026-08-23** | Repo goes PUBLIC, not GitHub Pro. Verified safe on keys: `.env.local` never tracked, no key-shaped string anywhere in the repo or its history. **But `0001:145` seeds `world_secret` as a plain-text literal** (`voyage-v0-seed-6f2a91c4`) and `voyage.rng_raw` is public md5 in the same chain — publishing hands players a predictor for pirate attacks, haggle outcomes and the fair calendar. In git HISTORY too, so editing the file would not help. Fix in flight: production GENERATES its own seed at apply time so the repo never holds a real one. **Do not flip public until prod is proven to be running a seed that exists in no file.** Fix landed as **0031**: prod generates 128 hex chars of its own, and a CHECK constraint now refuses the published literal forever — the constraint, not the rotation, is what makes it permanent. Applied to prod 2026-08-23 and the assert ran INSIDE the production transaction: "rotated this apply: t", 128 hex chars, the published literal refused in 2 real rejected writes. Repo flipped PUBLIC only after that. |
| 12 | *"no spaghetti — separate independant codes, with plans for future … it has to be planned precisely and correctly"* | STANDING | Reactive half was already `docs/NO_SPAGHETTI.md` §§1-9 + `duplication.spec.ts`. The FORWARD half was missing and is now §7B. |

| 14 | Supabase access token stored on this machine | **DATED — expires ~2026-09-23** | Supabase no longer offers never-expiring personal tokens; 1 month is the max. Stored by `supabase login --token`, so no re-paste is needed until it lapses. **It was pasted into a chat transcript on 2026-08-23** - rotate it at the dashboard when convenient. When it expires, `db push` fails with a login error; that is the symptom, not a broken chain. |

## KNOWN AND NOT YET FIXED — surfaced by the work, not asked for

These are stated rather than quietly carried. The owner may not care about any of them; they are
here so the choice is theirs.

| What | Why it is not done |
|---|---|
| `BALANCE_MEDIAN_IN_BAND` (proof 05) is a lottery | Pre-existing non-determinism, measured: an unchanged chain gives medians 15.1/9.0/12.4/14.4/12.4/12.1 against a 4-16 band. A flake on the safety net. Worth its own slice. |
| `tests/rpc.firstSession.spec.ts` has the same root cause | Proof 04 was given a stationary-distribution fixture; this spec was not. |
| Proof 04 now winds the fair calendar | 0026's "the proofs run in a fair-free world" is half false; 0028's header says so. A fair can only make a trade cheaper, so it can only help the marker. The fixture was deliberately NOT reached into. |
| "Read this harbour's market" from the map | The read exists; the SEAM does not. "Which port is this house looking at" is component-local in MARKET and `sessionStorage` in PORT. A button that landed on the wrong port would be worse than no button. |
| `world.reachable(fleet)` is not served | Painting reachability across the sheet would be 214 round trips, or a client copy of the rule. That is a migration. |
| Nav bar geometry at 9 tabs | Being solved with the 도감; noted here in case the answer is to group tabs rather than add a row. |

---

## SHIPPED

Moved here once verified in the running game. See `docs/DEV_LOG.md` for what each one cost and what
it taught.

| In their words | Where |
|---|---|
| *"make icon for each trade good"* | D18 — 70 goods, 70 distinct glyphs, nine redrawn after failing at 22px |
| *"click a trade good then unfolding"* | D18 — asked twice before it was built |
| *"내 주방 separate tab but next the dishes"* | D18 — the galley face on FLEETS |
| *"do the migrations - price history, player row, officers, skills"* | 0013-0016 |
| *"yes add haggling mechanic"* | 0022, retuned in 0024 after shipping as a 0.36% rounding error |
| *"This game fleet will be comprised with 8 ships"* | 0021 — and it exposed three caps that no rule read |
| *"do 8, 9, 10"* (captains, buffs, the inert three) | 0025-0027 |

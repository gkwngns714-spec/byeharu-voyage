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

| 15 | *"when pressing sail, stop folding the sail. when pressing buy stop folding buy... don't restruct anything"* | **REOPENED — I built the OPPOSITE** | **Said three times.** Their first wording was *"the tab should be not unfolded. it should stay where it is"* and I read "not unfolded" as "collapse it". Backwards. **THE RULE: pressing a verb must not restructure the page AT ALL** - no collapse, no re-flow, no sticky sheet following the scroll. The six verb cards stay where they are and the chosen one is simply marked. Being reverted by DELETION, not behind a flag (NO_SPAGHETTI 5). This row is the ledger's own rule proving itself: a repeated instruction is a bug report about this file. |
| 16 | *"how many crew to hire, have it + 10, +100, max, make it more friendly"* | **DONE — verified** | MAX must be the smallest of berths free, the port's idle crew, and what the purse can pay - never a ceiling the server would then refuse. A step past the ceiling clamps, never goes dead. |
| 17 | *"and how many crew? show my ship info regrading crew, how many needs, min amount, max amount etc at the right"* | **DONE — verified** | Crew aboard, minimum to sail, maximum berths, port's idle crew. "At the right" is the desktop rail; at 390px the rail is written FIRST and appears above - deliberate, keep it. |
| 18 | *"15 days of stores is not clear, 4.9kn is what? 56 t free? lying at lisbon is duplicate... make it separate tab for all of them"* | **DONE — verified** | A bare unit with no label is half of UI_DIRECTION rule 2. "lying at Lisbon" is printed TWICE - the fleet chip above already says it; DELETE, do not relabel. |
| 19 | *"right now the sail, all the port is alligned by sentence. make it like a cube, and what is yard?"* | **PART DONE** | Harbour TILES, not sentences. Distance stays the server's sailed nm. "yard" = shipyard, jargon; some instances are server-authored and would need a migration like 0030 did for "hands".. Client done everywhere (COMMAND, PORT, LEDGER all say shipyard). One SERVED string remains - the REPAIR verb help at 0021:297 - queued as its own wording migration, same shape as 0030 did for hands. |
| 20 | *"when pressing a location to sail, dont unfold, instead make the what sail needs bottom by comming out unfoldingly, also, shown in map where i clicked"* | **DONE — verified** | A harbour tile has nothing to unfold INTO - tapping it should just choose. Sheet from the bottom so the grid stays put. **The Issue control must never live inside a region that can clip it.** Chart must ring the TAPPED port - it was built for hover/keyboard, and a phone has no hover. |
| 21 | *"the map in sail, i should be able to zoom, drag, move."* | **DONE — verified** | `SmallChart` now mounts the ONE gesture hook in an embedded posture (`useChartSurface` `scroll: 'page-vertical'`): drag pans, pinch zooms, and the Map tab's own +/−/find column rides the chart (`src/chart/ViewControls.tsx`, one component, both callers). The old inertness reason is ANSWERED, not ignored: no wheel listener is attached (the wheel scrolls the form) and `touch-pan-y` gives a one-finger vertical drag to the page — measured at 390×844: five finger-drags from the top of the open picker reach the Issue button 1,268 px below the fold, with the chart's viewBox byte-identical before and after. |
| 22 | *"i want you to categorize trade goods, common, uncommon, rare... make appropirate color or sign so that it is unique"* | **DONE — verified** | Rarity must be SERVED, authored or derived in ONE place - a client-side rule would drift between picker, compendium and market. Colour PLUS a non-colour channel, so it survives colourblindness and greyscale.. Landed as 0032, DERIVED from how many ports actually produce the good - not authored (a hand-set label would drift the moment the world grew from 12 to 214 ports, which already happened once) and not from price (every port trades every good here, so dear is not scarce - gold has 22 producers and is common; Venetian glassware has 1). exotic 6 / rare 20 / uncommon 22 / common 22. Every tier has a GLYPH as well as a colour; all four clear WCAG AA on the panel (6.06 to 9.00:1). |
| 23 | *"do all the work properly"* | STANDING | Do not silently narrow a request. If a slice is too big to do well, say which part to split out - half-doing five is worse than finishing three and naming the other two. |

| 24 | *"yes build set ratio but let me set it personally - adjust. Save it as preset. Give something like 6 presets"* + *"the ratio must account for number of crews as well"* + *"crew now, but show it clearly"* | **DONE — verified** | 0034. House-owned presets, cap 6 enforced by a TRIGGER on the table (so a future writer inherits it), a fleet holds a REFERENCE never a copy - proven by editing one preset and watching two fleets provision to the new figure with no re-apply. Fires on arrival only, inside voyage.settle's arrival arm, BEFORE the queue runs, so a queued onward SAIL departs provisioned. Sized from crew AT FIRE TIME: 5.04 t at 8 crew, 14.70 t at 20. Galley prints `keep Long haul - 30.0 days - at 8 crew`. |
| 25 | *"when pressing sail, stop folding the sail. when pressing buy stop folding buy... don't restruct anything"* | **DONE — verified** | Verb cards 6 to 6 to 6, identical pixel positions, scrollTop unchanged. Sticky sheet deleted. **Consequence measured and NOT hidden: Issue now sits 2,112px down, about 2.3 screens.** Offered a static fix (order line and Issue near the top, never moving); owner has not answered. |
| 26 | *"what moves the price -> price movement... Why add unnecessary words?"* + *"stores last -> provision"* + *"cargo space or cargo, and 0T/54T - 0%"* | **DONE — verified** | Whole-screen label cut. Cargo now `4 / 60 t - 7% full`. A few fragments kept with reasons (`first ten at` cut to "cost" would leave the number ambiguous about what it prices). Fixed one figure carrying THREE names across the game - endurance / range / provision - now provision everywhere. |
| 27 | *"use worktrees from now on"* | **STANDING** | **Said twice** - the rule was already in memory and I ran six agents in one clone anyway, which twice let a half-written migration take down every other agent's verification. Verified recipe recorded: `git worktree add` + an `mklink /J` junction for node_modules, so no npm install is needed. Every dispatch from now gets one. |

| 28 | *"i told you to not recreate anything when pressing a certain tab... how many times do i have to say this simple thing?"* | **DONE — verified** | **Said FOUR times, and the first two I built BACKWARDS.** Now measured, so it is no longer a guess: after tapping BUY there are **140 price cells and a filter box**; after tapping one price cell there are **0 and none** - the whole goods list is unmounted and replaced. THE RULE: a control SELECTS; it never replaces, collapses, re-flows or destroys the surface it was pressed on. Fixing at the MODEL level if the argument rows all swap this way, not per-verb. |
| 29 | *"what is max 12 in hire? just max is enough"* | **DONE — verified** | The figure is noise - the chip already means "as many as possible" and the number is on the rail beside it. |
| 30 | *"in provision, full and days, they does not have to be folded"* | **DONE — verified** | Same rule as 28. |
| 31 | *"find button on map, sail, it is not correct. have a symbol instead"* | **DONE — verified** | `+` and `-` are symbols, `find` is a word among them. Needs a glyph AND an accessible name - an icon nobody can name is worse than a word. One component serves both Map and SAIL. |
| 32 | *"when i press corfu or dubrovnik... the map does not move to that location. make it move - pinpoint"* | **DONE — verified** | The ring is drawn off-screen, so the chart says "marked" and shows nothing. **This is not a no-restructure violation** - only the viewBox moves; nothing appears, vanishes or resizes. |
| 33 | *"overall, check game itself - every aspect, and move simple words"* | **DONE — verified** | Whole-game plain-language sweep plus an audit. Served strings collected for a migration rather than glossed client-side. |
| 34 | *"make trade goods in blocks as well, not all alligned in sentences - horizontally"* | **DONE — verified** | "as well" = like the SAIL harbour tiles they liked. MARKET first; the tile goes somewhere SHARED because the command picker is certainly the second caller. |
| 35 | *"read again on top left of the game is useless. remove it"* | **DONE — verified** | Correct: the world re-reads every 30 s and on tab focus, so the button asks for what is already happening. Deleting it must NOT delete the screen-specific read behind it. |
| 36 | *"do the work properly. do the work all. do not leave anything behind. double check. always work with rules."* | STANDING | Every row above must be MEASURED, not glanced at, and "double check" means a second method - not the same look twice. Both agents told to say which items they measured and which they only eyeballed. |

| 37 | *"why are there only 70 trade goods? there should be thousand. real-life trading by regions + 대항해시대 오리진 + 대항해시대"*| IN PROGRESS | Measured the collision first: 214 ports x ~6.5 offers = ~1,400 slots, so 1,000 goods averages 1.4 offering ports each. Works ONLY because a port OFFERS 4-9 but BUYS anything - exotics being single-source is the point. Agent must report the offer histogram and check the 0032 rarity tiers still mean something (a catalogue that is 80% exotic has no tiers). |
| 38 | *"each cities max 9 trade goods... Min 4, max 9. Add real islands... JEJU island might have korean gochujang"* | IN PROGRESS | Tier already ranks city size (1:35, 2:79, 3:100 ports) - use it, do not invent a second axis. Islands need REAL coordinates and, critically, **reachability**: a port no sea route reaches is a port nobody can sail to. That is the most likely way this ships broken. |
| 39 | *"in map - make a small miniturized map at the corner of the map, that shows where my fleets are in color + symbol"* | IN PROGRESS | A minimap must not become a second chart - the chart layer has one entrance and one camera. |
| 40 | *"this game might need OSN system as well as other system built in byeharu, the previous game. audit and implement it so that later on, combat, exploration, npcs can be added"* | IN PROGRESS | Architecture, not a feature. Audit dev/byeharu's OSN and zone platform, then lay the FOUNDATION - the seams combat/exploration/NPCs will need - without building those systems now. Half a foundation is worse than none. |

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
| `layout.spec` could pass while measuring NOTHING | **FIXED 2026-08-23.** Point `PLAYWRIGHT_BASE_URL` at a bare host and vite preview answers with its own "did you mean" page - no tables, no tiles, no skeletons - so `ready()` resolved and all 8 tests went green having measured a 404 helper. A non-vacuity guard now requires the screen to have rendered something; break-tested against a bare host and it fails with the reason. |
| ~~`db.chain` rebuild spec times out under parallel load~~ FIXED | Passes alone in 1.9 min; it rebuilds the whole world twice and gets slower with every migration added. At 34 it is close to the line. Needs its own timeout or a lighter fixture before it fails for real. |
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

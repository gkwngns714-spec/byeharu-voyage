# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

---

## 2026-08-20 — D11h: the four left undone, done

Owner: *"don't leave out. do all."* So all four, each proved in a browser rather than reasoned about.

### 1. The drift flake, explained rather than suppressed

0010's assert read ONE row (Lisboa x Salt) before and after a drift tick and required it to change.
`port_goods.drift` is `numeric(6,4)`, so an OU step under 0.00005 rounds to no change — from a
zeroed drift, a perfectly ordinary draw. **The assert was a lottery on one row.**

Measured, now that it counts: **14,967 of 14,980 rows move; 13 round away.** That is 0.087%, so the
old single-row assert had roughly a **1-in-1,150 chance of failing any boot it ran in** — which is
exactly "seen once, never reproduced in 8 tries".

The claim is now measured where it lives: the tick promises to step every row, and a stepped market
is one that has MOVED. It requires 90% and gets 99.91%, and the receipt prints the count so a
regression shows instead of hiding.

### 2. %NBR was sixth, and fell off the right edge

The column the entire game turns on — this port's price against what its neighbours pay — was the
one you had to swipe to see, while `131` and `139`, which mean nothing on their own, sat in plain
view. **It is second now**, immediately behind the sticky good name, which is the last position
guaranteed to be on screen at 390px without scrolling.

Measured in the browser: `GOOD | %NBR | BUY | SELL | STOCK | NOTE`, second cell `83%`,
`fullyVisible: true`. The prices did not get less important; they got less urgent.

### 3. The queue trap now says so, while it can still be cancelled

A SELL queued behind a SAIL home is a guaranteed loss the ledger tells you about afterwards. A queue
is first-in-first-out and cannot be reordered, so the fix is to say WHERE a trade will happen:

    [2] SAIL Gaivota TO LIS                    PENDING
    [3] BUY salt ALL      after she sails      PENDING

It reads the server's own parsed `verb` and nothing else. Writing a client-side parser for the order
line — when F.4 says there is exactly one parser and it is on the server — would have been a worse
bug than the one being fixed.

### 4. A half-made order survives a reload

Composing an order is four or five deliberate taps through pickers, and a refresh threw them away
with no trace. The draft persists to **sessionStorage**, not local: a draft is a thing you are
doing, not a thing you keep, so tomorrow opens on a clean composer instead of resurrecting an order
aimed at a fleet that has since sailed, sold and come home.

`handoffs` is deliberately NOT persisted — it is the nudge that scrolls the composer into view when
another tab hands an order over, and restoring it would scroll on a plain reload as though a
hand-off had just happened. **Persist the order; never persist the reaction to it.** A corrupt byte
opens a clean composer rather than wedging the tab.

Proved: `SAIL Gaivota` on screen, reload, `SAIL Gaivota` still on screen.

### The whole suite, green

**149 passed, 0 skipped, 0 failed** — the first fully-green run of the day, including all 12 layout
tests and the fold test that had been red since before this session started. `db:proof` 31/31.

**One consequence to record:** editing 0010's self-assert changes the chain fingerprint, so any
browser still in LOCAL mode rebuilds its world once. Cloud mode has been the default since D11e, so
this is now a note rather than a loss. The live server is unaffected — `db push --dry-run` reports
*"Remote database is up to date"*, and a recorded migration is never re-applied. As with 0012, the
deployed copy of 0010 carries the older assert text; no schema or behaviour differs.

---

## 2026-08-20 — D11g: the three defects the playtest found, fixed

Owner: *"fix and do what is necessary."* So: the catalogue from D11's playtest, not new work.

### 1. The first tap a new player made was already refused

Tapping a good on MARKET handed the order to Command prefilled with the FREE HOLD — which ignores
the purse. The preview refused it instantly: *"60 tuns of Black Pepper cost 8020 d. and you hold
8000"*. Twenty ducats over, on a screen they had not touched yet.

It was the **third copy** of the rule D10 was written to kill (*"two places computing a maximum,
both ignoring the price"*). D10 fixed the MAX chip and `cmd.resolve_qty` and this one survived
because nothing pointed at it.

**The fix deletes the copy rather than correcting it.** Both sides now hand over `ALL`, and the
client computes no maximum at all: buy-side `ALL` resolves server-side through
`public.fleet_buy_capacity()`, which walks the same stepped book a committed trade walks and stops
at whichever of hold, stock, daily cap or **purse** binds first. `ALL` is read when the order RUNS,
so it survives a voyage that changed the hold.

### 2. She was "lying at" a port she was still sailing towards

The COMMAND summary read *"…56 t free · lying at Cadiz"* while the panel directly below it read
*"at sea → Cadiz, 84 nm of 248 nm"*. Same fact, two sentences, one of them false. `port` there is
where the order will TRADE — where she lies, or where she is bound if she is at sea (F.2) — and it
was printed as "lying at" either way. It now says **bound for** when she is SAILING.

### 3. A proof that had been red since before today

`MARKET puts a complete price row above the fold` failed with *"only 0 complete price rows above the
fold at 731px"*. Not a layout defect: `waitForLoadState('networkidle')` fires when the bundle has
downloaded, and the chain applies **inside the browser** for seconds after that — so the test was
measuring the loading skeleton, honestly and uselessly.

The first fix was wrong and the suite said so: waiting for a table row timed out on COMMAND, which
has no table. **Ready is the absence of the two things loading looks like**, and both are
design-system-wide: `Skeleton` is the ONE placeholder (`animate-pulse`), and *"Opening the world"*
is the one sentence every screen prints while the chain applies.

All 12 layout tests green, including the fold test, measuring the real screen.

### And a guard the deployment made necessary

With `.env.local` present the app is in cloud mode and every route redirects to `/auth`, where there
is no table to measure. That is the wrong BUILD, not a layout failure, so the spec now **skips with
the reason and the fix** instead of failing confusingly — proved by running it both ways: 12 passed
on a local build, 6 skipped on a cloud one.

`db:proof` 31/31 · `playwright` 143 passed · tsc + eslint clean.

### Left undone, deliberately

* **%NBR is still cut off at 390px** — the column the game turns on. It needs the layout change the
  redesign canvas draws, not a patch.
* **The queue is still FIFO with no reorder and no warning** when "sail home" is queued ahead of
  "sell". Design work, not a fix.
* **A half-composed order still dies on a reload** (the draft is in-memory).
* **0010's drift self-assert flake** — seen once, never reproduced, still not understood.

---

## 2026-08-20 — D11f: sections, and the clock that runs in one of them

Owner: *"do the next thing, but again, no spaghetti with others. What you've created so far,
organize them separately and independently so that individual have its own separate section …
ships, stats, skills, trade goods … prices, buffs, fleet, captains, location."*

### The spaghetti was real, and it was measurable

Nine imports had one SCREEN reaching into another screen's internals:

    port/PortScreen      -> command/commandDraft, command/orderText, fleets/worldGate, fleets/fleetDerive
    fleets/FleetsScreen  -> command/commandDraft
    market/handOff       -> command/commandDraft
    ledger/LedgerScreen  -> fleets/worldGate

None of it was bad code. Every one was a screen borrowing something that was never the lender's:
**"how much hold is free" is a property of a fleet, not of the tab that draws one.**

The clearest tell was `market/handOff.ts`, whose own header explained that it existed as an adapter
because *"commandDraft.ts is owned by the CMD tab"*. **An adapter that exists only to survive a
boundary is a sign the boundary is in the wrong place.** It still exists as a named intent; it is no
longer a border crossing.

### Two sections, by pure move

    src/domain/order/   draft.ts · text.ts · handOff.ts   the order language and the order being made
    src/domain/fleet/   derive.ts                          hold, crew, stores, cargo, hull, draught
    src/live/WorldGate  (was features/fleets/worldGate)    world loading + failure chrome

Each has one entrance (`index.ts`). Both are pure — no React, no store, no screen — and **neither
decides anything**: the server owns every rule, and these only read what a served payload says.

Cross-screen imports today: **zero**.

### The rule has teeth now

`tests/sections.spec.ts` reads the import graph off disk and fails on three things: a screen
importing another screen, a domain reaching up into a screen or the shell, and anything reaching
past a section's entrance into its internals.

**It was proved to bite before it was trusted** — a cross-screen import was added on purpose and the
spec failed, naming the exact crossing, then went green when it was removed. A boundary test that
has never failed is decoration.

`docs/SECTIONS.md` is the map: which section owns which concept today, and — for the ones the owner
named that do not exist yet — where they land. Skills, buffs and officers each get their **own
migration**, never a column bolted onto `players` because that table was nearest. The row worth
guarding is `stats`: a stats table that anything may write is not a section, it is the place
sections go to tangle.

**The server is not reorganised, and that is deliberate.** The chain is deployed; re-cutting
0001–0012 would desync `schema_migrations` on the live project and destroy every player's world to
gain a filing improvement. Existing migrations stand. New concepts get new files.

### The next thing: 0012, the clock is wound

0010 owns what a tick DOES. **0012 owns only when it runs.** Two files, two questions, no overlap —
the pattern the rest of the game should copy.

The cadence is **derived, not restated**: `drift_slot_seconds` (0010) already answers "how often does
the market step", so writing `*/10 * * * *` here would be a second answer, and the day somebody
retunes the knob the cron would keep the old rhythm. `public.tick_cron_expression()` computes it,
and the self-assert proves the crontab and the knob agree.

    arrivals    * * * * *      every minute — a voyage-day is three real minutes
    drift       */10 * * * *   from drift_slot_seconds = 600, not from a literal
    reconcile   7 * * * *      hourly and OFF the hour, so the audit never lands on the writers

Positive controls that bite: a 30-second slot and a 35-minute slot are both REFUSED, not rounded.
And under PGlite, where pg_cron cannot exist, it applies cleanly, schedules nothing, and **says so**
rather than pretending.

### Proved running, not merely scheduled

    jobname                   schedule        active
    byeharu-voyage:arrivals   * * * * *       true
    byeharu-voyage:drift      */10 * * * *    true
    byeharu-voyage:reconcile  7 * * * *       true

    cron.job_run_details: arrivals succeeded at 06:48:00 and again at 06:49:00

**The world breathes on its own now.** Market drift and stock regeneration run whether anyone is
looking or not — which is what makes a shared economy shared.

`db:apply` 12/12 receipts · `db:proof` 31/31 · `playwright` 143 passed · tsc + eslint clean. Three
test pins moved deliberately (last migration, its sentence, the receipt count).

### One honest discrepancy

0012 was pushed to the live server, and THEN two cosmetic edits were made to the file: the
no-scheduler receipt was reworded to match the `self-assert ok:` contract the chain's non-vacuity
floor requires, and a no-op `for` loop was deleted. Supabase will not re-apply an already-recorded
migration, so **the deployed copy carries the older text**. There is no schema or behaviour
difference — a NOTICE string and dead code — and the three jobs on the server are the correct ones,
verified above. It is recorded here rather than quietly left.

---

## 2026-08-20 — D11e: the game went online

Owner: *"can you just delete everything of aqua chronicles, and overwrite this?"*

### What was destroyed, and what was looked at first

`aqua-chronicles` held one of the account's two free Supabase slots. Before deleting anything:

| | |
|---|---|
| status | `ACTIVE_HEALTHY`, Seoul, Postgres 17 |
| last commit | **2026-06-16** — two months dead, the day byeharu began |
| data | 8 players, 5 ships, 3 teams |
| accounts | 8 — and **7 were test accounts** (`cooptest_`, `cargo_e2e_`, `repro_`, `claudedebug_`) |

So: a dormant dev database holding the owner's own two emails and six robots. Every row of it was
exported to `Desktop/aqua-chronicles/_final_db_export_20260820/` first, and the 293 migrations that
built it were never at risk — they are in the repo. Then the project was deleted. **That is
irreversible and the export is the only copy.**

### byeharu-voyage is now a real server

    project   byeharu-voyage · olaquvizoavjeiricyxk · ap-northeast-2 (Seoul)
    chain     11 migrations pushed, 11 self-assert receipts GREEN on real Supabase
    schemas   world, cmd, voyage exposed to PostgREST
    world     214 ports · 782 legs · 14,980 prices · 0 client write grants

0001's grant lockdown found what only a real project has: **16 default-ACL entries owned by
`supabase_admin`** that cannot be revoked from the migration role. It printed them, proved every
object in the four schemas is owned by `postgres`, and passed — the exact scenario D8 wrote the
Supabase-shaped preamble for, now confirmed against the real thing rather than a fixture.

### The proof, end to end, in a browser

    1. sign-in       -> /command   [rpc] cloud: Supabase project, PostgREST, schemas world/cmd
    2. no house      -> THE REGISTER · "Sign the book"
    3. signed        -> 8,000 d. · Gaivota · lying at Lisbon · 15.0 d of stores · 56 t free
    4. FLEETS        -> 1/2 fleets · 1/4 ships · Gaivota DOCKED at Lisbon · Barca

A `cmd.found_house()` call over PostgREST returned `{"ok": true, ...}`, and a second one returned
`E_ALREADY_FOUNDED` — **the positive control biting in production**, not in a fixture.

### The screen that had to exist first

`src/features/found/SignTheBook.tsx`. Local mode founds its captain during boot, so nobody had ever
needed one; on a real project a new account owns nothing and every tab is an empty shell. The
register now REPLACES the tab content until the book is signed (`AppShell.tsx`) — there is nothing
to navigate around and nothing to misread as broken. It appears only when the world is `ready` and
the fleet list is empty, because "still opening" and "failed" are also empty and are not the same
state; local mode never sees it.

**It validates nothing.** `public.players` already carries `unique` and
`check (length(btrim(company_name)) between 3 and 24)`, and 0011 turns each into a refusal with a
sentence. A length check in the form would be a second authority that drifts the first time the
constraint moves. The button asks, and prints what comes back.

### Two mistakes made along the way, both corrected

**1. The auth config was pushed when I had declined it.** `supabase config push` prompts per
service; piping `y\nn\n…` answered the API prompt correctly and then did *not* hold for auth —
remote auth silently took the local file's values, changing `site_url` from `localhost:3000` to
`127.0.0.1:3000` and turning MFA enrolment off. No users existed and nothing broke, but it was not
an intended change. Corrected deliberately: `site_url` is now
`http://localhost:5173/byeharu-voyage/` (where the game actually runs), the Pages URL is in
`additional_redirect_urls` for when it exists, and MFA is back on. Verified by re-diffing until all
four services reported *up to date*.

**2. I called a 42501 a defect before reading the grant.** `world.snapshot()` over PostgREST
returned *"permission denied for schema world"* and the first instinct was written down as a bug
only a live deployment could find. It is not a bug: 0001 line 223 grants `world` USAGE to
`authenticated` and `service_role` and deliberately **not** to `anon`. The call was made with an
anonymous key. Signed in, it returns 200 and the whole world.

### Still not done

* **pg_cron is not scheduled.** 0010's receipt has said so on every apply and still does. Reads
  settle voyages (D.2) so the game plays, but market drift and stock regeneration never run.
* **The `.env.local` switch is total.** With it present the dev server is in cloud mode, and the
  local PGlite world — including any game played in this browser — is not what loads. Delete the
  file to go back.
* **One world, many captains** is now literally true and has never been under load.

---

## 2026-08-20 — D11d: cloud mode could never have worked, and the reason was one missing function

Owner: *"this is an online game... everything must be server controlled."*

### What is already server-controlled, and it is most of it

The RULES have never been anywhere but the server. Every verb is a SQL function; `cmd.preview()`
runs the real verb in a subtransaction and rolls it back, so the estimate and the commit cannot
disagree; the client-side validator (838 lines) was deleted in D5 because *"two authorities for 'is
this order legal' is exactly the duplication this project forbids"*. RLS is on all 19 tables with
**0 client write grants**, re-proved on every apply. The client renders and requests. It decides
nothing.

### What is not

**The database runs in the player's browser.** PGlite, one private world each — no shared economy,
no other captains, no server clock, and a save that lives or dies with one origin's IndexedDB
(D11c). `src/lib/rpc/init.ts` was built to flip this with one answer (`hasCloud`), and
`cloudBackend.ts` has said so since it was written: *"NOT PROVEN AGAINST A REAL PROJECT."*

### The hole that flip would have fallen into

Auditing the cloud path before deploying anything, rather than after:

    grep -rn "new_house" src/     ->  src/lib/db/localDb.ts, and nothing else

`public.new_house(p_auth_uid, name, nation)` founds the house, the 8,000 ducats, the Barca at
Lisboa. 0004 line 342 revokes it from `public, anon, authenticated` — **correctly and permanently**,
because it takes a uid as an argument, so a client that held it could found a house on somebody
else's account. Its only caller was the local engine's boot.

So: **sign in to a real project and you would land in an empty world.** No fleet, no purse, no
ledger, and nothing on any screen to press. Cloud mode has never been playable, and nothing would
have said so until a real player signed up.

### 0011 — `cmd.found_house(name, nation)`

Note what is *not* in that signature. **It takes no uid.** It reads `auth.uid()` itself, so the only
house a caller can found is their own — the security property is structural, not checked.

It also **restates no rule that already exists**. `public.players` already carries
`auth_uid uuid unique` and `company_name text not null unique check (length(btrim(...)) between 3
and 24)`. The function lets those constraints bite and translates the SQLSTATE into the refusal
vocabulary the client already speaks. Two authorities for "is this name legal" would drift; there is
one, and it is the constraint.

Five refusals, and the self-assert makes **four positive controls BITE** rather than asserting the
happy path alone:

| | |
|---|---|
| `E_NOT_SIGNED_IN` | an unsigned caller, before any house exists |
| `E_ALREADY_FOUNDED` | a second house on one account |
| `E_NAME_TAKEN` | a name already trading |
| `E_BAD_NAME` | a 1-character name |
| `E_NO_SUCH_NATION` | an unknown flag — carrying all 20 real ones as fixes |

and it asserts the grants OUTSIDE the rolled-back probe, because a revoke that never happened must
fail the migration rather than vanish with it: `anon` may **not** execute it (or a crawler founds
thousands), `authenticated` may (or nobody can sign the book at all). After the four refusals it
re-checks that the refused captain still has **no** house — a refusal that half-founded one would
leave a purse with no ledger behind it.

### Wired, and the vocabulary test earned its keep

`cmdFoundHouse` is one row in `src/lib/rpc/catalog.ts` — both backends are built from it, so the
local SQL and the PostgREST named-argument call cannot drift. Adding it turned
`rpc.surface.spec.ts` red, exactly as designed: the client's whole vocabulary is asserted by name
*"so that adding one is a deliberate edit here"*. The edit is made, and the comment beside it that
0011 invalidated (*"a browser must not be able to found a house"*) is corrected to the real rule —
`new_house(uid, …)` never, `found_house(name)` yes, and **the difference is the argument**.

`npm run db:apply` 11/11 receipts · `db:proof` 31/31 · `npx playwright test` 140 passed · tsc and
eslint clean. Three test pins moved deliberately (last-migration name, its sentence, the vocabulary
list).

### THE WALL, stated as a fact

**There is no Supabase project for byeharu-voyage, and one cannot be created on this account.**
`supabase projects list` returns exactly two, and the free tier allows two:

    aqua-chronicles   Northeast Asia (Seoul)       2026-05-24
    byeharu           Southeast Asia (Singapore)   2026-06-16

The one-time fix is the owner's and takes a minute in the dashboard: **pause `aqua-chronicles`**
(reversible, keeps the data) or **upgrade the org to Pro**. Nothing else is blocked by it — CI's
disposable-Supabase job proves the whole chain against real Supabase roles on every push, and it is
green on `4f598e6`.

### What still stands between a project and a shared world

Written down now so the day it exists is a checklist, not a discovery:

1. **Expose the schemas.** PostgREST serves `public` only by default; the API settings must add
   `world`, `cmd`, `voyage`. `cloudBackend.ts` has carried this note since it was written.
2. **Schedule the clock.** 0010's own receipt says *"pg_cron absent — the tick functions exist and
   are proven, but nothing schedules them here."* Reads still settle (D.2), so the game plays; but
   market drift and stock regeneration would never run.
3. **A screen to sign the book.** 0011 gives the server side; a signed-in captain with no house
   needs somewhere to type a name. Deliberately not built blind — it cannot be proven end-to-end
   without a project, and a founding screen that has never founded anything is not a screen.
4. **One world, many captains.** The moment the economy is shared, price impact stops being personal:
   `%NBR` and the stepped book start reflecting what other people bought this morning. That is the
   game working — and it is also the first thing that has ever needed load thinking.

---

## 2026-08-20 — D11c: I reset the owner's save, and the game never said a word

Owner: *"wait, i've bought something before and the currency went down. but after this load fix, it
was set back to original value."*

They are right, and it was my doing. **This is a regression I caused in D11b, and the save is gone.**

### What happened

D11b edited migration 0005 for speed. Editing ANY migration changes the chain fingerprint, and
`src/lib/db/localDb.ts` then does exactly what its own header has always promised:

> "if the build carries a different chain, the stored database is DEMOLISHED and rebuilt from
> migration 0001 — applying six new migrations on top of a four-migration database is how you get a
> schema that exists in no repository."

`demolish()` is `drop schema public cascade`. It takes the world **and the house standing in it** —
`players`, `fleets`, `ships`, `voyages`, `orders`, `events`, `ledger`. The purse went back to 8,000
because a brand-new house was founded on the rebuilt world.

That rule is right and it stays. Two things around it were not:

1. **It happened without a word.** `bootState` has carried a `rebuilt` flag since the day it was
   written, and `grep -rn "rebuilt" src --include=*.tsx` returned nothing outside `lib/db`: a fact
   computed and thrown away. A purse silently returning to its opening balance does not read as
   "the world was rebuilt", it reads as the game losing your money — which is how it was reported.
2. **It could not be undone.** Nothing was dumped first. `dumpDataDir`, `backup`, `restore`: no
   hits anywhere in `src/lib/db`.

And I told the owner *"your browser has the old chain cached, so your next load will rebuild once"*
without saying that a rebuild destroys the save. That sentence was the last chance to prevent this
and it did not carry the one fact that mattered.

### What is fixed

**`src/lib/db/rescue.ts`** — before `demolish()`, every row of the eight player tables is read out
and stashed in `localStorage` under `byeharu-voyage.rescued.v1`, with column names, keyed by the
fingerprint of the world it came from. It cannot throw: a missing table, an unreadable one, absent
or full storage all come back as a receipt, because this runs on the path to a rebuild the player
did not ask for and must never turn a wipe into a dead boot.

**`src/app/RebuildNotice.tsx`** — the game now says it. A standing panel (not a toast: losing a
voyage is not a thing to mention for four seconds and withdraw) that names what happened, how many
rows went, where the copy is, and why it is not put back automatically.

### What is NOT fixed, and why not pretending is the point

**The rescue does not replay the save into the new world.** Every world row is keyed by
`gen_random_uuid()`, so a rebuild gives every port, good and ship class a NEW id.
`fleets.port_id`, `voyages.from_port_id`, `ships.class_id` and a cargo row's `good_id` all point at
uuids that no longer exist. A replay has to translate each one back through its stable code
(`ports.code`, `goods.code`, `ship_classes.name`) and prove the destination table still has the same
shape. That is a real piece of work with its own proofs. THE DATA HAD TO SURVIVE BEFORE ANYTHING
COULD RESTORE IT, and that half is what shipped today.

**The owner's lost voyage is not recoverable.** It was demolished before any of this existed.

### Proved on the real path, not asserted

A Playwright run that plays the game rather than mocking it:

    1. purse after a real PROVISION : 7,925        (issued through the Command tab, 8,000 -> 7,925)
    2. migration edited (fingerprint now differs)
    3. purse after the rebuild      : (fresh house)
    4. rescued from localStorage    : {"rows":8,"tables":["players","fleets","ships","orders",
                                       "events","ledger"],"ducats":7925}
    5. notice shown to the player   : true
    6. console                      : [db] THE CHAIN HAS CHANGED ... | [db] RESCUED 8 of your
                                      row(s) from 6 table(s) before demolishing

`players.ducats = 7925` — the exact figure that was silently lost this morning is now on disk before
the demolition starts. tsc, eslint clean; `npx playwright test` 137 passed.

### Observed once and NOT explained: 0010's drift self-assert

During the proof run one boot printed:

    [db] BOOT FAILED — demolishing the half-built world and trying once from empty
    MIGRATION FAILED: 20260818000010_the_clock_ticks_for_everyone.sql
    0010 self-assert FAIL: tick_market_drift did not step all 14980 rows
    ({"drifted": 14980, "slot": 2978652, ...}), or the drift did not move (0.0000 -> 0.0000)

`drifted: 14980` shows every row WAS stepped, so it is the second clause that bit: the assert reads
one specific row (Lisboa x Salt) before and after a drift tick and requires the value to change.
`port_goods.drift` is `numeric(6,4)`, so an OU step under 0.00005 rounds to no change at all.

The boot's own one-shot retry recovered it and the game came up. I could not reproduce it: **0
failures in 8 full chain applications** — but that is WEAK EVIDENCE and should not be read as
"rare". `drift_slot_seconds` is 600, so eight runs inside two minutes sampled one or two draws, not
eight. NOT INVESTIGATED FURTHER, NOT FIXED, and not caused by D11b as far as I can tell (the D11b
rewrite was proved to produce bit-identical `port_goods`). It is written down here because it was
seen, not because it is understood.

---

## 2026-08-20 — D11b: the first load took 37 seconds, and 13 of them were one INSERT

Owner: *"the first loading takes quite a long time, why?"* Measured before answering, in a real
browser at 390x844, with every non-localhost request blocked at the network layer:

| | to a rendered PORT screen |
|---|---|
| cold — first ever visit | **37.1 s** |
| warm — second visit, same profile | 3.5 s |

The console said where it went: *"chain applied: 10 migration(s) in 34194 ms"*. **The chain is not
applied on a server. It runs in the browser, in PGlite, once per player.** A cold load downloads
15.6 MB of WebAssembly PostgreSQL (`pglite.wasm` 9.62 MB + `pglite.data` 6.00 MB) and then applies
all ten migrations for real inside it — self-asserts included. A warm load is 3.5 s because
`bootState` reuses the stored world: *"reusing the stored world: 10 migration(s)"*.

Per migration, timed on this machine:

| migration | ms | share |
|---|---|---|
| 0005 every price is derived, never stored | 16 049 | **69%** |
| 0010 the clock ticks for everyone | 4 087 | 18% |
| 0009 the world reads back | 2 643 | 11% |
| the other seven | 508 | 2% |

Split 0005 at its own SELF-ASSERT banner: the proof was 2.5 s and the **seed was 13.1 s**. It was
not the proof. It was one INSERT.

### Which half of the seed, measured rather than guessed

    as shipped (world.affinity_for() per row)                 12.4 s
    knobs read once, distance still per (port, good)          10.2 s
    knobs once + the nearest source as one set-based pass     10.0 s
  * knobs once + a port x source-port distance matrix          3.8 s

The config knobs were never the cost. **The distance was.** Asked per (port, good), the
nearest-source subquery evaluates the great circle once per specialty row of that good: 214 ports x
834 specialty rows = **178,476 haversines**. But a distance does not depend on the GOOD at all.
Computed once per (port, source-port) pair it is 214 x 214 = **45,796**, and the per-good answer is
a `min` over that matrix through the authored fact. Nearly 4x fewer; 3.3x faster on the clock.

(`public.wc_num` is `security definer`, so PostgreSQL can never inline it — the five knobs per row
were ~150,000 function invocations. Real, and the smaller half: 2.2 s of the 12.4.)

### The fix, without a second economy

0005's own comment warned that *"a formula that lived only inside an INSERT could not be re-run
without copying it, and a copied formula is how two economies get born."* That law stands, so the
set-based seed does **not** restate the formula. The formula was extracted instead:

- **`world.affinity_at(is_producer, nearest_nm, producer, home, span, reach, curve)`** — the
  arithmetic and nothing else. Every input is an argument, so it is `immutable` with no
  `security definer`, which is exactly what lets PostgreSQL inline it. 14,980 calls now cost nothing.
- **`world.affinity_for(port, good)`** — unchanged signature, still the shape the balance tuner and
  any re-derivation ask for. It reads the knobs, finds the nearest source, and defers.
- **the seed** — knobs in a CTE, the port x source-port distance matrix in a second CTE, then the
  same `world.affinity_at()`.

One formula. Two callers. Neither restates it.

### Proved identical, not assumed identical

The whole chain was applied before and after and all 14,980 `port_goods` rows — affinity, stock,
stock_target, production_rate, ordered by port and good — hashed:

    before  sha256 328de64e8c263b835f38ec2ab1846d84ca1f208a97d7d59018448d96aba5d0ef
    after   sha256 328de64e8c263b835f38ec2ab1846d84ca1f208a97d7d59018448d96aba5d0ef

`npm run db:proof` 31/31 PASS, including `BALANCE_MEDIAN_IN_BAND` (median first voyage 7.4%, band
4.0-16.0) and `BALANCE_DISTANCE_PAYS`. `npx playwright test` 137 passed. tsc and eslint clean.

### Result

| | before | after |
|---|---|---|
| migration 0005 | 16.0 s | **7.9 s** |
| whole chain (node) | 23.3 s | **15.3 s** |
| chain in the browser | 34.2 s | **15.0 s** |
| **cold first load** | **37.1 s** | **17.6 s** |
| warm load | 3.5 s | 3.3 s |

### And the answer to the question before it

The game needs **no internet**. Both boot runs above ran with every non-localhost request aborted at
the network layer: **0 external requests**, game fully playable. No Supabase (`hasCloud` is false
with no `.env.local`, so `initRpc()` picks the local PGlite engine), no CDN, fonts self-hosted via
`@fontsource` and bundled. Only `npm install` and `git push` need the network.

Still on the table, not done: 0010 (4.1 s) and 0009 (2.6 s) are now 43% of the chain between them,
and the 15.6 MB PGlite payload is a one-time download that would dominate a first visit over a real
network rather than over localhost.

---

## 2026-08-20 — D11: too many words, so the words went behind a dot

Owner, looking at the running game: *"too much word. Make icons, make them tappable, then show info
explaining."*

### What was measured, before anything was changed

Every tab screenshotted at 390x844, full page, and its visible text counted:

| tab | words |
|---|---|
| PORT | 713 |
| MARKET | 766 |
| FLEETS | 235 |
| COMMAND | 194 |
| LEDGER | 106 |

The top of PORT was three numbers wearing seventy words of footnote — `Market tax 3.0%` followed by
*"set by the Mayor, banded 0–8%. Tax relief is not in the V0 chain, so what you pay is what is
printed."*, then `Spread 2.6%` followed by another. Every figure in the game came with a permanent
paragraph defending it.

The prose was not wrong. It is what makes the game legible the first time you meet it, and it is
worthless on the two-hundredth reading — by which point it is the thing standing between the player
and the number.

### The one authority: `Explain`

`src/components/ui/Explain.tsx` (+ `explainState.ts` for the hook, the same split
Collapsible/collapsibleState already uses). An `ExplainDot` — a real inline `<button>` carrying the
`info` glyph, `aria-expanded` + `aria-controls` — and an `ExplainPanel` that mounts only while open.
`<Explain>` wires the pair for the common case; PageHeader and CardHeader compose the parts because
their dot rides the heading and their panel drops below it.

Where the line falls against the fold we already had, written into the file:

- **Collapsible** — folds content the player came for. Full-width header, persisted, open by default.
- **Explain** — folds the standing explanation *of* content. Inline dot, ephemeral, always closed.

**IT DRAWS AT 28px AND IS TAPPED AT 44px.** `navTabs.ts` sets this app's floor at 44px; a dot that
cleared it visually would be a blot beside a 13px figure, and there are eleven on PORT. So the
circle is 28×28 and the hit area is an invisible `::before` inflated 8px on every side. It also
carries `z-20`, and that is part of the target rather than decoration: measured on FLEETS, the
sticky table header (`z-10`, tableLayout.ts) took the bottom half of the Ships dot and left a 44×22.

The panel is a `<span class="block">`, not a `<div>`: it opens inside `<p>`, inside `<h3>` and inside
`<dd>`, and a div is invalid in the first two. React said so out loud until it was a span.

### The prop that was carrying two different things

`subtitle` was doing two jobs, and only one of them belonged on the screen by default:

    Port · Lisbon                              Fleets
    Portugal · latin · North Atlantic Ocean    What you own, and the state it is in.
    ^ LIVE — the harbour you are reading       ^ STANDING — true on every visit, forever

So `PageHeader` and `CardHeader` now take **both**: `subtitle` stays printed (live subject, status,
or the disclosure of a tap affordance the player could not otherwise find), and `explain` goes
behind the dot. Each of the 25 call sites was sorted by hand rather than by rule.

### What may never go behind a dot

Written into Explain.tsx so it survives the next sweep: live data, a refusal sentence and its fixes,
and any hint disclosing an affordance that is otherwise invisible. `TABLE_SCROLL_HINT` ("Swipe the
table sideways…") and "Tap a fleet to command it." are still printed, on purpose — hiding those is
hiding the game, not tidying it.

### After

| tab | before | after |
|---|---|---|
| PORT | 713 | 557 |
| MARKET | 766 | 623 |
| FLEETS | 235 | **123** |
| COMMAND | 194 | **122** |
| LEDGER | 106 | 98 |

PORT and MARKET stay high because most of what remains is *data* — 70 priced goods, 214 port chips —
which is the screen doing its job. The prose walls are gone from all five.

### Proved in a browser, not asserted

A Playwright pass at 390×844 walks **every dot on every tab**: 25 dots, 25 opened and showed real
text and closed again, 0 failures. All 25 clear 44×44 at all four corners (`elementFromPoint` at
centre ±21px). No page ever scrolls sideways (390/390). Zero console errors — the invalid-nesting
warning that the first draft produced is gone.

`tsc -b` and `eslint .` clean; `npx playwright test` 137 passed / 6 skipped; `layout.spec.ts`
11 passed.

**Pre-existing red, NOT caused by this work:** `MARKET puts a complete price row above the fold`
fails with *"only 0 complete price rows above the fold at 731px"*. Verified by stashing this change,
rebuilding and re-running: `main` fails identically. The failure screenshot shows the page still on
"Opening the world." — `waitForLoadState('networkidle')` returns long before PGlite has applied the
chain (~15s), so the test measures a skeleton. It is a harness timing gap, not a layout defect.

**Also noted, environment:** `vite preview` binds `[::1]` only on this machine, while
playwright.config.ts defaults to `127.0.0.1` — the layout specs silently SKIP unless run with
`PLAYWRIGHT_BASE_URL=http://localhost:4173/byeharu-voyage/`.

---

## 2026-08-19 — D10: the picker that lied, and an economy that printed money

Two owner-reported defects, both found by looking at the running game rather than at a test.

### The MAX chip offered more than the purse could carry

The quantity picker's MAX read **91 tuns of pepper**; issuing it was refused with *"91 tuns of Black
Pepper cost 8130 d. and you hold 8000"*. The game contradicting its own control.

The client was dividing the purse by the market's opening ask — and `features/command/fleetLimits
.ts` said so in its own comment: *"a real BUY reprices as it walks the book (G.1), so the true
ceiling is a little lower."* A known-wrong number in a control that presents itself as exact.

**The same bug was in the server, and worse.** `cmd.resolve_qty` resolved buy-side `ALL` from the
FREE HOLD alone, so `BUY salt ALL` filled the hold and was then refused for want of money. Two
places computing a maximum, both ignoring the price.

One answer now: **`public.fleet_buy_capacity(fleet, good)`** walks down through `world.quote()` —
the same stepped quote a committed trade uses — and returns `{max_qty, est_total, bound_by}` where
`bound_by` is *hold* · *stock* · *daily cap* · *purse*. `ALL` means it, and `world.buy_capacity()`
serves it to the picker, which now reads:

> **MAX 50** — *up to 50 t — your purse stops you there (6,659 d. for all of it)*

Asserted at BOTH edges in 0007: affordable at the number offered, and NOT affordable one tun above
it. One edge alone would pass a function that always answered "one".

It steps down in trade steps until the last stretch, then **one tun at a time** — a pure ten-step
walk answers "0" for anything dearer than ~800 d./tun, and she can afford two diamonds.

### A first voyage returned a third of the stake

Measured across two dozen starting ports (`scripts/db/measure-first-voyage.mjs`, new): **median
33.7%, best 65.6%**, on round trips of about twenty-five real minutes. The purse doubled in two
voyages, before the player had seen the map. That is not a trading game.

The gradient was too steep between NEIGHBOURS: affinity ran 0.60 at a producer against up to 2.35 a
few hundred miles away, a price ratio near 2× for a leg you can sail in a coffee break.

The rule is now five knobs in `world_config` and ONE function, `world.affinity_for()`, which the
seed and the tuner both call — so a sweep cannot drift from the game:

```
prod 0.60 home 0.85 span 1.50 reach 6000 curve 1.00   median 32.3%   <- what shipped
prod 0.88 home 0.97 span 0.90 reach 8000 curve 0.70   median 11.5%
prod 0.90 home 0.98 span 0.88 reach 8000 curve 0.75   median  8.8%   <- chosen
prod 0.92 home 0.99 span 0.85 reach 9000 curve 0.80   median  6.0%
```

`scripts/db/tune-balance.mjs` (new) prints that table by re-deriving all 14,980 affinities per
candidate and replaying the best opening voyage. **Balance is a measurement now, not an opinion.**

What the chosen row buys, measured after the fact:

```
Barcelona    164 nm  coral         3.0%     Callao      1311 nm  cacao   12.8%
Antwerp      118 nm  diamonds      5.8%     Copenhagen  2004 nm  amber   13.3%
Bordeaux     500 nm  indigo        8.8%     Cartagena   1027 nm  diamonds 19.0%
```

**Distance is what pays** — which is the entire reason the world is 214 ports wide. The first
session proof now reads +9.41% on the stake.

`scripts/db/proofs/05_first_voyage_balance.sql` (new) holds all three claims: every sampled port
offers a voyage that pays, the median sits in a 4–16% band, and long legs out-earn short ones. If
it goes red, run the sweep and read the table — do not nudge a constant until the red goes away.

### Green

```
db:apply   10 migrations, 10 receipts     db:proof   5 files, 31/31 markers
playwright 137 passed / 6 skipped         tsc · eslint · vite build all clean
```

---

## 2026-08-19 — D9: the world became the real world, and three assumptions died with it

**The owner's correction, verbatim:** *"not typing, but making commands. i told you it will be
real world, not a imaginary places. wtf."*

Two separate defects, both mine, both structural rather than cosmetic.

### The world was twelve toy ports

`data/ports.json` has held **214 real harbours across 97 countries since day zero**, every
coordinate a Wikidata P625 item — and the chain seeded **twelve**, around Iberia. The owner opened
the game and saw a made-up world, because that is what was in the database. The data being right
in a JSON file nobody plays is not the world being right.

**Migration 0003 is now generated from the data**, by `scripts/build-world-seed.mjs`: 214 ports,
782 legs, 70 goods, 51 seas, 25 regions, 20 nations, 834 specialty rows — 115 KB of SQL that
applies in **0.1 s** and self-asserts every claim it makes. The generator's header states every
derivation rule (size tier, draft, yards, development, culture, which 1550 power held a port), so
the world can be re-derived rather than re-typed.

### The legs could not be authored, so they are DERIVED FROM THE SEA

Twenty-two hand-curated edges scaled to twelve ports. Twenty-two thousand candidate pairs do not.
The first attempt asked "does the straight line between these two ports stay at sea?" — and got a
world where **Lisbon and Cádiz had no leg at all**, because the straight line clips the Algarve.
That is the wrong question: ships round Cape St Vincent.

So `scripts/sea-grid.mjs` rasterises the Natural Earth land polygons into a **0.25° water grid**
and a route is an **A\* search through water cells**, straightened by line-of-sight. What comes out
is the real geography of the age, and nothing in the generator encodes any of it:

```
Lisbon → Cádiz          248 nm  (the straight line is 188; the cape is in the way)
Alexandria → Aden    10,944 nm  round the Cape — there is no Suez until 1869
Veracruz → Acapulco  10,860 nm  round the Horn — there is no Panama until 1914
Guam → Honolulu → Acapulco     the Manila galleon, appearing on its own as an ocean crossing
```

**782 legs, one connected world, mean sailed/straight ratio 1.16×.** Both canal controls are
printed on every run, because a generator that quietly starts digging Suez is worse than one that
fails. Fifteen named CHANNELS are authored — the Sound, the Bosphorus, Bab-el-Mandeb, Hormuz,
Malacca, the Cape road, Cape Horn, the St Lawrence — because those waters are narrower than the
map's own resolution; that list is the whole of the game's "you may pass here" authority.

### The prices could not be authored either

§G.1 calls affinity "the authored soul of the world", and with 12 ports it was a hand-typed
12×12 matrix. 214 × 70 is **14,980 cells**, and a hand-typed 14,980-cell matrix is not authorship,
it is noise nobody can check. So ONE editorial fact is authored — **which ports produce which
good**, in the new `public.port_specialties` table, sourced in `docs/WORLD_DATA.md` — and 0005
derives every affinity from it by one rule:

> a port that produces the good sells it at 0.60; everywhere else pays
> `0.85 + 1.50 × min(1, nearest source / 6000 nm)`.

That is the age of sail in one line: pepper is cheap in Malabar and dear in Lisbon because Lisbon
is nine thousand miles from the nearest vine, and the whole voyage exists to close that gap.

### THE ROUTER: 1,811 seconds → 0.1 seconds

`voyage.route_direct` enumerated every simple path and took the cheapest. Its own comment said why
that was fine: *"The V0 graph is 12 nodes and 22 undirected edges."* On 214 nodes of mean degree 7
it took **thirty minutes** — measured, in the apply log, not guessed. Replaced with Dijkstra
(O(n²) scan, edges laid out by source with a start index). Same answers, in milliseconds.

### THE HALT RULE WAS HALF-IMPLEMENTED, and a probe found it

§F.3 says a queue "halts at a failure — it never skips". `cmd.advance` did stop at a failure...
within one call. The next arrival called `advance()` again, found the failed order was no longer
`pending`, and ran the one behind it. That is skipping, on a delay. It surfaced as a queue reading
`[1:failed E_HOLD_FULL 2:done 3:pending 4:pending]` in a probe that was only meant to be checking
something else.

Fixed: a failed order now blocks the fleet until it is cleared — and `cmd.clear` was widened to
release it, because a halt with no release is the **empty-fleet deadlock** that cost the previous
game a live incident. Both halves are asserted, in the two files that own them.

### Every seed-shaped assertion in the chain, fixed in one pass

The rule from the previous project: *a test that asserts a seed asserts a WORLD.* The chain was
full of them, and the real world set them all off at once. They were rewritten to **assert the
rule and find their own subject**, never to name a cargo or a distance:

| was | is now |
|---|---|
| `port_goods rows = 144` | `= (count of ports) × (count of goods)` |
| `snapshot has 12 ports / 22 legs` | `= what the tables actually hold` |
| `tick_market_drift stepped 144 rows` | `= count(port_goods)` |
| "Lisboa→Cádiz is 188 nm, 1.6 days, 4.7 min" | days = nm/kn/24 and real = voyage/compression, on whatever leg the world has |
| "buy sal at Lisboa, sell at Cádiz" (0007, proof 4) | **find** the best one-leg trade a starter can afford, then play it |
| `"s" is ambiguous, naming Safi and Sevilla` | it refuses, says E_AMBIGUOUS, and lists more than one |

**Proof 4 — the product proof — now reads:** black pepper at Lisbon, 62.6% of its neighbours,
sold at Ponta Delgada 781 nm out, wheat carried home: **+2,763 ducats on a 7,925 stake, 34.9%**,
every order running unattended with no tick. (That return is high for an opening voyage; a
balance pass belongs on the list, and it is a balance question, not a correctness one.)

### Green, and what it costs

```
npm run db:apply    10 migrations, 10 self-assert receipts,  ~13 s
npm run db:proof    4 files, 28/28 PASS markers
```

The chain applies **in the browser on first boot**, so that 13 s is a real cost the player pays
once. 0010's drift soak came down from 15.1 s to 2.9 s by scoping the forced slots to a sample of
twenty ports and saying so out loud. 0005's remaining 7.9 s is 14,980 real `world.price()` calls —
the full sweep is kept deliberately, because "every price in the world is sane" is worth eight
seconds and a sampled version would not be the same claim.

### Still open from this entry

- **The Command tab is still a typing prompt.** The owner's first correction. Being rebuilt as a
  composer: pick fleet → verb → real options, previewed on the server, issued as the same string.
- The five screens are still on fixtures; `src/live/worldStore.ts` is the seam they move onto.
- Cold boot is ~15 s (2.2 s WASM + ~13 s chain). A prebuilt database image would remove almost all
  of it and is the obvious next optimisation.

---

## 2026-08-18 — D8: a blind local gate, and then an assert that could never pass

Two failures, one after the other, and the second is the more interesting one.

### Round 1 — the local gate was blind

CI's `disposable-chain` job — the one that boots a real Supabase in Docker — failed applying
migration **0001**, on 0001's own self-assert, three runs running (`8d1956e`, `27bcb58`, `0836c31`):

```
ERROR: 0001 self-assert FAIL: 16 default ACL entr(ies) would grant a client role a
       write/execute on future objects (SQLSTATE P0001)
```

`npm run db:apply` and `npm run db:proof` were **green on this machine** the whole time, because
`scripts/db/apply-chain.mjs` boots a **bare PGlite**: no `anon`, no `authenticated`, and **no
`ALTER DEFAULT PRIVILEGES` entries of any kind**. 0001's lockdown had nothing to revoke and its
assert had nothing to find. It passed **vacuously** — and so did every other grant / default-ACL /
role-dependent assert in the chain. A green run over an empty starting state is not a proof.

Fix: **`scripts/db/supabase-preamble.sql`**, a **test fixture, never a migration**, applied by
`apply-chain.mjs` before 0001. It creates the Supabase roles and installs the default privileges a
real project ships, **under a grantor that is not the role applying the chain** — which is the
entire mechanism. It lives in `scripts/`, so the Supabase CLI (which only reads
`supabase/migrations/`) cannot deploy it. The harness refuses to run without it, and refuses to run
if it stops printing its own receipt. With it in place, the unfixed 0001 failed locally with CI's
message character for character.

### Round 2 — the assert was over-broad, and unsatisfiable on the real thing

The first fix made 0001 revoke the defaults of **every grantor `pg_default_acl` names**. CI then
failed with the message that fix was written to produce (run `32122434872`):

```
ERROR: 0001: cannot clear the default privileges held by grantor supabase_admin in schema public
       (object type S). The role applying this migration is postgres, which is not a member of
       supabase_admin, so ALTER DEFAULT PRIVILEGES FOR ROLE is refused.
```

So the grantor was `supabase_admin` and **the revoke is genuinely impossible from the migration
role.** The assert as written could never pass on a real Supabase project.

**The assert was wrong.** Stated plainly, and argued before changing, because that is the rule.
The governing fact — verified by running it, not by reasoning about it:

> **A `pg_default_acl` row applies ONLY to objects created by its own grantor.**

Measured on PostgreSQL 18.3 with all 16 entries in place and 0001 §5a applied:

```
create table public.t_by_postgres        ->  owner postgres        relacl = null            (no client privilege)
create table public.t_by_supabase_admin  ->  owner supabase_admin  anon + authenticated get
                                             INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, SELECT
```

Same split for sequences and functions. `supabase_admin`'s defaults cannot reach an object this
game owns. The assert was demanding control over something the migration cannot control **and**
that does not threaten it — a permanently blocked deploy, which is really just sustained pressure
to delete the check.

**0001 restructured to assert what it can actually guarantee:**

* **(d)** — default ACLs **owned by the role applying the chain** are clean. Kept and narrowed to
  this; these are the ones that decide every object the chain creates. Real protection, unchanged
  in force.
* **(d2)** — foreign grantors' defaults are a permanent **`NOTICE` on every apply**, naming the
  grantor and object types. Never swallowed, never fatal.
* **(i) — NEW, and it is what pays for the narrowing.** Every table, sequence, view and function in
  all four schemas is **owned by the role applying the chain**, so none can have inherited a foreign
  grantor's defaults. That turns (d2)'s un-revokable entries from an unprovable claim into an
  irrelevant one, which is the honest position. Positive control: the same authority
  (`public.objects_not_owned_by()`) asked about a role that owns nothing must return rows — a
  control that needs no privileges, which matters because the migration role on Supabase is not a
  superuser and cannot manufacture a violation to test with.
* Proof 03 gained an **eighth marker**, `GRANT_LOCKDOWN_CHAIN_OWNS_EVERYTHING`, so the ownership law
  is checked at **end of chain** — and CI re-runs proof 03 against the disposable Supabase, which is
  the only place it meets the platform's real roles. The workflow also re-checks both claims with
  raw catalogue queries, independent of the chain's own authorities.

**§5b deliberately does not even attempt the foreign revoke.** It would succeed here (the harness
runs as a superuser) and fail there, putting the cheap gate and CI back on different code paths —
the original defect of this whole episode.

Nothing is deployed anywhere, so **0001 was amended in place; no 0011 patch.** Forward-only starts
when the chain goes live.

**A defect found by firing the error paths instead of trusting them.** Both new failure branches
were run deliberately on PGlite. The first raised `operator is not unique: text || "char"` instead
of its own message — `pg_default_acl.defaclobjtype` is `"char"` and needs an explicit `::text`. An
error path that has never been fired is not known to work.

### What this actually taught, which is subtler than round 1

Round 1's lesson was the obvious one: *CI catches a class of defect the local gate cannot see.*
Round 2's is sharper and worth more:

> **A local gate that models a hostile starting state can produce an assert that is unsatisfiable
> on the real thing.** The preamble was right to exist — without it the defect was invisible. Its
> first assert was wrong, because "reproduce the hostile state" is not the same as "reproduce what
> the migration role is *permitted to do about it*". PGlite runs as a superuser; Supabase's
> `postgres` is not one and is not a member of `supabase_admin`. A fixture that models the
> environment but not the **authority** will happily let you write a check that passes locally and
> can never pass in production.

The general rule this leaves behind: **assert the thing you own, and prove the thing you don't own
cannot reach you.** Not: assert that the platform is shaped the way you would have shaped it.

---

## 2026-08-18 — DAY ZERO: the pivot, and the founding decisions

**The owner's request, verbatim:**

> "since the combat system, visually and code-wise are not working properly. Therefore i want this
> game to turn into a wording, strategical game, where most of the game played on tabs and commands
> made on a separate tab, and i can follow where my fleets are through map - only visually see where
> it is going and where it is. It is going to be a new game, we will use byeharu core to make a new
> byeharu. This time you will have to make a world map, add real countries, cities, especially
> harbour - sea related cities. It is going to be uncharted island origin (mobile game), similar, but
> will have multiple ships (fleet) to be controlled, invest in cities, rank, etc."

### D1 — A new repository, not a branch of `byeharu`

`byeharu` is a **live multiplayer game** with real players on it and **333 applied migrations**
carrying a space-strategy schema, a spatial-combat engine, and a world editor. Grafting an
age-of-sail trading game onto that chain would be spaghetti by the owner's own law: two games, one
schema, one authority per concept violated on day one.

So: **`byeharu-voyage` is a new repository with a new migration chain that starts at 0001.**
`byeharu` is left running and untouched. What crosses over is the **core** — the stack, the shell,
the auth, and above all the *discipline* (server-authoritative RPCs, self-asserting migrations,
CI apply-proof) — not the schema and not the combat code.

Repo: `https://github.com/gkwngns714-spec/byeharu-voyage` (private).
Local: `C:\Users\디폴리스\byeharu-voyage`.

### D2 — The checkout is LF-only, from the first commit

`byeharu` was bitten by CRLF baking `\r` into sliced SQL so it could never match
`pg_get_functiondef` output, failing production deploys. This repo sets `core.autocrlf=false` and
ships a `.gitattributes` with `* text=auto eol=lf` / `*.sql text eol=lf` **before any SQL exists**,
so that class of bug cannot be born here.

### D3 — Combat is not "fixed later". It is designed out.

The visual combat layer is the thing that failed, visually and in code. This game has **no
battlefield**. Risk at sea (pirates, storms, disease) is a **server-resolved number** reported to
the player as a written after-action report on a log tab. There is no scene to render, so there is
no scene to break.

### D4 — The map is an output device

The map tab shows where fleets are and where they are heading. It **never accepts an order**.
All orders are composed on the Command tab. This is the owner's brief taken literally, and it is
also what makes the game cheap to build and impossible to break with a rendering bug.

### D5 — Database: unblocked, deliberately deferred

Verified on this machine (2026-08-18): the Supabase CLI at
`C:\Users\디폴리스\supabase-cli\supabase.exe` (v2.101.0) **is already authenticated** — it lists the
owner's `byeharu` and `aqua-chronicles` projects. So creating the new project needs no action from
the owner. It is deferred until the first migrations exist, so the project is created against a real
schema rather than an empty one.

There is **no Docker on this machine**, so `supabase start` cannot run locally. As in `byeharu`,
**the real migration chain is proven in GitHub Actions CI**, which does have Docker. That remains
the net.

### D6 — The migration chain runs LOCALLY, on real Postgres, with no Docker

`byeharu`'s single worst handicap is written into its own operating notes: *"SQL migrations can NOT be
run locally — no Docker / Supabase CLI / psql on this machine."* Every SQL mistake there costs a push
and a CI round-trip.

That handicap is **not inherited**. Proven on this machine today, not assumed:

```
VERSION: PostgreSQL 18.3 (PGlite 0.5.5) on wasm32-unknown-linux-gnu
PLPGSQL RESULT: Lisbon->Malacca = 6310.0 nautical miles
RAISE works: unknown port
```

That is a real `plpgsql` function with `SELECT ... INTO`, a `RAISE EXCEPTION`, and haversine maths,
compiled and executed in-process by PGlite — the same package `byeharu` already ships, but used there
only as a parser. So the chain gets proven in **three** places, in this order:

1. **PGlite, locally** — the whole chain applied to real Postgres before a single push. New. Fast.
2. **Disposable Supabase in GitHub Actions** — the apply-proof, exactly as in `byeharu`. Still the net.
3. **Supabase cloud** — production.

Because layer 1 exists, a migration should never reach layer 2 red.

### D7 — Supabase cloud slots are full; production is deferred, development is not

Attempted today, real output:

> `Unexpected error creating project: The following organization members have reached their maximum
> limits for the number of active free projects within organizations where they are an administrator
> or owner: gkwngns714-spec (2 project limit).`

Both free slots are taken by `byeharu` (Singapore) and `aqua-chronicles` (Seoul). A third free project
cannot be created while both are active.

This blocks **nothing** right now: V0 is built and played against layer 1 (PGlite), with the identical
SQL. The cloud project is needed only when the game goes online for other players. When that moment
comes it needs one of: pausing `aqua-chronicles` from the Supabase dashboard (reversible), or upgrading
the `byeharu` org to Pro. That is the owner's call and is not urgent yet — it is recorded here so it is
not a surprise later.

### Work dispatched today

Three foundation agents, on disjoint file domains:

| # | Agent | Writes |
|---|-------|--------|
| 1 | Core reuse audit of `byeharu` | `docs/CORE_REUSE.md` |
| 2 | Real-world port / region / goods dataset | `data/*.json`, `docs/WORLD_DATA.md` |
| 3 | Game design, grounded in Uncharted Waters Origin research | `docs/DESIGN.md`, `docs/DESIGN_RESEARCH.md` |

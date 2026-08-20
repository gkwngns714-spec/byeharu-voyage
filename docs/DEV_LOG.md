# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

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

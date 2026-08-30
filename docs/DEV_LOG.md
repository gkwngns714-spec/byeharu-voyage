# byeharu-voyage — Dev Log

Running record of **requests**, **decisions**, **work done**, **bugs**, and **fixes**.
Newest entries at the top. Dates are absolute (YYYY-MM-DD).

---

## 2026-08-26 — D29: a good comes from somewhere (0062), and what 0058's hash had quietly deleted

**The request, verbatim:** *"Also the 243 trade goods, they should be regional, meaning that for
example rice - was a main food in eastern asia and india, haggis for example is only in scotland,
unique, etc. I want something like this not a bunch of list with randomness. I want uniqueness
taylored to a location. make a list, make a table, file, and orgnize and show how you've organized"*

**The deliverable the owner named is `docs/REGIONAL_GOODS.md`** — 1,120 lines: all 243 goods filed
by region of origin, the 38 broad goods and the 83 region-locked ones kept apart, the 54 goods
buyable at exactly one port on earth, the 47 entrepot offers defended one by one, and the whole of
what 0058 broke reconstructed port by port.

### What was already true, and what 0058 had done to it

`data/ports.json` already carried a hand-researched roster for all 224 harbours — this was never a
blank page. What `0058` did, to force the owner's own count law (capital 10 / mid 4-8 / small 4),
was choose WHICH goods by `public.roster_rng(port_code || '|' || good_code)`, a seeded md5 rank.
Its receipt: *"78 offer(s) dropped, 56 offer(s) filled"*. Measured by diffing `data/ports.json` at
`6991814` against its parent:

* **78 drops, all at small harbours, the casualty picked by hash.** Konigsberg lost **amber** — the
  port whose own `notes` field reads *"ducal Prussian capital holding the Baltic amber monopoly"*
  and the good whose own note reads *"worked at Konigsberg and Gdansk"*. Saint-Louis lost
  **gum-arabic** (*"controlling the gum-arabic trade"*). Trondheim lost **copper** (*"outlet for
  Roros copper from 1644"*). Willemstad lost **salt** (*"took Curacao in 1634 for its salt pans"*).
  Machilipatnam lost **diamonds**, Jaffna **pearls**, Accra **gold**, Fuzhou **tea**.
* **56 fills, all at capitals, drawn from the whole catalogue.** Tokyo gained caviar, gold thread,
  lychees, molasses and sealskins — five of its ten. Jakarta gained North Sea herring. Copenhagen
  gained Guinea camwood. Callao gained Tuscan majolica and Chian mastic.
* **Three goods fell out of the world.** `allspice`, `pistachios` and `lac` each had exactly one
  port; each lost it to the hash. Before 0058 all 243 goods had a producer; after it, 240 did — and
  the other three stayed priced, stayed in the compendium, and were buyable **nowhere on earth**.
  Nothing was red anywhere.

### 0062 — the law, and why an entrepot list is the guard

Two new columns on `public.goods`, both authored in `data/goods.json`: **`origin_regions`** (the
regions that PRODUCE the good — never empty) and **`entrepot_ports`** (the ports outside them that
historically RE-EXPORTED it). One sentence, no third case:

> every offer is **native** (the port's region is in `origin_regions`) or a **named entrepot** (the
> port's code is in `entrepot_ports`).

**1,288 offers: 1,241 native, 47 entrepot, 0 neither.** The 47 are the age of sail — pepper at
Lisbon and Alexandria, silver at Seville and Macau, wool at the Calais Staple, Korean ginseng at
Tsushima — and every one had to be typed in by hand and defended by name in §D of the doc. That is
the point: **a seeded hash can invent an offer, but it cannot write an entrepot row.**

`0058`'s COUNT law is **kept and composed, not retyped** — assert (e) calls
`public.roster_target_count` rather than restating 10 / 4-8 / 4. What is retired is the hash's job
as an AUTHOR, and assert (j) is the positive control: 48 of its 56 picks must be gone. **8 survive
on purpose** (Cadiz silver plate, Canton grasscloth, Havana lignum vitae, Istanbul's arsenal timber,
Batavia's and Bahia's chillies, Macau's bamboo paper, Manila's carved ivory) because a blind draw
can land on a true fact and deleting a true fact to tidy the story is its own dishonesty.

### The rosters, rewritten by hand

**35 of the 78 drops restored**, each with a weaker good going in its place so the count law still
holds exactly; **43 accepted** with the reason written down. **48 of the 56 fills replaced** with a
good defensible from that capital's own trade. Eight authored pairs that predate 0058 were also
replaced because they could not be defended at all — Zanzibar's cloves are an 1818 transplant,
Hong Kong's "frankincense" is Dongguan agarwood, Cartagena never had a diamond.

### Two live incoherences the new assert found on its first run

```
0062 self-assert FAIL: 2 port(s) produce a good their own culture will not trade: FAM/wine, RHO/wine
```

Famagusta and Rhodes carried `islamic` by region and sold wine. `scripts/lib/world-derive.mjs`
already overrides two Latin-ruled Greek islands for exactly this reason (`heraklion`, `chios`);
Rhodes (Hospitaller to 1522) and Famagusta (Venetian to 1571) are the same case and were missed.
The override was completed rather than the wine deleted — weakening a true fact to green is not a
fix.

### One authority moved

`culture_mask` used to be a hand-typed table **inside a build script**
(`scripts/lib/world-derive.mjs`, `const ALCOHOL_MASK`, six entries) — a second author for a fact
about a good. It is deleted there and read from `data/goods.json`'s `cultureMask`, so one file now
answers every geographic question about a good. It gains a seventh entry: `salted-beef`, masked from
`indic` and `japanese`. Alcohol was deliberately **not** extended to `malay`, because arrack's own
note names Batavia as its distillery.

### Proven

`npm run db:apply` green, 54 receipts, and **world-guard certifies** the applied world equals
`data/*.json` (224 harbours, 243 goods, 1,288 offers, 54,432 market rows). `npm run db:proof` green.
`scripts/db/breaktest-0062.mjs` watches 26 mutations, one at a time, against a real PostgreSQL 18 —
every guard bit.
## 2026-08-26 — D29: a city SELLS only what its roster names (0061)

**The owner, `docs/OWNER_REQUESTS.md` row 48, said twice:** *"i told you, min 4, max 10 trades goods
per city. there should be a purpose to go to a city that is far away to get rare trade goods."*

**0058 answered the wrong half of it.** It made `public.port_specialties` obey the counts, and what
that table decides is AFFINITY (`world.affinity_for`, 0005:196) — how DEAR a good is, not whether it
is on the quay. `public.port_goods` still carried one row per (harbour, good): **54,432 = 224 x 243,
measured on the applied chain**, so MARKET listed all 243 goods at every city and `cmd.do_buy` sold
any of them anywhere. A repeated instruction always means the wrong thing shipped.

### THE DECISION, and it is the whole entry: BUY is the roster, SELL is not

Restricting SELL as well was considered and **refused, on measurements**: the roster names 1,288
pairs over 243 goods, so a good is on the roster of **5.30 harbours on average** and three goods are
on no roster at all. A city that also refused to BUY outside its roster would leave a hold with
roughly five buyers in a world of 224 harbours, and cargo already afloat would be unsellable where
it stood. So `cmd.do_sell` is **deliberately untouched**, and with it every `public.port_goods` row:
the market row IS the price, and `world.quote` / `world.price` / `world.mid_price` all raise
`E_NO_SUCH_GOOD` without one. A city buys what is offered to it and sells only what it trades.

That decision is why this slice does NOT delete 53,144 market rows, which is what the brief that
opened it expected. Deleting them would have taken SELL down with them.

### THE MECHANISM — one authority, composed onto a refusal that already existed

`public.port_offers(port, good)` answers *is this good on this city's quay?* by reading
`public.port_specialties`. It **derives nothing**: no `roster_target_count`, no `roster_rng`, no
count, no opinion about how many goods a city ought to name — because the roster's CONTENT is being
restored to `data/ports.json`'s authored, historically-grounded lists in a separate slice, and every
rule here has to survive that. `cmd.do_buy` gains ONE gate, raising the **`E_UNAVAILABLE: % is not
traded in this port` it already raises for the culture mask** (0007:435-443), so `cmd.refusal_caught`
and the client's refusal rendering are untouched by construction.

`world.market` serves the quay through `public.quay_shows` — the roster **plus** whatever a fleet of
the reader's lies here CARRYING. Without that second half SELL would be legal on the server and
unreachable in the game: `src/features/command/ArgPickers.tsx:471` draws the SELL list from
`world.market(port).goods`, and a row the read omits has no price to sell at. Those rows carry
`offered: false` and may be sold, never bought.

### AND THE RECORD FOLLOWED THE QUAY — the number the owner is paying for

`public.tick_price_snapshot` now samples only offered pairs, and the rows it had already written for
pairs no quay offers are deleted. **0057's window law and its 600 MiB budget are untouched.**

| | pairs sampled | window | ceiling |
|---|---:|---:|---:|
| before | 54,432 | 57 slots | **~594.7 MiB** |
| after | 1,288 | 57 slots | **~14.1 MiB** |

**The seam is named rather than hidden.** 0057 divides its budget by `count(*) from port_goods`,
which is now an UPPER BOUND on the pairs the record holds rather than the exact count — conservative,
by 42x. Pointing `price_history_window()` at the offered count instead would raise the window to
**2,430 slots** (measured: `price_history_window_for(1288)`) and put the ceiling straight back at
~600 MiB, because a budget-filling law fills its budget. That is a decision about how much history is
worth keeping and it belongs to whoever next revisits 0057's budget.

### SPAGHETTI, NAMED AND NOT ADDED TO

The culture predicate `culture = any(g.culture_mask)` is written **five times** in the live schema —
`cmd.do_buy`, `cmd.do_sell`, `world.market`, `world.trade_routes`, `cmd.haggle`. It predates this
slice and folding five live bodies in a migration about the roster would triple the blast radius on a
live game, so it is written down here and 0061 refuses to become the sixth: `port_offers` answers the
ROSTER question only. **Measured consequence of leaving it:** 2 (port, good) pairs are on a roster
AND blocked by their port's culture, so 2 harbours offer one fewer BUYABLE good than their roster
names. Content, not mechanism — which is why the migration asserts the owner's own **4..10** band
rather than 0058's per-tier counts.

On the client the same question got the same treatment: `buyableHere(good)` in
`src/features/market/marketRows.ts` is the ONE reading of *can this be bought at this quay*, folding
both reasons a city will not sell (culture, roster) behind the sentence the screen already said —
**"not traded here"**. `MarketScreen`'s tap target, its tile split and its filter all ask it.

### THE DEFECT A PROOF FOUND THAT REASONING DID NOT — and it is the entry to keep

The first draft left `world.trade_routes` alone, on the written argument that it *"joins
`public.port_goods` at BOTH ends"*. It does — **and every (harbour, good) pair still has a
`port_goods` row, so that join restricts nothing.** The quay went on shortlisting cargoes a captain
could no longer buy. `scripts/db/proofs/04_first_session.sql` read it straight back:

```
PROOF 4 FAILED at 0:20 — the Lisboa market served 10 of 243 goods,
civet is on it 0 time(s)
```

That is `0017:50-55`'s scar in a new costume — a rule wired into one half and not the other — so the
fix landed in **the same migration**, not a follow-up: `world.trade_routes`'s ORIGIN CTE now asks
`public.port_offers`. The **destination is deliberately still unfiltered**, and for the same reason
`cmd.do_sell` is: selling is not gated by the roster, so a city that does not trade a good may still
be the best place to carry it — filtering both ends would have deleted the owner's own point by
construction.

`scripts/db/proofs/05_first_voyage_balance.sql` then found the mirror image: its EXHAUSTIVE control
still scanned all 243 goods and so beat the shortlist with a trade nobody can make —
*"at ALE the exhaustive scan found 1070 d. (cloves to HER) and world.trade_routes offered only
614"*. Its comment already said "every good this port trades"; since 0061 that sentence is literal,
and the control now asks the same authority the shortlist does.

**Two proof pins moved deliberately**, both away from a membership pin and onto a derived one:
proof 4's `length(market.goods) = count(*) from public.goods` became the port's own roster count
with the owner's 4..10 band checked beside it, and `tests/rpc.surface.spec.ts`'s
`toHaveLength(snap.goods.length)` became the same. Neither pins WHICH goods a city carries, because
the roster's contents are being re-authored in 0062.

### PROVEN

* `npm run db:apply` / `npm run db:proof` — see below.
* `scripts/db/breaktest-0061.mjs` — every mutation watched go red.
* The migration's own receipt, on a real house at Lisboa in the transaction that applies it: a
  queued BUY of `abaca` — **whose market row still exists** — is refused `E_UNAVAILABLE` and the
  order recorded `failed`; `black-pepper` still fills 10 tuns for 1,295 d.; and **SELL of that same
  `abaca` still pays 2,523 d. for 20 tuns**, so no hold is stranded. `world.market` at one harbour
  per tier serves that harbour's roster exactly — ACC 4, ACA 6, ALE 10 — and exactly one row wider
  when a hold carries something the city does not trade.

---

## 2026-08-26 — D28: the encounter mix is LIT (0059), and a fair wind that could fold the schedule

**One migration, 0059 — `the_sea_decides_what_it_breeds`.** It is the lighting slice 0055's own
header named, and nothing else: the four statements at
`supabase/migrations/20260818000055_what_these_waters_breed.sql:132-143` are quoted verbatim at the
top of 0059 and the file is those four statements.

| statement | what landed |
|---|---|
| 1 | `voyage.hazard_roll`'s body IS `voyage.encounter_at`'s — **sliced, not retyped**: the deployed definition with only the function name in its header changed, so the two cannot differ by a character. `voyage.encounter_at` is **DROPPED in the same statement**; 0055 wrote it to BE this body, and a copy kept "for reference" is the second author §1 forbids. |
| 2 | The flat draw is **deleted, not left beside the mix**: trigger `voyage_event_kinds_weights_close`, its function `public.tg_voyage_event_kind_weights`, and the columns `roll_weight`, `cedes_to`, `cede_fraction`. The cede columns go too, on **0055:427-430's own ruling** — *"the mix says it directly, so a second mechanism for the same sentence would be a second authority."* Then `is_rolled = true where in_sea_mix`, so `is_rolled` now means only "drawn". |
| 3 | `voyage.settle` gains five arms by a **three-hunk slice**. FAIR_WIND gives back delay hours, FOUL_WATER starts water over the side, SHOAL_WATER takes durability, DERELICT and CONSORT touch no ship. `if v_delay > 0` becomes `<> 0`, because a fair wind moves the arrival EARLIER and the old test would have banked the hours. And the chain now ends `elsif h.occurred then raise E_KIND_ARM` (§7C) — before it, a drawn kind with no arm fell through to `else` and was **written down as a quiet watch**: a hazard silently deleted from the game, green everywhere. |
| 4 | `voyage.waters_ahead` serves the mix as a fifth fact per row, `voyage.sea_mix`'s own shares. **The panel does not draw it yet** — `src/features/map/WatersAhead.tsx:41-44` names itself that reader and its spec forbids a row that reads like a forecast; that is a client slice and 0059's header says so rather than implying it. |

### THE MEASUREMENT, and it is the migration's own

Not quoted from 0055. 0059 captures the pre-image bands one statement before it deletes them and
walks all 10,000 points of [0,1) twice — once through those bands, once through the deployed
`voyage.sea_mix` — and prints both in its receipt:

| sea (danger, piracy) | PIRATES share of event-days |
|---|---|
| home waters (1, 0.20) | 33.0 → **7.0** per cent |
| **Mediterranean (3, 0.45)** | **43.0 → 20.4** per cent — the Barbary run |
| Caribbean (4, 0.45) | 43.0 → 23.4 per cent |
| Malacca (5, 0.45) | 43.0 → 25.8 per cent |
| Arctic (4, 0.12) | 29.8 → 9.3 per cent |

7,540 of 10,000 points of the Mediterranean draw now land somewhere other than the flat bands put
them. **The frequency of event-days did not move at all**, and that is proved rather than asserted:
over 34 voyage-days of a real 3,536 nm passage the lit draw matched DESIGN B.6's clamp and the three
rng streams **recomputed independently of the deployed body** on every single day.

### THE BUG THE PROBE CAUGHT, which is the entry to keep

The first draft's fair wind gave back up to 48 hours. `voyage.day_ends_at(d)` is
`departed_at + (d × 24 + delay_before_day(d)) × k`, so **a gain of 24 hours or more moves day d+1's
boundary to or before day d's and the schedule INVERTS** — `voyage.settle` then resolves two
checkpoints where the player was told there was one. The probe caught it as *"day 2 settled as
FAIR_WIND … and the voyage stands at day 4"*. The gain is now bounded twice, and both bounds are
load-bearing:

* never more than `voyage.delay_before_day` (0006:475), because `voyages.delay_hours` is
  `check (delay_hours >= 0)` (0006:67) and an unbounded gain aborts the settlement on a CHECK — and
  would land a fleet before she could physically have sailed;
* never a full voyage-day (6–22.8 h), so a fair wind **compresses** the schedule and never folds it.

Both are asserted, the second by requiring day d+1 to still end after day d once the arm has fired.

### THE SECOND BUG, which was in the probe rather than in the game

The unarmed-kind probe inserted `PROBE_UNARMED` and pinned the mix to it and *then* went looking for
a clean day to draw it on. The day-search settles the days it skips — so a skipped day drew
`PROBE_UNARMED` **outside** the handler, and `E_KIND_ARM` doing exactly its job escaped as a
migration failure. About a one-in-a-hundred lottery, and **it lost on the third full `db:apply`,
after the break-test had gone green sixteen times.** The clean day is now found first, while the mix
still holds only armed kinds. Worth writing down because it is `docs/NO_SPAGHETTI.md` §4's rule in a
new costume: *a probe is deterministic and satisfies its own preconditions* — and a probe that is
right 99 times out of 100 is a probe that will be wrong in CI.

### PROVEN

* `npm run db:apply` — 53 migrations, 53 self-assert receipts, world guard green.
* `npm run db:proof` — every marker of all nine proofs.
* `scripts/db/breaktest-0059.mjs` — **fifteen mutations, every one RED.** It caches the pre-0059
  chain as a PGlite data directory keyed on the bytes that built it, so iterating on the migration
  costs seconds instead of the ten minutes a cold chain takes; a changed earlier migration changes
  the key, so the cache cannot go stale. Three of the first drafts
  were mis-aimed and are written down here because the mistake is instructive: one edited text
  *inside* the insertion (invisible to a byte comparison by design), one overflowed `numeric(6,4)`
  and so was a SQL error rather than a legal wrong migration, and one deleted the `elsif h.occurred
  then` line and thereby broke DERELICT's arm instead of testing the fallthrough it was aimed at. A
  mutation that goes red for the wrong reason proves nothing.
* `scripts/db/proofs/01_offline_equivalence.sql`'s `OFFLINE_EQUIV_ENCOUNTER` marker **follows the
  body** to `voyage.hazard_roll` — it was gated on the dark function by the slice that authored it,
  and it now covers the LIVE draw.

### AND ONE FLAKE SEEN IN PASSING THAT IS NOT 0059's — migration 0047

On one `db:proof` run the chain died inside **`20260818000047_the_sea_is_a_free_plane.sql`**:

```
E_DIVERT_FAILED: she did not come to rest at the turn (status SAILING)
```

0047 is untouched by this work, it runs eleven files before 0059, and the identical chain had
applied cleanly in the `db:apply` seconds earlier and in every run before and after. `voyage.divert`
truncates a voyage and then settles to `greatest(v_now, v_eta)`, so its own probe is sensitive to
real wall-clock time against a compressed ETA — the same class of defect as the two above.
**Recorded, not fixed, and not attributed to 0059**: it is a pre-existing intermittent in an applied
migration's self-assert, it will eventually redden CI's disposable-chain job on an innocent PR, and
whoever picks it up should start at `0047:1022`.

### THE PRODUCTION QUESTION, asked out loud because 0057 was not

0057 passed on PGlite and on CI's disposable Supabase and then **failed the real production push**,
because both engines boot from an EMPTY database and production carries live data. So, explicitly:
**0059 seeds nothing and inserts nothing.** Its only committed write is
`update public.voyage_event_kinds set is_rolled = true where in_sea_mix` — an UPDATE of rows the
chain itself put there, on a server-private table no client can write, so there is nothing for it to
collide with. Every other statement is DDL or a `pg_temp.recut` slice, and a slice **refuses** rather
than half-applies if production's deployed body is not what the hunks were cut against. Days already
in `voyage_events` are never recomputed, so no day a player has been told about changes; for the days
still ahead of a sailing fleet, 0055's assert (j) already proved the two bodies agree on whether
something happens, its magnitude and its probability — she keeps her event days and her arrival, and
only what befalls her on them may differ.

**NOT DEPLOYED — and the sentence this replaces was already stale when it was written.** This is on
branch `osn-0059-light-encounters`. It said *"Production is on 0056; 0057, 0058 and 0059 are all
still un-pushed"*; by then **0057 and 0058 had both applied** and production read 52 of 52, head
0058 (D27, below). Only **0059** is outstanding. The agent that wrote this line was working from a
`d6270f4` base and could not see the push — which is the ordinary hazard of a worktree, and the
reason a deploy state is re-read from `supabase migration list --linked` rather than carried
forward in prose.

**Also corrected:** this entry's closing note called 0053's Postgres-17 failure a *"still-open
blocker"*. It is not — `ffbaf9c` fixed it and 0053 applied to the real Postgres 17 in production on
2026-08-26. The 17-vs-18 caution the note draws from it still stands on its own merits: PGlite is
Postgres 18 and this migration has not been proven on 17, which is what the PR gate is for.
## 2026-08-26 — D27: the migrations reach production — all 52 applied — and the reason they nearly did not

**Production's database is no longer behind its client.** `supabase migration list --linked` reads
**52 of 52 applied, head 0058, nothing outstanding.** Verified on the target, not inferred from a
green exit code. The eight that had been stuck — 0051, 0052, 0053, 0055, 0056, 0057, 0058 — are all
live. The Postgres-17 blocker D26 recorded is gone: `ffbaf9c` pinned the neighbourhood walk to a
custom plan and 0053 applied to the real Postgres 17 without complaint.

### THE ONE TO READ: both test engines were green on a precondition that could not hold

The first production push applied 0051, 0052, 0053, 0055 and 0056 and then **died on 0057**:

```
ERROR: duplicate key value violates unique constraint "price_history_pkey" (SQLSTATE 23505)
Key (port_id, good_id, slot)=(c205adb3-..., 4c69bf2d-..., 2979499) already exists.
At statement: 9
```

0057's step 3 seeds a precondition — rows at slots `now-3`, `now-10` and `now-100` — so the prune
below has something to prove itself against. **A fresh chain boots `price_history` EMPTY**, so
nothing collides there, and a fresh chain is *every engine this project tests on*: PGlite locally,
and CI's disposable Supabase. Production has a live tick that has been writing a row for every
(port, good) every ten minutes for days. All three slots were already occupied. The INSERT could
only fail.

**The knowledge was already in the file and did not reach the statement.** The comment directly
above the INSERT says, in these words: *"On production the equivalent excess already exists for
real, at every pair"*. It then wrote a bare INSERT.

The fix is `on conflict (port_id, good_id, slot) do nothing` — which is not a patch but **0013's own
idempotence rule**, the same way `public.tick_price_snapshot` has always written. It makes step 3
mean the same thing on both kinds of database: after it, rows exist at all three slots — written by
this file on a fresh chain, by the live tick on production. **No assertion below weakens**, because
every one of them reads the TABLE rather than this statement's row count; on production the ancient
slot carries REAL rows the prune must remove, which is a *stronger* positive control than a
synthetic one.

And because `do nothing` can silently do nothing, the precondition is now **asserted rather than
argued**: a new check raises unless the subject port carries both recent and ancient rows before the
prune. On a fresh chain it reports `486 recent and 243 ancient`.

**The lesson, and it is not specific to 0057:** *green on PGlite and green on the disposable
Supabase does not mean it will apply to production*, because both boot empty and production does
not. Any migration that WRITES a precondition rather than only reading one is exposed to exactly
this. Editing 0057 was legitimate only because it had never applied anywhere real — the rollback was
clean and it held no production state.

### What is now live that was not

| | what a player gets |
|---|---|
| **0051** | rarity re-tiered on the world's own mean producer count — 171 goods moved tier |
| **0052** | Bristol snaps 0.00 nm instead of 64.55 nm over Devon; the overland course is REFUSED |
| **0053** | `world.market` at Bordeaux 1,442 ms -> 241 ms, buffers 331,470 -> 40,530 |
| **0055** | ten encounter mixes derived from each sea — **still DARK**, nothing draws from it yet |
| **0056** | `drift_sigma` 0.040 -> 0.020; geography beats noise again (1.17x -> 1.64x) |
| **0057** | `price_history` bounded at **57 slots / 623,627,424 bytes**, was headed for ~3.0 GB |
| **0058** | every harbour offers **capital 10 / mid 4-8 / small exactly 4** — 78 offers dropped, 56 filled, 1,310 -> 1,288 |

0057's self-assert ran INSIDE the production transaction and required the whole table's slot span to
sit under the 57-slot window with rows still present. **It committed — so production's
`price_history` is provably bounded now**, not merely expected to be.

### VACUUM FULL: decided AGAINST, and the reason is not laziness

0057's header correctly says the freed bytes are not returned to the disk until someone runs
`VACUUM FULL` by hand. That step is **deliberately not being taken**:

* The dead space (~800 MB) is already reusable by Postgres, and the table is now permanently
  bounded, so the file cannot grow past what it already is.
* `VACUUM FULL` takes an ACCESS EXCLUSIVE lock — it would block the price chart read *and*
  `tick_price_snapshot` on a live game — and needs ~600 MB of transient disk.
* It buys ~800 MB back on an 8 GB disk, against a database that now settles near 620 MB.

Separately and independently: it is **not runnable from this machine at all**. The Supabase CLI has
no arbitrary-SQL subcommand, and no database password is stored here — `db push` connects by
provisioning a temporary login role from the access token ("Initialising login role..."). It would
need the dashboard SQL editor. The decision above does not depend on that.

### The plan question, answered with arithmetic

Checked against supabase.com/pricing, not recalled: **Free is a 500 MB database; Pro is from
$25/month with 8 GB disk included**, then $0.125/GB.

Production's steady state after 0057 is `price_history` **595 MB** (623,627,424 bytes, the figure
0057 asserts) plus `port_goods` 23 MB plus everything else under 2.3 MB — **about 620 MB**.

**620 MB > 500 MB, so the free tier is unreachable — and it stays unreachable even at the floor.**
At 48 slots, the minimum the chart itself requires, 54,432 pairs x 48 x 201 = **501 MB** of
`price_history` alone, 526 MB with the rest. There is no setting of 0057's budget that fits 500 MB
while the world samples 54,432 pairs. **Pro is forced.**

The only lever that changes that arithmetic is the pair count, and it leads somewhere worth
recording: **`port_goods` carries all 243 goods at all 224 ports (54,432 rows) — every port trades
every good.** 0058 implemented row 48 as `port_specialties`, 1,288 rows, about 5.75 per port. So a
city *specialises* in 4-10 goods; it still *offers* 243. If `price_history` sampled only the roster,
1,288 pairs x 48 x 201 = **12.4 MB** and the free tier would fit with room to spare. That is a design
question, not a disk question, and it is flagged on row 48 rather than decided here.

---

## 2026-08-25 — D26: pushed and deployed (site only), an outage that filled the disk, and a Postgres-17 blocker found on the way out

Later the same day as D25. Three things happened, none of them a migration:

**1. Pushed and deployed.** `origin/main` moved to `15bd8c3`. `Build`, `Acceptance` (run
`32857651456`), and `Deploy (GitHub Pages)` all ran green; the owner drove the live site at
`https://gkwngns714-spec.github.io/byeharu-voyage/` and confirmed the new one-row six-cell nav
bar. **This is a frontend deploy only.** Production's database is unaffected by it — Supabase does
not deploy migrations on a `git push`, and `supabase migration list --linked` still shows 0050 as
the applied head, with 0051, 0052, 0053, 0055 and 0056 all carrying an empty remote column.

**2. The outage.** The production Supabase project filled its 2 GB disk and Postgres put the whole
project into **READ-ONLY mode**. Every write failed; `POST /auth/v1/token?grant_type=refresh_token`
returned **500**, so no player could even hold a session, and the live game hung on loading
skeletons. `supabase db push` and `supabase migration list` both died with
`ERROR: 25006: cannot execute GRANT ROLE in a read-only transaction`.

Cause, measured in the dashboard SQL editor: **`public.price_history` was 1,410 MB across 7,347,231
rows — 98% of a 1.43 GB database**, where a freshly built world from the same chain is 21 MB. The
owner upgraded the org to Pro and raised the disk from 2 GB to 8 GB; read-only cleared at 23:34 and
the game came back.

The underlying defect: `price_history_slots = 288` was calibrated for the 14,980-pair world 0003
seeded, and migration 0041 grew the world to 54,432 pairs without resizing the retention window —
a designed ceiling of **15.7M rows / ~3.0 GB**. Raising the disk quota bought time; it did not fix
the ceiling. **Being fixed as migration 0057, by another agent, not yet landed on this branch as of
writing.**

**3. Migration 0053 fails on Postgres 17.** `supabase/config.toml` pins `major_version = 17`, which
is what production runs; PGlite (the local gate) runs Postgres 18, where 0053 passes. CI's
`disposable-chain` job boots a real Postgres 17 and caught it: run `32857650723`, job
`disposable-chain`:

```
ERROR: 0053 self-assert FAIL: one world.market() read still touches 314337 buffer(s) against the
old body's 270277 — less than the 3x this file exists to buy. The read has gone back to walking
the neighbourhood once per good. (SQLSTATE P0001)
```

This blocks `supabase db push` at 0053, which in turn blocks every migration after it —
0051, 0052, 0055, 0056 are not themselves at fault but cannot deploy until this clears. In flight in
worktree `bv-pg17` / branch `pg17-0053` as of writing; not yet landed on `main`.

See `docs/RESUME.md`'s anchor for the current state of all three. `docs/OWNER_REQUESTS.md`'s
`DEPLOY STATE` note is corrected to match.

---

## 2026-08-25 — D25: nine slices — and the number this project has quoted for a week was measuring the harness

Five migrations (**0051, 0052, 0053, 0055, 0056**), one slice that took the number **0054** and turned
out to need no migration at all, and three client slices. The chain is **50 files** and ends at 0056.

**THE ONE TO READ FIRST** is the balance finding at the bottom. `docs/DEV_LOG.md`, `docs/RESUME.md`
and this proof's own header have quoted *"a first voyage returns 12–18%"* since 2026-08-18. That
figure was never about the economy. It was a count of how many drift ticks the test harness happened
to run before it looked, and **every deployed world — every world whose clock has run, which is all of
them — was paying about 37%.**

### The recipe named once, the supersede declared, and a guard that stopped over-reaching

Two duplication guards were red, and they were two different defects.

* **The class recipe written twice.** `src/components/ui/RefusalNote.tsx:63` (the `have / need` figure
  beside a danger Meter) and `src/features/command/HaggleBlock.tsx:139` (the next-odds percentage
  beside its own Meter) both hand-wrote `shrink-0 font-mono text-sm tabular-nums text-ink` — **100
  per cent token overlap across two files that never met**, which is the shape the twelve chip copies
  started in. Named once as `inlineFigureClass()` at `src/components/ui/typography.ts:61`, beside
  `fineClass`/`rowLinkClass`/`headRowClass` and exported from the design system's one entrance; both
  call sites ask for it and neither owns it. **The flex behaviour (`shrink-0`) is deliberately left
  to the caller** rather than baked in — the same boundary `rowLinkClass` keeps with the 44 px floor.
  `tabular-nums` is named as the load-bearing token: the figure sits in a flex row beside a
  `min-w-0 flex-1` Meter, so proportional digits would shift the bar's end on every tick.
* **0050 genuinely supersedes `voyage.sail_refusal` and its header never used the word.** A
  `── THE SUPERSEDE, DECLARED ──` section now says it: what is superseded and why, that it is a
  no-op where `figures` is absent, and that everything which must move together moved in that one
  file. **0050 is applied to production, so this had to be comment text and nothing else** — proven
  rather than promised: `git diff -U0` is 31 added lines, every one beginning `--`, and the two
  versions are byte-identical once comment lines are stripped. Said out loud as a consequence:
  `src/lib/db/chain.ts` fingerprints the chain's bytes, comments included, so a comment moves the
  fingerprint and every local browser database rebuilds from 0001 (rescuing player rows first).
* **The third guard was WRONG, and the fix was to narrow it, not to invent a supersede.**
  `pg_temp.recut` is the hunk-slicing helper, defined at `0047:80` and again at `0050:120`. A
  `pg_temp.*` function lives in the connection's temporary schema and dies with the session: it never
  enters the deployed catalogue, so there is no deployed body to re-cut and **a migration replayed
  alone into a fresh session MUST carry its own copy.** `tests/duplication.spec.ts` now skips
  `pg_temp` and nothing else (`tests/duplication.spec.ts:368-384`, one line of code and seventeen of
  reason) — every persistent schema is still read, and 0050's real supersede is still caught by the
  same test.

### 0052 — the Severn is water, and the pack is one rule

**D22 filed this as a wrong label. It was a live breach of the owner's law.** *"i don't want the
fleet to ever touch land"* (`OWNER_REQUESTS` row 41).

The Severn estuary is narrower than a 0.25° cell above Barry, so the whole Bristol Channel east of
4°W scan-filled as LAND and Bristol's nearest sailable water was **Lyme Bay, 64.55 nm away, over
Devon, on the other coast of England**. And `sea_reaches.snap_nm` is not a label: it is what
`voyage.path_refusal` grants a course as its **head allowance**, so Bristol carried a **~90 nm
land-exempt corridor and the pathfinder used it**. Measured on the old raster: **BRS→AMS 324.7 nm**,
whose first leg ran straight from the quay to (50.63, −0.13) **across Somerset, Dorset and
Hampshire**; **BRS→DUB 179.5 nm** straight over the Welsh mountains.

A `severn` entry in `scripts/sea-grid.mjs`'s CHANNELS — the Bristol Channel and the Avon, real water
her ships worked to King Road and seven miles up to the quay — opens **5 cells (545,984 → 545,989)**:

| | before | after |
|---|---|---|
| Bristol's snap | 64.55 nm (Lyme Bay, English Channel) | **0.00 nm** (her own cell) |
| the sea she answers | english-channel at ring 4 | her own declared sea, at **ring 0** |
| BRS→AMS | 324.7 nm over England | **613 nm** round Land's End |

The second defect in the same file: **the Antarctic closure was three statements of one concept** —
`ICE` could only express a northern parallel, so the pack lived in the generator as its own
`cells.fill(0)` at −60 and the generator's cross-check repeated the same −60 a third time. `ICE` now
takes `latBelow` and the pack is one row in it, justified from the dates (South Georgia 54°S 1675;
the South Shetlands at 62°S not sighted until 1819; the Circle not crossed until Cook in 1773).
**THE WATER DID NOT MOVE: same parallel, 0 cells different.**

And the file proves it changed only what it meant to: **55,938 pair readings identical, 468 moved,
every one of them Bristol's.** LIS→NAG 12,989 nm, ALE→ADE 11,050 nm, VER→ACA 12,398 nm — unmoved.
Cape Horn, the Drake Passage, the Roaring Forties and the Cape route identical to 0.1 nm. Both
Bristol guards are non-vacuous by construction (the snap must not exceed 20 nm — *it was 64.55*;
BRS→AMS must not fall under 500 nm — *it served 324.7*), and the real overland course is put in front
of `voyage.path_refusal` and REFUSED.

### The map: a name you can hit, a ratio you can set, and an opening frame with land in it

Three defects, each found by driving the running game in a browser, each reproduced before it was
touched, each with an assertion that goes red without its fix (`tests/map.sendfleet.spec.ts`).

* **A harbour's name was not part of the harbour.** Measured at 1389×900 on the seeded world: Cádiz's
  mark sits at x = 959.6 and the word *Cadiz* runs x = 968.6…1000.1, so **the centre of the name is
  24.8 px from the mark and the reach was 22 px.** Walking outwards, 18 px selected Cádiz and 22 px
  returned *"OPEN SEA 36.4°N 6.4°W"* — a plausible panel for a different destination and a wasted
  voyage, with nothing to tell the player they had missed. `GLYPH.hitRadius` is now DERIVED from
  numbers this repo already owns: `labelGapX` 9 + `TOUCH_TARGET_PX`/2 22 + the largest mark's
  half-extent 7 = **38 px**. Checked against the names the running app actually drew, measured from
  their own centres: **Cadiz 24.8, Porto 24.8, Lisbon 27.9, Malaga 27.9, Sevilla 31.0** — every one
  inside 38. Free-sea pinpointing is untouched away from a drawn harbour, and near one it is a zoom
  away: 38 CSS px is 70 nm on the opening frame and 9 nm four steps in. Ties are no longer decided by
  array order — greater `size_tier` wins, then the lower code.
* **The fold could USE a standing order but not WRITE one.** A house that had authored none saw a
  single `None` chip and had to leave the map for FLEETS — the screen-hop row 45 exists to delete.
  The fold now carries the ratio itself: the hero figure `15.0 / 16 days` (her served
  `endurance_days` over the depth the order would keep her at), a countable `Gauge`, and two
  steppers. **Adjusting writes nothing and sends nothing;** one named press on its own line —
  `Keep 16 & send` — resolves the days through 0034's book and sends. The ratio is looked up in the
  book and written only when the book does not already hold it, through the same
  `cmd.provision_preset_save` / `cmd.provision_preset_apply` the FLEETS galley presses. **The map
  cannot mint a second set of standing orders**; one issue path, one judge, one composer.
* **The opening frame could contain no land.** `atLeast` guaranteed 12 degrees across and nothing
  about what was in them, and free-coordinate anchoring puts fleets in open water on purpose — so a
  fleet at anchor mid-ocean opened on a correct frame of nothing. `openingBounds` now widens about
  its own centre, keeping its shape, until the nearest HARBOUR is on the sheet (a harbour is where
  land meets water, and the coastline is fetched too late to consult). **It only ever widens**, so
  the frame every existing player already sees is unchanged.

The land check is not a promise either: `tests/map.sendfleet.spec.ts` asks the RENDERED coastline
path itself, through `isPointInFill`, at 24 × 24 = **576 sample points** on the §K.1 opening frame
and measures **154 / 576 = 26.7 per cent land** against an asserted floor of 5 per cent. Break-tested:
the 22 px reach turns the Cádiz tap back into *"Open sea 36.6°N 7.1°W"*; hiding the ratio block fails
the fold assertion; a mid-ocean opening frame reports **0.0 per cent land** through the same probe.

### One row of six: the voyage stays direct, the cabin takes the tap

Measured at 390×844 before: **nine cells of 130×56 in a bar 168 px tall — three rows, 19.9 per cent
of the screen spent on navigation.** After: **six cells of 65×56 in a bar 56 px tall, one row.** The
game gained 112 px.

`docs/OWNER_REQUESTS.md` carried this as an open question — *"noted here in case the answer is to group
tabs rather than add a row."* The answer is to group, and the grouping is read off the information
architecture rather than an arithmetic split:

* **THE VOYAGE stays one tap.** Command, Fleets, Port, Market and Map are the loop, touched many
  times a session, and `UI_DIRECTION.md` 3a is explicit that depth added to a frequent act is a
  defect. None of them is grouped.
* **THE CABIN is the one group: Ledger, Rank, Codex, Profile.** What they share is not "leftovers" —
  **none of them acts on the world.** They are consulted, not played, and one extra tap is what buys
  the frequent five their directness. RECORDS was rejected (Ledger is already *the running record*);
  HARBOUR over {Port, Market} was rejected (Port is already glossed *the harbour you are in*, and
  Market is played too often to sit behind a tap).

**ONE TABLE, STILL.** `group` is a field on the tab in `ALL_TABS`; `NAV_CELLS` is DERIVED from it.
There is no second array of members to drift. **A group REVEALS, it does not replace the bar:** the
members open in a panel positioned out of flow above the rail, so not one cell moves, the rail does
not change height, and the screen behind is overlaid rather than pushed — the owner's rule, said four
times and built backwards twice. `tests/nav.geometry.spec.ts` pins both halves and was break-tested
both ways: forcing `grid-cols-4` goes red on the row count, and making the panel `relative` goes red
on the rail swelling **57 px → 113 px** (`nav.geometry.spec.ts:232-237`). **That second break PASSED
the first version of the guard** — the six cells were identical to the pixel and the screen behind
had still been re-flowed — which is why the guard now measures the nav box and `main` as well as the
cells. Also measured at 320×568: six cells of 53×56, widest label 46 px, none shaved, which is the
reason it is six and not seven (320 ÷ 7 = 45.7 px, and COMMAND needs 46).

### The world arrives built — a pre-built image the chain's own fingerprint names

`docs/RESUME.md` and this file both recorded the defect: *"Cold boot 78.8 s measured with 243 goods.
The world builds in the player's tab."* Every first visit replayed the whole chain — 52,002 derived
price rows, a re-measured sea — to arrive at a world that is **a pure function of the repository**.
`npm run build` now applies the chain once and emits `dist/db/world-<fingerprint>.tar.gz`.

Measured on this machine, back to back, on the same build:

| | measured, chromium 390×844, empty storage, the purse read off the screen |
|---|---|
| cold boot, chain applied in the tab | **171.7 s** to a live purse — 168.8 s of it applying the chain |
| cold boot, world restored from the image | **7.1 s** to a live purse — 4.3 s to `ready`, **no migration applied in the tab** |
| warm boot (world already in IndexedDB) | 5–7 s either way; this slice does not touch that path |
| the image over the wire | **+4.75 MB** gzipped (`dist` 7.48 → 12.22 MB), fetched **only when a world must be built** |

**A shipped image is a SECOND COPY OF THE WORLD, and D23 is what that costs** — 0003 was edited after
production had applied it, production kept 70 goods while every fresh rebuild got 243, and *"nothing
red happened anywhere."* So the image is built to be impossible to ship stale: it is **generated,
never committed** (`vite.config.ts` calls `ensureWorldImage()` during the build, from the chain on
disk at that moment); **its NAME is its fingerprint**, and the client derives that URL at run time
from `fingerprintChain(files)`, so a moved chain is a 404 and a 404 applies the chain; **it carries
the fingerprint INSIDE it** (`app_local.chain` moved to `appLocal.ts` so builder and browser stamp
and read it with one DDL and one query) and `imageRefusal()` refuses a mismatch out loud, in the
console, in `bootState` and in `RebuildNotice` on the screen; and **it is certified by the existing
authority** — `scripts/db/world-guard.mjs` run against the database RESTORED FROM THE TARBALL, no
second comparator written, plus §K.1's opening played inside it, because a world that reads back but
cannot be written to is not a world anybody can play.

The size came from the same discipline. **100.4 MB dumped → 37.4 MB after the log trim → 4.75 MB
gzipped**: 67 MB of the raw dump was `pg_wal` — segments PostgreSQL had RECYCLED, holding the log of
migrations that had already run, waiting to be overwritten by writes a shipped copy will never make.
`dropSurplusWal()` keeps only `[checkpoint, current]`, which is what a restored engine replays, and
`initdb --wal-segsize=1` makes those segments 1 MB instead of 16.
The trim is not trusted: the certification restores and PLAYS the trimmed tarball before it is
allowed a filename. `tests/db.image.spec.ts` certifies whatever the build emitted and carries its own
positive controls — an image offered as another chain's, and an image whose inner stamp was
rewritten, must both be REFUSED, and both were watched red. The fallback is untouched and driven end
to end: no image, a 404, an SPA page instead of a tarball, an unreadable tarball, or a mispaired one
all land on the chain apply.

### 0051 — the world says how rare rare is

0032 derived rarity from how many ports produce a good, which was right, and then cut it at **three
absolute producer counts calibrated for a 70-good catalogue**. At 243 goods over 1,310 specialty rows:

    exotic 133 (54.7%) / rare 58 (23.9%) / uncommon 27 (11.1%) / common 25 (10.3%)

**The top tier was the default, so the word meant nothing.** The average harbours per good had fallen
11.9 → 5.4 under the same fixed cuts. And 0032's own shape assert allowed any tier up to 60 per cent,
so the meaningless rule satisfied it — **that loose assert was part of the defect** and is re-cut here
to fail on it (apex ≤ 25 per cent, no tier over 40).

THE RULE: `public.rarity_scale()` is the world's own mean producer count (μ = 5.391 today, read from
`port_specialties` alone), and the cuts are `max(1, μ/4)` / `max(2, μ/2)` / `max(3, μ)` — a geometric
ladder floored at the smallest three whole numbers of producing ports so the tiers stay
distinguishable however sparse the world gets. Today: **exotic 47 / rare 86 / uncommon 58 / common
52**, with **171 of 243 goods re-tiered**. The apex cannot be thinner than 47, because 47 goods are
made in exactly one harbour.

* **Scale-freedom is PROVEN, not argued:** every good keeps its tier when the whole world is
  multiplied by **k = 2, 3, 7, 17 and 50** — 47/86/58/52 at every one — **with 0032's absolute rule
  run through the same sweep as a positive control**, where it collapses: k=3 gives 0/47/135/61, k=7
  gives 0/0/47/196, and **at k=17 it puts 100 per cent of the catalogue in `common`**.
* **Run BACKWARDS on 0032's own world** (70 goods, 834 rows, μ = 11.914) the new law derives
  ≤2 / ≤5 / ≤11 against the ≤2 / ≤5 / ≤12 that 0032 chose by hand. Two of three thresholds
  reproduced exactly, the third off by one.
* **The old function is DROPPED, not overloaded.** `rarity_from_producers(int)` no longer resolves,
  so no caller can pick between the old law and the new. The law stays IMMUTABLE because the table
  read was lifted OUT of it into an argument. `world.snapshot` and `world.market` are not re-cut —
  they already ask the one authority.
* **Cost, stated:** `world.snapshot()` 1,437 → 2,377 ms (+65 per cent), paid once per session;
  `world.market(port)` unchanged within run-to-run spread.

### 0053 — the quay prices its neighbours once

`world.market()` drew ONE screen by calling `world.pct_of_neighbours` 243 times, which called
`world.mid_price` 9,720 times, **each of which re-read four `public.wc` knobs** — **38,880 plpgsql
calls for four numbers that cannot change while the statement runs.** Broken down: the 9,720 mid
calls cost 514 ms, of which **321 ms is the knob reads — 62 per cent of the mid's cost.** At 70 goods
that was 2,800 calls and invisible.

`explain (analyze, buffers)` on `select world.market(BOR)`: **336,872 buffer hits to serve 243 rows,
305,396 of them (91 per cent) inside the `nbr` CTE.**

The §G.1 mid arithmetic moves into `world.mid_from_terms` — **SQL, IMMUTABLE, no SECURITY DEFINER and
no SET clause, which is exactly what PostgreSQL needs to INLINE it** — and %NBR gains a set-valued
body, `world.pct_of_neighbours_at`, that derives the neighbourhood and the five knobs ONCE per quay.
The scalar keeps its name and COMPOSES the set through a nullable narrowing argument; nothing is
copied. 0019's CTE fence is **not** the problem and is kept.

| port | neighbours | before | after |
|---|---|---|---|
| Bordeaux | 42 | 1,442 ms | **241 ms** |
| Bilbao | 39 | 1,250 ms | 218 ms |
| Goa | 36 | 1,420 ms | 223 ms |
| Lisboa | 24 | 881 ms | 250 ms |
| Malé | 8 | 845 ms | 247 ms |
| Callao | 0 | 584 ms | 188 ms |

**The guard is the buffer RATIO and the deployed shape, never a millisecond** — a second controlled
run read 1,095 → 336 ms at Bordeaux where this one read 1,442 → 241, a factor of 3.3 against a factor
of 6.0, and a wall clock that swings 1,066 ms to 2,740 ms on the same call twenty minutes later
cannot gate anything. The invariant is **331,470 buffers → 40,530 for one read of Bordeaux, 8.2×**;
the guard demands 3×, because the break-test harness reads 5.8× and the old shape scores about 1×.

**All 54,432 mids in the world are proven byte-identical** against a pre-image captured in the same
transaction, alongside a 7,290-row hypothetical-stock sweep, 268 answers through the scalar door, and
the FULL `world.market` payload byte for byte at six ports including the crowdedest neighbourhood and
an empty one. And the inline precondition is asserted rather than assumed — SQL, IMMUTABLE, not
definer, no proconfig — because otherwise 9,720 real function calls silently come back.

### 0055 — what these waters breed, landed DARK

`public.seas` carries four spatial facts. Only `hazard_base` and `piracy_index` were read by any rule,
and those two took **exactly three distinct value-pairs across all 51 seas**:

    0.0080 / 0.2000 → 36 seas      0.0180 / 0.1200 → 8      0.0120 / 0.4500 → 7

**71 per cent of the world's water was mechanically the same water**, so the Strait of Malacca — the
game's only danger 5, *"thick with pirates"* — drew from the same bag as the Baltic. And the calm was
35 per cent of everything, everywhere. `seas.danger_level` and `seas.note`, authored per sea by 0040
for exactly this, were **read by no rule at all**.

Each kind row gains three response numbers and the mix is DERIVED —
`mix_base × (1 + mix_danger·D + mix_raiders·D·piracy)`, `D = danger_level / 5` — rather than authored
in a per-(kind, sea) table, which would have been **51 × 8 = 408 hand-written numbers free to drift
from the danger scale they restate**. **Ten distinct mixes where there were three.**

**`mix_raiders` is an INTERACTION, and that is the whole reason it is one:** a plain piracy term puts
corsairs in the Arctic (danger 4, piracy 0.12). Raiders need lawless water AND hard water at once, so
the Arctic stays at 9.3 per cent while Malacca reaches 25.8 and the Baltic sits at 7.0.

Five new kinds against 0035's catalogue: **FAIR_WIND — the first event kind in this game that is not
a loss** — plus CONSORT, DERELICT, FOUL_WATER and SHOAL_WATER. Every one reads back out of
`voyage.report_line` with no code edit, which is the claim `NAVIGATION_PLAN:173` makes about 0035 and
this file proves on real payloads.

**IT IS DARK, AND ASSERTED SO.** `voyage.hazard_roll`, `voyage.settle` and `voyage.report_line` are
byte-identical after this file; the rolled set is still exactly {STORM 0.40, CALM 0.35, PIRATES 0.25};
the live draw still answers 0006's CASE on all 50,000 (r, piracy) pairs; `voyage.encounter_at` has
**zero callers**, probed on comment-stripped `prosrc` with a positive control. **No voyage yields one
ducat differently because this file ran** — deliberately, because another worktree was measuring what
a first voyage returns and moving the mix under that measurement would have invalidated it.

The panel that landed with it says **WATER, not ships**, and the header says why: a contact means an
actor and that seam is unbuilt. Two dishonest panels were refused — one listing the days ahead (it
hands the player the dice, and a look-ahead is not even authoritative in this chain) and one printing
a dark mix. What it shows is frozen at departure: the seas her course still has to cross, the
distance to each, the 0040 tier as countable pips, and the sea's character in the world's own words.

### 0054 and 0056 — the balance figure this project has quoted for a week was measuring the harness

This is the most important thing found today, and it invalidates a number in our own documentation.

**THE GATE CRIED WOLF FIRST.** On an unchanged chain, `BALANCE_MEDIAN_IN_BAND` measured
**15.1 / 9.0 / 12.4 / 14.4 / 12.4 / 12.1**, once 16.2, and on 2026-08-25 the same bytes gave 18.3 and
then 14.1 against a 4–16 band. `public.tick_market_drift` moves every price by `random()` deliberately
and the chain's own self-asserts call it while applying, **so every `db:apply` dealt a different
market**. `tests/rpc.firstSession.spec.ts` had the identical defect and had never been given proof
04's fixture.

**0054 built ONE authority for holding it still.** `proof.pin_market` (`scripts/db/market-fixture.mjs`)
redraws every row from the distribution the real process settles into — the OU stationary law, clamped
as 0010 clamps it, keyed on the AUTHORED port and good codes so the market is the same on every run
and on every machine. The forty lines of Box-Muller that stood inside proof 04 are gone from it;
proof 04, proof 05 and the first-session spec all call the one function now. The drift is **replaced,
never removed** — proof 04 records that a flat market is not "the economy without noise", it is an
economy with less trade in it than the game ever has (36 routes out of Lisboa drifted, 20 flat).
Measured: two runs on the same apply are IDENTICAL, and three separate applies — each with a fresh
world secret and fresh port and good uuids — all report **37.4 / 7.0 to the digit**. **No migration
was cut: nothing in the shipped game changed, and cutting one to look busy would have been a lie in
the chain.**

**AND PINNING IT EXPOSED WHAT THE LOTTERY WAS HIDING.** Driving the chain's own tick forward one slot
at a time from a freshly applied world:

    ticks (10 min each)     0       1       2       4       8      16      32
    sd(drift)           0.0210  0.0442  0.0566  0.0706  0.0827  0.0890  0.0905
    median voyage        13.2%   20.2%   21.1%   28.8%   32.5%   34.1%   35.2%

**A FRESHLY APPLIED CHAIN IS NOT A LIVE WORLD.** It has taken about one drift step on the **14,980**
market rows 0003 seeded and **none** on the **39,468** that 0041 added, so **72 per cent of its prices
sit at exactly drift 0**. The 12–18 per cent this proof reported was a measurement of how many ticks
the harness happened to run. A world whose clock has been running for about two hours — which is
every deployed world, since `pg_cron` winds the tick and `world.market()` winds it too on every read —
sits at `0.04 / √(1 − 0.81) = 0.0918` and pays about **37.4**.

**AND THE DECIDING NUMBER IS NOT THAT ONE.** 37 per cent is over twice the designed pace, but a pace
can be argued about. `BALANCE_DISTANCE_PAYS` could not be:

| | long legs (>800 nm) | short legs (<400 nm) | long / short |
|---|---|---|---|
| one drift step | 10.80% | 3.26% | **3.31×** |
| the settled market, σ 0.040 | 18.87% | 16.19% | **1.17×** |
| the settled market, σ 0.020 | 9.66% | 5.88% | **1.64×** |

This is a game about carrying goods from where they are made to where they are not. **At σ = 0.04,
crossing 800 nm of ocean was worth 17 per cent more than staying inside 400, where the world's own
geography makes it worth three and a third times as much.** A knob that drowns the premise is not a
balance preference.

**0056 pulled `drift_sigma` 0.040 → 0.020.** One row of one table; it supersedes the value 0001 seeded
at `0001:159` and nothing else — not `drift_theta`, not `drift_clamp`, not a spread knob, not an
affinity knob, and not one stored price, because every price is derived on read.

* **Geography measurably recovers,** and the shape of what the quay offers moves with it: the long-leg
  premium 1.17× → **1.64×**, a 40 per cent relative gain, while **85 near routes fall to 55 and 360
  far ones rise to 405**. Less noise does not merely pay less — it pays less for staying home.
* **THE AUTHORED ECONOMY WAS ALREADY DOING EXACTLY WHAT IT WAS DESIGNED TO DO.** On a flat market the
  gradient reads **7.0 per cent at every sigma setting, to the digit**, against the 7.5 that
  `0005:125` tuned the affinity knobs to. Everything above 7.5 was noise — **and flattening the
  gradient to compensate, which is what 0048 did, would have made the geography WORSE while leaving
  the printer running.**
* **The claim was split into two markers rather than widened.** `BALANCE_MEDIAN_IN_BAND` is now
  **13.0–20.0 on the settled market and says out loud that it is a REGRESSION TRIPWIRE**, not a
  statement of what a voyage ought to pay. The design's own claim did not disappear: it moved to
  **`BALANCE_GRADIENT_IN_BAND`**, which measures the FLAT market — the thing the affinity knobs
  actually govern — inside the original 4–16, where it reads 7.0. The gap between them is the drift
  windfall, and every proof run now prints it. The band's width is chosen from the sweep, not from
  taste: the neighbouring settings pay 12.5 and 21.5, so 13.0–20.0 is the widest band that still
  refuses a quarter-sized error in the knob in either direction.
* **The self-assert does not read the knob back, it watches it work.** The market is flattened, the
  chain's own `tick_market_drift` is run, and the measured sd must land within 0.9–1.1× of 0.02 on at
  least 14,000 moved rows — **and the same probe with 0.04 restored must NOT land in that window**,
  which is the positive control that makes the first number mean anything. Both probes unwind to a
  savepoint; only the number escapes. The first draft asserted "one knob moved" from `updated_at` and
  `scripts/db/breaktest-0056.mjs` walked straight through it, so it now photographs the whole knob
  table before and after.
* **Rejected, with figures rather than opinions:** the affinity knobs (0041 flattened the gradient 30
  per cent and the median barely moved); widening the spread (spreads average 3.6 per cent against a
  30-point overshoot); `drift_theta` (memory, not size — the market would flicker rather than wander);
  `drift_clamp` (it bound on well under one per cent of rows); and moving the band and leaving the
  economy alone, **which was the previous slice's conclusion and is superseded by this one — a band of
  30–45 certifies the money printer the proof exists to prevent.**

**THE OWNER RULED 0.020 OVER 0.015.** The measurement favoured neither on its own: 0.015 pays 12.5
(mid-band rather than at its ceiling), recovers geography further to 1.96×, and keeps a fully
bargained trader inside the designed 4–16 where 0.020 does not (15.7 + proof 06's 2.7 = 18.4).
Against it: **it thins the near market hard — 39 short routes against 55 at 0.020 and 85 at the old
setting — and that is the water a new captain starts in.** 0.020 shipped; the rest is recorded so a
second step needs no new measurement.

Five `db:proof` runs after it landed: **61/61 markers, median 15.7 and distance 9.66 / 5.88 identical
in every one.** The lottery is dead.

### KNOWN, STATED, NOT HIDDEN

* **0055 is DARK, and lighting it is one migration and four statements** — named in its own header so
  the next hand does not have to work them out: (1) `create or replace function voyage.hazard_roll` =
  this file's `voyage.encounter_at` body, which is written to be dropped in; (2)
  `update public.voyage_event_kinds set is_rolled = true, roll_weight = null where in_sea_mix`, which
  0035's closure trigger forbids, **so the same slice must also drop
  `voyage_event_kinds_weights_close` and `roll_weight`** — once the mix is the draw, a flat weight is
  a second authority and must not survive; (3) `voyage.settle` gains one arm per new kind, five arms
  (FAIR_WIND subtracts delay hours, FOUL_WATER starts water over the side, SHOAL_WATER takes
  durability, DERELICT and CONSORT touch no ship); (4) the map panel gains the mix as a fifth fact per
  row. Measured cost of doing it: **Barbary raid-days 43.0 → 20.4 per cent of event-days**, home
  waters 33.0 → 7.0, Malacca 43.0 → 25.8. **The frequency of event-days does not move at all** —
  this changes WHICH thing happens, never HOW OFTEN something does.
* **`public.good_rarity` is now the largest single item left in `world.market` — 87 ms of the ~240
  that remain** (`supabase/migrations/20260818000053_the_quay_prices_its_neighbours_once.sql:164`).
  It got there honestly: 0051 made it derive the world's scale, and 0032's callers ask it once per
  good. 0053 named it and did not fix it, on purpose: 0053's brief was the %NBR regression, and 0051
  was a day old and is the newest authority in that area. It is a real cost, it is a different slice,
  and it is written down so the next hand does not have to measure it again.
* **`Strait of Gibraltar` still falls outside the hit reach** (`src/chart/glyphs.ts:88-93`). Its label
  measured **119.6 px wide**, so its far end is **129 px from the mark** against a 38 px radius.
  **The honest fix is not a bigger radius** — it is hit-testing the label's own BOX, which needs the
  label PLAN (`src/chart/labels.ts`, currently planned inside `ChartCanvas` against the selection and
  the chrome). Recomputing that plan at tap time would be a second author of where a name is, and the
  two could disagree about which names were even printed. It stays one authority and one radius
  **until the plan is lifted out of `ChartCanvas` for both**.
* **Bristol was not the only one, and it was not even the worst — there are FORTY.** Counted off
  0052's own `sea_reaches` rows: **40 harbours still snap more than 20 nm to sailable water, and 13
  of them more than 30 nm.** The four largest are **Longyearbyen 67.68 nm, Hanoi 58.68, Khambhat
  57.77, Tokyo 47.69**, then Patras 47.21, Trondheim 45.98, Izmir 40.29, Amsterdam 35.47. Every one
  of those is a land-exempt head allowance of exactly the kind that let Bristol sail across
  Somerset, and the fix for each is the same shape 0052 used: a CHANNELS entry for the water that is
  really there. **None of them is cut, and this census is not written down anywhere else** —
  `scripts/build-sea-migration.mjs:298` prints the count to the console at generation and no file
  keeps it, so it has to be recounted from the data each time somebody wants it. Do not confuse it
  with the *"the last 67 nm are the approach to Longyearbyen"* notes in 0041's leg rows: those are
  the retired graph's authored detour allowances, a different quantity from a different model.
* **The rebuild-with-image path is proven in Node, not in a browser.** `tests/db.image.spec.ts:5` says
  so in its own first line — *"PURE UNIT SPEC. No `page` fixture, so Playwright runs it as a plain
  Node process"* — and the PostgreSQL and the tarball are real, but no browser has been driven through
  a cold boot off the image. The certification, the two wounded-image positive controls and the
  fallback are all real; **what is not recorded is a human or a browser arriving at a live purse in
  7.1 s.**
* **The map's ratio control has not been driven on production.** The unfold chain was verified on the
  live game today (see `OWNER_REQUESTS` rows 45/46); the ratio block landed after that drive and is
  built-not-verified.
* **`world.snapshot()` costs 0.9 s more per session** than it did yesterday, paid once, and that is
  0051's price for a rarity ladder that scales. Stated rather than absorbed.

### WHERE IT IS

> **CORRECTED by D26, above.** This section was true when written; it is not true any more. The
> client code was pushed and the SITE deployed later the same day (`origin/main` at `15bd8c3`).
> **The database line is still correct as written below** — production stayed on 0050 through the
> push, and still does: pushing the frontend does not deploy migrations, and a later Postgres-17
> blocker in 0053 (also D26) now stops the migration chain from reaching production at all until it
> is fixed.

**MERGED TO LOCAL `main`. NOT PUSHED. NOT DEPLOYED**, at the time this section was written. As of
writing, local `main` was **25 commits ahead of `origin/main`**, which sat at `d3463da` — *"A
refusal is two numbers and a verb"*, migration 0050.

What that meant concretely: **production was running the 45-migration chain** that D24 recorded and
probed with the anon key on 2026-08-25. **0051, 0052, 0053, 0055 and 0056 were not on it**, and,
per D26, still are not — so the live game today is still paying the ~37 per cent first voyage,
still tiering 54.7 per cent of its catalogue as exotic, still letting Bristol sail across Somerset.
**The nav bar claim no longer holds**: the frontend deployed with D26, so the live site now draws
the one-row six-cell bar even though the database it talks to is still on 0050.

---

## 2026-08-24 — D24: the sea becomes a free plane — the clock ×20, ONE raster, ONE mover, the graph deleted, and a refusal that is two numbers and a verb

Six migrations, **0045–0050**, and four of them REPLACE a model rather than extend one. (0050's hunks
were sliced on 2026-08-25 and it committed that morning as `d3463da`; it is the finish of this day's
work and is recorded with it rather than alone.)

**THE THREE ASKS, in the owner's own words:**

* *"make the speed of moving ships faster 20 times, for faster testing"* → 0045.
* *"it should go by sea without the fixed route — but fastest way possible. Also, in map, i should
  be able to pinpoint anywhere in the ocean to make a fleet move."* — said three times
  (OWNER_REQUESTS rows 41–43) → 0046, 0047, 0048, 0049.
* *"too long. make it very concise. This concise concept will have to be applied to all aspects of
  the game. Always show in graphics, concisely."* — said of E_ENDURANCE's four-clause paragraph →
  0050.

**THE DEFECT THEY REPLACE.** The game sailed a fixed graph of 782 precomputed legs between ports, and
the graph was measurably wrong: it routed Lisboa→Nagasaki **over the North Pole at 88.6°N for 7,565
nm**, where the honest water is **12,989.3 nm round the Cape of Good Hope at a maximum course
latitude of 38.7°N**. It drew **532 of its legs over land** and silently teleported **41** river-port
approaches (Suez 72 nm, Bristol 65, Hanoi 59) at no cost in time or stores. Every one of those
numbers gated an endurance check and priced a trade route.

### 0045 — the world runs twenty times faster

* `time_compression` 480 → 9600. A voyage-day WAS three real minutes; it is **9 real seconds**, and
  the self-assert DERIVES that from the knob rather than retyping it — a second copy of that
  arithmetic is how 0028's two clocks came to disagree by a factor of sixteen.
* **A knob, not a dev flag.** The server owns how fast time runs (DESIGN D.1, `voyage.position`
  closed-form); a client "test mode" would be a SECOND authority for the rate at which the world
  turns. The header says out loud that this reaches production on the next deploy, and that the way
  back is a superseding migration — not a flag, and not an un-deployed prod.
* **What made it more than a one-line UPDATE:** `eta` is STORED at departure, but the day boundaries
  are RE-DERIVED on every read and clamped by `least(v.eta, …)`. Raising the knob under a fleet
  already at sea splits her in two — every remaining day completes at once, her hazards all roll in
  one tick, and she then sits becalmed off her destination waiting for a stored `eta` computed at the
  old rate. So every SAILING voyage is re-ETA'd here through `voyage.recompute_eta`, the ONE ETA
  authority, and only the arrival instant moves.
* **The probe is non-vacuous by construction.** A fresh chain has no fleet at sea, so the re-ETA loop
  would run zero times and prove nothing: a real house is founded and put to sea inside a
  subtransaction, the knob is wound BACK to 480 (the arrival must move LATER) and forward again (it
  must come back in) — both directions, so the ETA is proven to FOLLOW the knob rather than merely
  differ from a number typed in the file — then the whole probe rolls back and a delta assert proves
  it left no row behind.
* **Deliberately untouched:** `game_day_seconds` (2880), the CALENDAR clock that fairs and seasons
  run on. The owner asked for ships to move faster, not for the seasons to blur past. The consequence
  is stated rather than discovered later: the two clocks differed by 16× (0028) and now differ by
  0.3× — a fair lasts many more voyages than it did.

### 0046 — the water knows the way (generated; `scripts/build-sea-migration.mjs`)

* **`public.sea_raster`** — 1,440×720 cells at 0.25°, a 2-bit passability mask per cell packed
  LSB-first in **259,200 bytes**. Bit 0 SEA = sailable (Natural Earth land, CHANNELS forced open,
  Arctic ice closures, Antarctic pack south of 60°S). Bit 1 POLAR is the open polar margin — DATA
  for the ice and region systems to come; **it gates nothing yet, and the migration that gives it a
  reader must say so.**
* **`public.sea_reaches`** — one row per place: the sailed nm to every other place, flooded by the
  one pathfinder (`src/lib/sea`) over this very raster, straightened by line-of-sight and measured as
  the polyline's great-circle length. Plus `snap_nm`, how far the true harbour coordinate sits from
  sailable water (Suez 0.00, Bristol 64.55) — and it is **INSIDE** every reach figure, because each
  path starts and ends at the true coordinate. The silent snap is charged, never skipped again.
* **`voyage.path_nm`** is THE measure of a polyline — the server never takes a client's distance —
  and **`voyage.path_refusal`** is THE water-legality of one: every segment sampled at half-cell
  steps (≤ 7.5 nm) by the same linear interpolation `voyage.position` uses to place the ship, so the
  line judged is the line sailed. The ends are exempt only by the MEASURED approach allowance, never
  a fixed guess. Neither is granted to a client.
* **The canal controls, printed on every apply.** There is no Suez and no Panama in 1550, and nothing
  encodes that: it falls out of the land. **Alexandria→Aden 11,050 nm** round the Cape;
  **Veracruz→Acapulco 12,398 nm** round the Horn. LIS→NAG is asserted over 12,000 nm — under it and
  the Arctic is open again.
* **The two rasters are made to agree.** Cell-for-cell against 0040's sea-membership raster at
  generation, and at apply on eight named control cells read back through `get_bit` (mid-Atlantic,
  the middle of Iberia, the Bosphorus, the Siberian arctic, the Barents Sea, the Antarctic pack, the
  South China Sea, the Sahara), four of them re-asked through `voyage.sea_at`. Then the properties:
  every place reaches every other, symmetric, and never shorter than the great circle.

### 0047 — the sea is a free plane (generated; `scripts/gen-0047.mjs`)

* **The split is measured, not chosen.** A\* in plpgsql costs **302 s** for Lisboa→Calicut; the same
  search in the browser costs **≤166 ms**; VERIFYING that a path is all water costs **0.02 ms**. So
  the search runs where it is cheap — the client PROPOSES a course — and the authoritative acts stay
  on the server: verify → measure → gate → depart. **A client cannot gain by lying:** land is
  refused, a longer course only costs its own player days and stores, and a shorter water-legal
  course is simply a better route. With no course attached the straight line is tried, which is free
  and correct exactly when it verifies; otherwise E_NO_COURSE.
* **The FOUR graph movement authorities are DROPPED, not joined** — `voyage.route`,
  `voyage.route_direct`, `voyage.path_from_nodes` and `voyage.reach_from(uuid, int, uuid)` — with
  `sail_refusal`, `depart`, `position`, `cmd.do_sail`, `cmd.divert`, `cmd.issue`/`cmd.preview` and
  `world.trade_routes` superseded whole or sliced. The predecessor's recorded catastrophe was four
  overlapping movement paths.
* **Any water point is a destination.** Fleets carry `lat`/`lon` and an ANCHORED status; `cmd.divert`
  turns her AT HER POSITION (truncate, settle through the one arrival arm, clear the stale queue, one
  SAIL through the one parser). 0037's node-turn existed only because routing from a point was
  impossible; it is not any more.
* **The slice-and-replace method:** every superseded body is edited by hunks that must occur EXACTLY
  ONCE in the DEPLOYED definition (`pg_get_functiondef`), re-asserted at apply time — a drifted
  deployment refuses rather than half-applies. Nothing is retyped.
* **Carried forward:** pre-0047 voyages stored leg REFERENCES and are converted in place to
  legacy-marked segments with the same nm, the same seas and the same frozen speeds — the schedule is
  byte-identical, so proof 01's offline settlement rests exactly where 0006 put it. A computed course
  is still a FIXED course once departed.
* **The self-assert plays a whole game.** A real house was refused a straight course across Iberia as
  E_LAND *through `cmd.issue` itself*, refused an unplotted cape passage E_NO_COURSE and a mis-joined
  course E_OFF_COURSE; then SAILED Lisbon–Cádiz on a verified water course whose server-measured
  total agrees with the reach table to 3%; a homeward SAIL queued at sea departed itself on arrival;
  she PINPOINTED 33,−15, ANCHORED on the very point, was refused BUY there as E_NOT_DOCKED, and
  sailed home from the anchor; on thin stores the same passage was refused for the ROUND TRIP; the
  helm answered MID-OCEAN, truncating at her position to the mile; a leg-era voyage converted with
  its schedule byte-identical; and the land guard walked every stored course and BIT a planted
  straight Lisbon–Barcelona voyage.
* **`world.trade_routes` re-cut:** the scan radius is now SAILED nm over `sea_reaches`
  (`sea_scan_radius_nm` = 1,700, the measured median horizon of the old 2-leg scan), so the Asian
  trade stops being priced at half its true distance.

### 0048 — the quay reprices the honest sea

Honest water reaches better-paying markets inside the same first-voyage horizon than the 782-leg
graph did. Proof 05's median first-voyage return, tuned to 13.5–14.8% under the graph (D21), measured
**14.6 / 14.7 / 15.2 / 15.5 / 16.8 / 17.8 across six full runs** — mean ~15.8, straddling the 4–16
band's ceiling. The band is the design and the affinity knobs are the sanctioned lever (D11/D21
precedent), so the sweep is the evidence (`scripts/db/tune-balance.mjs`, 14 top-tier ports, the same
600 nm honest reach the proof measures):

| knobs (producer / home / span / reach / curve) | median | p25 | p75 |
|---|---|---|---|
| 0.92 / 0.99 / 0.85 / 9000 / 0.80 — D21's, in force | 8.9% | 7.6% | 9.7% |
| **0.93 / 1.00 / 0.76 / 9500 / 0.88 — CHOSEN** | **6.2%** | 5.1% | 7.1% |

−30% relative on the sweep's own statistic. Every `port_goods.affinity` is recomputed through
`world.affinity_for` — THE function the seed used, so the world cannot drift from its own rule —
`stock` is CLAMPED DOWN to a fallen target and never re-seeded upward (stock is player-made state and
a reprice must not mint goods), and `drift` is deliberately NOT reset: it is live market state, and
zeroing it would move every price at once for no reason the ledger could name.

### 0049 — the graph is history

* **`public.legs` is dropped**, and in the same commit `data/sea-routes.json` and its generator
  `scripts/build-sea-routes.mjs` are deleted, the growth generator stops deriving legs, and the world
  guard is repointed — **keeping its planted-drift positive controls, because a guard that cannot
  fail certifies nothing**.
* **Why it is its own migration.** 0047 left the table "as history, with no reader", which is exactly
  the state the no-spaghetti law forbids: a second, dead authority for what water connects to what,
  which every future world change would have to keep regenerating (0041 regenerated
  `sea-routes.json` for no reader) and which the world guard would keep certifying as if it mattered.
* **It refuses to drop blind.** ≥100 leg rows must exist (a drop that deletes nothing is a different
  migration than the one this file documents); **no live function body may name `public.legs`**,
  asked of `pg_proc` rather than of my memory; and no stored voyage path may still be leg-shaped.
* History is not edited: the applied migrations that create and seed the table still run at their own
  chain positions, where it exists.

### 0050 — a refusal is two numbers and a verb

The owner, on this sentence — *"Gaivota carries 2.9 days of stores, and there is no chandler where she
is bound — the round trip is 28.7 voyage-days; you need 33.0 — PROVISION first"* — said: *"too long.
make it very concise. This concise concept will have to be applied to all aspects of the game. Always
show in graphics, concisely."* What the player needs is a bar, two figures and a verb:
`▁▁▁▂ 2.9 / 33 days  [ PROVISION ]`.

* **THE LAW:** the client must NEVER parse a served sentence for numbers. A client that regexes "2.9"
  out of prose is a second author of the refusal, one wording change from lying — the same defect
  0030 (crew) and 0033 (shipyard) had to undo. So the numbers travel as DATA, from the one place that
  computed them.
* **Neither obvious mechanism works alone, and reading the code is what settled it.** Returning the
  figures from `voyage.sail_refusal` does not reach the client, because `cmd.do_sail` RAISES and a
  returned value does not survive a raise — `do_sail` would have to RE-DERIVE have and need for the
  raise, a second arithmetic one knob from disagreeing with the sentence printed beside it. Carrying
  them only in `PG_EXCEPTION_DETAIL` drifts the other way, because `sail_refusal` must keep RETURNING
  (`world.trade_routes` asks it as a silent `… is null` predicate and cannot catch an exception per
  candidate port), so the author of the sentence and the author of the figures would be two different
  functions with nothing making them agree. **So: the return value for the AUTHORITY, the DETAIL for
  the one crossing that already exists.** `voyage.sail_refusal` now returns code, sentence and figures
  as ONE value; `cmd.refuse(code, sentence, figures)` is the ONE raiser — three arguments of one
  statement cannot drift apart — and `cmd.refusal_caught(message, detail)` is its inverse.
* **WHAT THE FILE PAID FOR ITSELF WITH.** "Split a raised refusal into an envelope" had **SIX
  hand-copied definitions** — `cmd.execute_order`, `cmd.preview` (twice), `cmd.issue`,
  `cmd.provision_preset_save`, `cmd.run_standing_provision`. Five were found by reading; **the sixth
  was found by this file's own guard, which asks the catalogue instead of my memory — which is the
  whole reason it asks the catalogue.** All six carried the same latent bug: when a message did not
  start with `E_CODE:` the code fell back to `'E_PARSE'` and the sentence was still cut at
  `length('E_PARSE') + 2`, so an unexpected PostgreSQL error reached the player with its first eight
  characters shaved off — *"division by zero"* → *"by zero"*. One authority, one fix.
* **The figures law is enforced, not documented.** `cmd.figures` raises if `have > need`, if `need`
  is not positive, or if the unit is anything but a bare lower-case NAME (`days`, `t`, `ducats`,
  `crew`, `depth` — never a sentence). A refusal always means have < need, so the bar is always
  have/need and always short.
* **`public.orders.error_figures`** — a failed order is history and its figures are part of it, so
  `cmd.issue` and `cmd.queue` read the order ROW rather than the exception.
* **The sentences lose two things they should never have carried:** the ARITHMETIC (E_ENDURANCE's
  sentence now contains no digit at all — that is the bar's job) and the FIX (`cmd.fixes()` has been
  the one author of "→ do this instead" since 0008, and the sentences were repeating it). What they
  KEEP is the REASON, which is the one thing neither a bar nor a fix can say: *no chandler where she
  is bound* is a real fact about the world and it survives, behind the ⓘ.
* 14 live bodies were sliced by occurs-exactly-once hunks. `world.trade_routes` and proof 05 needed no
  change at all — `… is null` reads a jsonb exactly as it read a text — and `voyage.path_refusal`
  keeps returning text, because E_LAND / E_OFF_COURSE / E_NO_COURSE are not arithmetic and there are
  no two numbers to draw.

### THE CLIENT, in the same window

* **The map now updates as often as the world moves.** The owner: *"i want the location of my fleet
  moving in map to be shown more often, updated more often."* The read interval was a flat 30 s whose
  own comment justified it as "well inside a voyage-day (three real minutes at TIME_COMPRESSION
  480)" — and 0045 made a voyage-day nine seconds, so thirty seconds became **3⅓ voyage-days between
  reads**, and a short passage could begin and end between two of them while a fleet under way jumped
  across the chart instead of crawling. The number was a rule evaluated once, by hand, against a knob
  that has since moved — so the cadence is now DERIVED from the served clock (four reads per
  voyage-day, clamped between 3 and 30 s) and re-arms if the knob changes under a running tab.
  Measured in the running game: *"read 2s ago"*, then *"read 0s ago"* four seconds later.
* **The whole send happens on the map** (OWNER_REQUESTS rows 45/46). Tap a place → **Send fleet** →
  her fleets unfold, each row dry-run against THIS destination through `cmd.preview` over the same
  proposed course the send will carry → press a fleet → 0034's standing-order presets unfold beneath
  that row → press one and she goes. `SailHere` is deleted, replaced. It COMPOSES what exists — the
  same order draft, the same issue path, the same `applyPreset` the FLEETS galley presses — and
  nothing on the map writes a preset. One thing fixed after driving it: the preset row carried the
  caption *"press one - it sets her order and sends her"* — a sentence explaining a row of buttons,
  on the very screen that had just been called too wordy. The chip is named for what it does (**Keep
  and send**) and the reason moved behind the dot.
* **`RefusalNote`** draws the bar from `refusal.figures` and falls back to a compact badge when they
  are absent. It was built waiting for 0050's contract, which is why 0050 is the migration it is.

### THE FLAKE THAT MADE THE GAME UNOPENABLE

The browser refused to boot: MIGRATION FAILED at 0036, *"after settling past the ETA the fleet is
SAILING at (nowhere)"*. That reads like a broken sea place and is nothing of the kind. 0031 rotates
the world secret on every fresh apply and `voyage.rng` is keyed on it, so the hazards rolled for a
probe's passage differ every run — a storm delayed her past the instant the probe settled to, and she
was still at sea when the assert looked. **0034 hit this and fixed it; 0037 hit it and fixed it; 0036
was written between them and never got the fix.** The pattern was known, written down twice, and
still landed a third time. Zeroed inside the rolled-back probe; three consecutive clean applies. A
failed migration is a world that will not boot, so this did not merely red a gate — it made the game
unopenable, intermittently, which is the worst way for a flake to present.

### KNOWN, STATED, NOT HIDDEN

* **The two clocks now differ by 0.3×, not 16×.** Ships were made twenty times faster and the
  calendar was not. If the seasons should scale too, that is a second decision and nobody has taken
  it.
* **Proof 05's balance band is still a lottery, and the mechanism is now measured rather than
  argued.** The sanctioned lever was pulled (0048) and the proof's median barely moved (15.9 / 17.3
  after); zero the drift and the same world's median drops to **8.8**, because the statistic is a max
  over ~243 goods × ~8 ports of drift-noised gaps and is therefore dominated by the drift amplitude,
  which no affinity knob touches. Zeroing drift inside the proof exposed a second finding
  (`route_scan_keep=3`'s shortlist drops the best trade at drift 0), so the two must land together,
  in a balance slice of their own.
* **The POLAR bit gates nothing**, and the ice/season masking question (navigation research P.10) is
  unchanged: a fleet can still pinpoint absurd latitudes on the open polar margin.
* **Bristol's approach is now MEASURED and charged** — 64.55 nm, inside every one of her reach
  figures, rather than teleported for free — but the Severn entry in `sea-grid.mjs`'s CHANNELS that
  D22 flagged is still not cut.
* **Rows 45–47 of `OWNER_REQUESTS.md` are BUILT and NOT CLOSED.** Commit `3ddcad1` claims the map
  send was *"driven end to end: the URL never changes at any step"*, and no browser drive of either
  the send flow or the served figures is recorded in this log or in that ledger. That file's rule 2
  says an agent report — mine included — is a claim, not proof, so the rows stay open until a drive
  is recorded.

### WHERE IT IS

**Applied to production.** Probed on 2026-08-25 against the live project with the anon key alone:
`public.legs` answers **404** — the table is gone, so 0049 ran — and `public.orders.error_figures`
answers **`42501 permission denied for table orders`** where a made-up column on the same table
answers **`42703 column … does not exist`**, so that column exists and 0050 ran. The chain applies in
order, so 0045–0048 are there with them. The chain is **45 files**; the numbering gaps 0038/0039 and
0042–0044 are deliberate and arbitrated by `npm run db:check-versions`, never by counting.
---

## 2026-08-24 — D23: the edited-migration defect — 0003 reverted, the world grows through 0041, and a guard so it can never drift silently again

**THE DEFECT (mine, prior session).** D21 regenerated migration 0003 in place after production had
already applied it. Editing an applied migration does not re-run it, so production kept the
ORIGINAL 70 goods / 214 harbours while every fresh rebuild got 243 — and the ten island ports,
which live in `data/ports.json` but were never regenerated into any migration, existed in **no
database at all**. Everything stayed green while the worlds diverged. The same commit also edited
0005's five affinity knobs in place (`world_config` rows seeded `on conflict do nothing` — a
deployed world keeps the old values).

**THE REPAIR, in one slice:**

* **0003 reverted to the exact bytes production ran** — git blob `eee9091` (commit `d70fe6e`),
  proven byte-identical: sha256 `8f3fc5b4…1118` on both sides, `git hash-object --no-filters`
  reproduces the blob id, `cmp` silent, 119,239 bytes, LF-only.
* **`supabase/migrations/20260818000041_ten_islands_and_a_richer_catalogue.sql`** — GENERATED by
  the new `scripts/build-world-growth.mjs`: measures the baseline by applying the real chain to a
  scratch PGlite, diffs it against `scripts/lib/world-derive.mjs` (the derivation, extracted
  verbatim from build-world-seed so generator + guard compose ONE authority), and emits the delta:
  +10 harbours, +173 goods (~10 renamed), +606/−130 offers, legs +94/−47/~621 re-measured,
  `port_goods` re-derived for every (harbour, good) pair through 0005's one formula, and the five
  knobs reconciled. Self-assert pins the END STATE to the data by set equality with values, both
  directions, plus the derivation rules over every live row. Player rows untouched by construction.
* **THE CODE-THEFT NET.** Diffing derived-vs-applied before shipping caught a real horror: the ten
  islands were inserted alphabetically into `data/ports.json`, and the order-walking code assigner
  let **Chios steal CHI from Chittagong, Port Louis steal POR from Port Royal, Port Royal steal
  PRT from Portobelo, and Tidore steal TRI from Tripoli** — four deployed harbours silently
  renamed. Every port code is now PINNED in `PORT_CODES` (world-derive.mjs); the derivation
  refuses an unpinned port and suggests a free code; a shipped pin never changes.
* **THE STANDING GUARD** — `scripts/db/world-guard.mjs`, run by every `db:apply` and `db:proof`
  (and thus CI's apply-proof): the applied world must EQUAL `data/*.json` — harbours, goods,
  offers, legs (values included), sea places, seas/regions/nations, market coverage — or the run
  fails, with a positive control (a planted dropped-harbour and bent-distance must be SEEN) on
  every run. The drift class of this defect can no longer stay green.
* **`scripts/build-world-seed.mjs` retired to a refusal stub** — running it now exits 1 with the
  history and points at the growth generator. The landmine that produced the defect is disarmed.
* **The production path is REHEARSED as a standing test** (`tests/db.chain.spec.ts`, GROWTH_SPLIT
  = 0041): apply the pre-growth chain (the world production holds), found a house through
  `public.new_house`, BUY real cargo through `cmd.issue`, then apply the growth — the house,
  fleet, cargo and ledger must survive to the ducat while the world doubles around them.

**Numbering:** 0038/0039 are the helm worktree's, 0040 the seas worktree's; growth took **0041**.
The chain spec's LAST pin moved to 0041 with the dated note.
---

## 2026-08-24 — D22: every water answers its sea (migration 0040)

The owner's free-sailing spec (OWNER_REQUESTS rows 42/43) keys piracy, hazards and NPC levels on
WHERE a fleet is — *"different npcs in different areas of the sea - different levels"*, so a late
joiner is never thrown into someone else's difficulty curve. But a point of open water belonged to
NO sea: `data/seas.json` held 51 hand-placed label centroids its own note marks unsurveyed. The
moment a fleet can sail to any water point, the spatial dimension of all three systems would have
silently switched off. This slice makes the answer total BEFORE the mover ships.

### WHAT LANDED

* **`public.sea_cells`** — a sea-membership raster on the SAME 0.25° grid as the water: 720 rows
  of 1,440 bytes, one byte per cell = `seas.raster_ordinal` (0 = no navigable sea). Storage shape
  is the measured one (research P.5: one TOASTed bytea reads at ~843 ms, 720 inline rows at 4–8 ms):
  1,216 KiB heap, no TOAST, `storage main`. Server-private (0035's posture: RLS on, no policy).
* **`voyage.sea_at(lat, lon)`** — the ONE membership lookup, strict (null on land — never a
  navigability answer; the mover's water raster owns that). Not granted to clients: no client
  caller exists; the day a map label wants it, that slice adds world.* + registry + catalog rows
  together. Measured: 0.88 ms per round-trip call, 0.065 ms per sample inside one statement
  (a 500-sample path sweep costs 32 ms).
* **Boundaries are SOURCED** — Natural Earth `ne_10m_geography_marine_polys` (public domain, the
  coastline's own source family): 49 of our 51 sea names match NE exactly; `INDIAN OCEAN` (caps)
  and `Inner Sea` (the Seto) are the only aliases. NE waters we do not model join their nearest
  sea BY WATER (multi-source BFS through water cells — nothing leaks across an isthmus), except
  seven authored, documented folds (Gibraltar/Alboran → Med, Bosporus → Marmara, Bristol Channel →
  Atlantic, Greenland Sea → Arctic, Coral Sea → S Pacific, SOUTHERN OCEAN split at the IHO sector
  meridians). Generator: `scripts/build-sea-raster.mjs`; polygons cached with provenance in
  `scripts/marine-polys.cache.json`.
* **Every sea got a danger tier and a character** — `seas.danger_level` (1 home waters … 5 deadly;
  Malacca is 5, "thick with pirates") and `seas.note` (plain words, a name not a sentence),
  authored in `data/seas.json`. **Both are marked READ BY NO RULE TODAY** in their column
  comments — the takes_effect discipline — with the NPC system named as reader.

### THE NUMBERS

647,913 navigable water cells; every one of them carries a sea except **687 in landlocked pools no
sea route can reach** (the Caspian 628, the inner Salish Sea 28, Lake Maracaibo 8, and 7 smaller
pockets — each unreachable by the mover by construction, drawn loud magenta in the proof renders).
All 228 chain ports resolve within 8 rings; **17 disagree with their hand-declared sea** and every
one is asserted BY NAME in 0040's self-assert, so a silent boundary drift is a red apply. The 17
are genuine boundary facts, not defects — Havana faces the Straits of Florida, Crete's north shore
is the Aegean, San Juan's is the open Atlantic; the port's `sea` stays the editorial market filing
(WORLD_DATA §6), the raster stays the surveyed water.

### THE NET

All seven assert families break-tested red with the real messages recorded (a deleted row, an
orphan byte, an extent-less sea, a port in the Sahara, a blanked control cell, a client grant, and
the disagreement-list delta — which caught a REAL drift during the build: data/ports.json runs 10
island ports ahead of the chain, so the assert is filtered to the ports the table holds at 0040's
position). Proof 08 holds the property against the FINISHED chain for ever, with a positive
control that pokes one byte in-txn and requires the answer to move. Eyeball pass done on the
Channel, Adriatic, Malacca, Gulf of Mexico and Sea of Japan renders.

### KNOWN, STATED, NOT HIDDEN

* `db:apply` flaked ONCE at 0036 during break-testing ("fleet is SAILING at (nowhere)") — the
  world_secret is generated per apply since 0031, so 0036's voyage probe is a per-run lottery: the
  same class as proof 05's BALANCE_MEDIAN row in OWNER_REQUESTS. Pre-existing, now on the record.
* Bristol still reads `english-channel` at ring 4: the Severn estuary is land at raster
  resolution, so Bristol's nearest water is Lyme Bay — the same 65 nm silent snap row 41 logged.
  The honest fix is a Severn entry in sea-grid.mjs CHANNELS (like the Thames and Gironde), which
  belongs to the mover's worktree — flagged, not smuggled in here.
* The far-south shelf water off Antarctica and the pole-side cells NE's polygons do not cover are
  BFS-filled ocean; a fleet could still pinpoint absurd latitudes — the mover's ice/season masking
  question (research P.10), unchanged by this slice.

---

## 2026-08-23 — D21: the catalogue grows to 243 real goods, and the world re-tunes around it

The owner: **"why are there only 70 trade goods? there should be thousand. real-life trading by
regions + 대항해시대 오리진 + 대항해시대."**

### THE COUNT, AND WHY IT IS 243 AND NOT 1,000 — arithmetic, not preference

A port OFFERS its listed goods (cheap there, it produces them) and BUYS anything — that is what
lets a big catalogue live on 214 ports. But the owner's own 4–9-offers-per-port-by-size rule caps
the world at ~1,450 offer slots on 214 ports (tier 1 ≤ 9, tier 2 ≤ 7, tier 3 4–5). At 1,000 goods
that is 1.45 producers per good: ~80% of the catalogue lands in 0032's exotic tier (≤2 producers),
which reds 0032's own no-tier-over-60% assert and makes rarity a label with no information — and
there is no slot budget left for a staples spine at all. 243 is the largest catalogue this world
carries with all four tiers meaning something; the ceiling scales with ports × offers-per-port, so
island ports and any future widening of the offer band raise it mechanically. A second, softer
bound: at kind granularity (a good = a thing a merchant priced as its own article; claret and
malmsey are both `wine`) the real 1500–1650 sea trade yields roughly this many distinct articles —
1,000 would mean vineyard-level near-duplicates, which `data/goods.json`'s own no-near-duplicates
rule forbids.

### WHAT LANDED

* **`data/goods.json` 70 → 243** (+173, every one a real article of period trade with a sourced-
  style note; all 70 legacy ids KEPT — `salt`/`wine` are load-bearing in 0008/0009/0010 and the
  tests). 22 umbrella names NARROWED because their folds were undone: `wine` sheds sake/rum/
  brandy/beer/arrack, `diamonds` sheds rubies/emeralds/carnelian, `sandalwood` sheds camphor/
  benzoin/aloeswood, `iron` sheds lead/coal/muskets, and so on.
* **Roster: every port re-authored to 4–9 offers by size** — 834 → 1,270 specialty rows, each
  defensible at its port (Basra dates, Sakai muskets, Chios mastic via Izmir, Iceland gyrfalcons,
  Bermuda cedar, Makassar trepang…). Measured distribution: 25 common (13+ ports) / 27 uncommon
  (6–12) / 58 rare (3–5) / 133 exotic (1–2) — exotic 54.7%, inside 0032's 60% cap with margin, and
  the island-port slice can only push counts UP (exotic → rare), the safe direction.
* **Migration 0003 regenerated** (243 goods, 1,270 specialties, 136 KB); generator gains the new
  perishables and ONE alcohol mask rule (`wine/beer/sake/rum/brandy/arrack` refused by islamic +
  swahili culture — verified on the compendium: the tiles say so).
* **0005 knobs retuned by measurement, in place** (the D11 precedent): the long tail of one-port
  specialties steepened local gradients and proof 05 read a 16.5% median first voyage — past the
  16.0 band top. `tune-balance.mjs` swept the candidates on the NEW world; prod 0.92 / home 0.99 /
  span 0.85 / reach 9000 / curve 0.80 brings the proof's median to **13.5%** (band 4–16), distance
  still pays (9.26% pooled >800 nm vs 4.61% <400 nm). The 0005 header carries the new sweep table.
  The full suite then ran twice: 51/51 markers both times, medians 14.8% and 14.2%.
* **Proof 04 had a latent seed-shaped constant** the growth flushed out: it filtered the return
  cargo on `base_value * 10 < stake` and then bought a flat 20 tuns — sword-blades passed the
  proxy and cost 2× the stake, the order failed, the queue halted. It now prices the very purchase
  from the quay's own `outlay/qty` and buys the quay's own quantity (docs/NO_SPAGHETTI.md §6:
  derive it, never pin it). 9/9 green.
* **Icons policy is now measured**: the original 70 keep their drawn marks; of the new goods the
  twelve offered at 5+ ports (rye, beer, dates, citrus, coconuts, coir, sappanwood, soap,
  areca-nuts, butter, paper, honey) got new drawn glyphs; the long tail wears its category glyph +
  name + rarity mark — verified rendering, no blank squares. `normalise-goods.mjs` now REFUSES a
  fold key that is a canonical good id (49 stale folds deleted — the `dates`→`dried-fruit` class
  of landmine is dead).

### THE COST, MEASURED

Chain apply: ~178 s in Node (0005's 52,002-row price world is 53 s of it). **Browser cold boot
78.8 s to a live purse** (was ~30–55 s), warm boot 2.4 s — measured chromium 390×844 against the
built bundle. The pre-built database image DEV_LOG has flagged before is now the obvious next
optimisation.

---

## 2026-08-23 — D20: plain words everywhere, goods become blocks, and the useless button dies

Three owner instructions in one sweep: **"overall, check game itself - every aspect, and move simple
words"**, **"make trade goods in blocks as well, not all alligned in sentences - horizontally"**, and
**"read again on top left of the game is useless. remove it."**

### THE `read again` CONTROL IS DELETED, NOT HIDDEN

AppShell already reads the world every thirty seconds and on every tab focus, and `world.fleets()` is
the catch-up — a button asking for something already happening taught the player their tap did nothing.
Removed from MARKET, FLEETS, LEDGER, RANK and the COMPENDIUM (COMMAND holds its own local copy, another
slice's). **The reads the button carried did not die with it**: each screen's extra read (MARKET's
prices, RANK's board, the COMPENDIUM's roster) is now keyed on `readAt`, the world-read's own stamp, so
it re-asks on the same thirty-second beat — which also means a refused board/roster read retries itself,
and MARKET's prices step the drift walk (0029) while the tab is open. The two "read again to try once
more" sentences those retries orphaned are reworded. `live/WorldGate.tsx`'s `ReadAgain` now has **zero
callers** — deleting it belongs to whoever owns `src/live`, which this slice does not.

### TRADE GOODS ARE TILES (`src/components/ui/GoodTile.tsx`)

The market table read each good as a sentence — name, index, price, strung horizontally, with trend and
destination behind a sideways swipe. It is now a two-column field of blocks: the good's own drawn mark
and name as the title, its rarity mark, and the figures labelled beneath (nearby index + trend line,
buy · sell, stock, pays at). The COMPENDIUM's goods face composes the same tile with its own figures
(base, bulk, spoils, refused by), grouped under kind headings instead of spending a column on the
category. **The tile's home is the design system** — `GoodTile.tsx` + `goodTileLayout.ts` — with
COMMAND's good picker as the named next caller (docs/NO_SPAGHETTI.md §7's seam list). Sort orders are
unchanged; `tests/layout.spec.ts`'s MARKET fold proof now counts complete tiles.

### THE WORD SWEEP (one word per idea, no schema on screen)

`%NBR` → **nearby** (COMMAND's own earlier pick, now MARKET's sort chip and how-to card, and PORT's
buy notes — "of neighbours" was a third name); `Yard` → **Shipyard** (0033's word, last client
holdout); `watered and victualled` → **provisioned**; `Presets` → **Standing orders** (with `Order N`
as the default name); `flag:` → **flagship:**; Profile's raw `ready` phase → **open**, `Sea legs` →
**Sea lanes**; Map's `asking the server…` → **checking the passage…**; `pool 35` → **35 at the inn**;
bare culture values get their noun (`latin culture`); `shipyard t2` → **shipyard tier 2**. Also:
REPAIRED's ledger badge was the same red as REPAIRING — a recovery coloured as a wound — and is green
now, and PortFaces' officer bonus now prints through `formatPctPoints` like the compendium's.

---

## 2026-08-23 — D19: the map stops being a picture

Owner, on the Map tab's caption: it *"literally reads `view only · orders on Command` — that sentence is
the screen confessing it is unfinished."* You could see the whole world, your fleet lying in Lisbon and
214 harbours around her, and act from none of them: remember the name, leave the tab, find it in a list.

**The caption is deleted, with the behaviour it described.** Tapping a harbour now offers `Sail here`.

### THE SEAM: THERE WAS ALREADY ONE, AND IT GOT A FOURTH CALLER

`tests/sections.spec.ts` forbids a screen importing a screen, so the map cannot reach into COMMAND. The
honest mechanism is a hand-off — and this repo has exactly one: `domain/order`'s draft, written by FLEETS,
PORT and MARKET as `handOff(intent)` then `navigate('/command')`. **Nothing new was built to carry an
order off the Map tab.** Three alternatives were considered and rejected, each for the same reason — each
would be a second place a pending order lives:

| rejected | why |
|---|---|
| a field on `live/worldStore` | two drafts. The store is the WORLD; it is not the order being made |
| router state (`navigate('/command', { state })`) | invisible to the draft's `sessionStorage`, so a reload loses an order the composer would otherwise still hold |
| a search param (`?verb=SAIL&dest=CAD`) | the URL becomes a second authority for the draft **and** needs parsing on arrival — a second parser, in a game whose whole point is that there is one |

**And "which hull is this order for" got no new answer either.** `domain/order`'s draft already owns it
app-wide. The map READS it, and selecting a fleet on the chart or in the list WRITES it — so the harbour
you tap next sails the ship you just pointed at, and COMMAND opens on her. A `useState` here would have
been a fourth screen with a private answer to one question, which is how *"where does her next order
happen"* reached four spellings (`domain/fleet/derive.ts:76`).

### THE MAP DOES NOT JUDGE, AND CANNOT RECOMMEND WHAT `cmd.issue` WOULD REFUSE

`voyage.sail_refusal` is THE answer to "may she sail there?" and it is revoked from every client role
(`0019:461`), so the only honest way to ask it from a browser is to run the verb and throw it away —
`cmd.preview()`. The `args` the map previews and the `args` it hands over are **the same object**, walked
through the same `orderText` COMMAND will walk, so the line the server judged and the line it is later
asked to run are equal by construction rather than by agreement.

Measured in the running game at 390×844, local PGlite chain, a freshly founded house:

| tapped | what the panel said |
|---|---|
| **Cádiz** | `Sail Gaivota here` · **248 nm · 2.1 days** — the SAILED distance round Cape St Vincent, not the 188 nm straight line |
| **Las Palmas** | `Sail Gaivota here` · 808 nm · 6.8 days |
| **Alexandria** | `Sail Gaivota here`, and under it `E_ENDURANCE` — *"Gaivota carries 15.0 days of stores and that route is 19.9 voyage-days; you need 22.9 — PROVISION first"* |
| **Cádiz, with her at sea and bound there** | *"She is at sea — this would wait in her queue."* |
| **Lisbon, with her alongside** | *"Gaivota lies here."* and no button |

**The refused button is not disabled**, which is the rule the haggle block already keeps (`README` §10.1):
tapping it hands over anyway, and COMMAND renders the refusal's *fixes* as tappable orders. Driven: the
Alexandria tap landed on COMMAND carrying `SAIL Gaivota TO ALE` with `PROVISION Gaivota FULL` offered
beside it and *Issue this order* correctly dead. **The map states the reason; COMMAND offers the remedy.**

### THE LOOP, COMPLETED

Tap Cádiz → `Sail Gaivota here` → COMMAND opens on `SAIL Gaivota TO CAD` → *Issue this order* → `sent:
SAIL Gaivota TO CAD` → Gaivota `SAILING`, *at sea → Cadiz, 0 nm of 248 nm, arrives in 6m* → back on the
chart, her dotted track out of Lisbon with Cádiz ringed. No pageerror, no console.error,
`scrollWidth === clientWidth === 390`. Repeated at 1440×900.

### A DEFECT THE DRIVE CAUGHT, WHICH NO TYPE COULD

The first draft asked `fleetPortCode(fleet)` whether she was already at the tapped port. That function
answers a **different question** — *"where does her next ORDER happen"*, `fleet.port ?? fleet.voyage.to` —
so with Gaivota three minutes out of Lisbon on a Cádiz passage, tapping Cádiz printed **"Gaivota lies
here."** She was 248 nm away. It is now `fleet.port === portCode`, one served field, and the comment above
it says why the other one is wrong. One field, two questions, and the wrong one was true-looking enough
to ship.

### TWO DUPLICATIONS FOLDED, BECAUSE THIS SLICE WOULD OTHERWISE HAVE BEEN THE THIRD COPY

`docs/NO_SPAGHETTI.md` §2 listed `num`/`str` — *"read a field out of a jsonb payload safely"* — as open
debt in two places that **had already drifted**: LEDGER's `num` tolerated a numeric arriving as a string
and COMMAND's did not. The map needed to read `cmd.preview`'s estimate, which is §1's *"found a third time
→ stop the feature and fold it, the same turn."* So:

* **`src/lib/json.ts`** — `num` and `str`, the STRONGER version of each (§6: never weaken to green).
  PreviewPanel's and LedgerScreen's copies deleted; neither screen's behaviour changes.
* **`src/domain/order/estimate.ts`** — `sailEstimate()`, the one READING of `total_nm` / `voyage_days`.
  COMMAND draws the full readout, MAP prints the passage in a corner panel; the chrome differs, the keys
  have one owner. **Only SAIL** — the other verbs' estimates have one reader each, and folding something
  that is not duplicated is inventing a home rather than finding one.

### SMALLER, AND DELIBERATE

* **`fit` → `find`.** One tap, always on the glass, frames what the house HAS. The behaviour is unchanged;
  `fit` is a chart programmer's word for the thing a player calls *"where is my ship"*, and the owner's
  standing map rule is no insider jargon.
* **The FLEETS chip stays folded on a phone, and that is the right call.** Measured when the rule was
  written: open at 390×844 it filled y 0–505 of 844 — 60% of the chart, from a component whose whole brief
  is "corner panel". Folded it is a 44px chip in the corner, one tap opens it, and the fold is remembered
  per player. Desktop is unchanged (open). It is also not the only way to find her — `find` is one tap and
  never folds.
* **The port panel is wider than the fleet panel on a phone** (`74vw` against the compact default's `55vw`).
  A refusal is a SENTENCE, and a 214px column turns a readable reason into a tower that pushes the button
  up the glass. The chart clips at its own edge, so panel height is what must stay bounded, and width is
  what buys it back.
* **The action is in the CORNER PANEL, never on the marker.** A chart pans; an action drawn at a map
  coordinate can be panned off the screen. That is the reach law arrived at by a different route, and it
  is now written into `components/ui/overlayLayout.ts`, whose header used to ban command buttons on
  overlays outright.
* **`keepOut={surface.chromeBoxes}`** wired through to `ChartCanvas` — the chart side's fix for names
  printed under this screen's opaque chrome (`Saint-Malo` as `Sain`, `Nantes` as a bare `s`). The port
  card the new flow opens is a `MapPanel` and carries the `CHART_CHROME` marker already, so it is covered
  by the same one line.

### WHAT THE SERVER WOULD HAVE TO SERVE NEXT

Two things the map wants and cannot honestly have. Both are named here rather than computed on the client:

1. **"Every port she can reach right now, and the reason for each one she cannot."** One preview per tap
   answers one harbour; painting the whole sheet reachable/not would be 214 round trips, or a client copy
   of `voyage.sail_refusal`. The shape wanted is one read — `world.reachable(fleet)` → `[{port_id, nm,
   voyage_days, refusal_code, refusal_sentence}]` — over the same `voyage.reach_from` + `voyage.sail_refusal`
   pair `world.trade_routes` already composes (0019). **That is a migration, and it is not this slice's.**
2. **"Read this harbour's market" from the map.** The READ exists (`world.market`); the *seam* does not.
   Which port a screen is LOOKING at is component-local in MARKET and `sessionStorage` in PORT, and
   `MarketScreen.tsx:113-122` already names the fix as promoting that into a section of its own. Building
   it means touching two screens this slice may not, so the map offers no "read the market here" button —
   an honest absence beats a button that lands on Lisbon.

---

## 2026-08-23 — D18: seventy marks, a row that unfolds, and a fair that happens whether or not you look

Owner: *"make icon for each trade good, do all the things that i asked before, and then do 8, 9, 10"* —
and, when asked what 내 주방 meant: **the galley, as its own tab beside the cargo.**

Six background agents across three waves, partitioned by disjoint file domains. Four migrations
(0025–0028), three new screens' worth of client, and one architectural carve-out that had been
correctly refused the day before.

### SEVENTY GOODS, SEVENTY MARKS

The picker drew seven category glyphs across seventy rows, which is an icon column carrying no
information: the reader still had to read every name. Now every good in `data/goods.json` has its
own drawn mark.

**The hard part was never drawing seventy pictures — it was drawing seventy that are still tellable
apart at the 22px the picker renders them at.** Nine were redrawn after the first contact sheet:
ginseng read as a standing human figure, furs was indistinguishable from musk, horses was a smudge
as a head profile (a horseshoe now), whale oil collided with tea, raw silk with cinnamon, ivory with
tobacco.

**And the honest limit is written down rather than smoothed over.** Nothing shares a mark, but six
pairs still need the name beside them: ivory/tea, nutmeg/cacao, silk cloth/muslin, musk/furs,
cinnamon/raw silk, and the three bowls (rice, gums, whale oil). The icon is an accelerator, never a
replacement for the name — which is why the unfolding row keeps both.

The old override table was **partly dead**: `pitch` was not a good id (the good is `tar`), and four
"overrides" pointed at their own category glyph. Both classes gone.

### THE ROW THAT UNFOLDS — asked for twice before it was built

Tapping a good opens it in place. The pick happens only on the fold's own `Choose <good>` button.

    ◔ Porcelain              BUY ⌄        HOW MUCH SHE CAN TAKE
      luxury                              20 t at most
      BUY 358 · SELL 328 · NEARBY 82%     stopped by       your purse
      STOCK ████████████████              all of it costs  7,179 d.

**Cost measured, not reasoned**: opening a row is exactly 2 RPCs; opening a second is 2 (the first
closes, nothing leaks); closing is 0; `trade_routes` is 0 per row, fetched once per (port, fleet).
Opening does not commit — proven in the browser: the argument still says *not chosen yet*.

`neighbours` was truncating to `NEIGHBOUR…` in a 96px cell. A label clipped by its own cell is a
label that has stopped working; it reads `NEARBY` now. Not `%NBR` — that is the column name in
migration 0009, and the player never reads the schema.

### THE BOARD, AND WHAT A ROW MAY CARRY

**The blocking question was not how to rank — it was what a board row may say.** A name, a nation, a
standing, and the fames the standing is computed from. Nothing else.

DESIGN J.1 makes the order book the only PvP surface, so another house's purse and the harbour her
fleet lies in are not colour — they say what she can afford to corner and where to be waiting.
Enforced by the server refusing to hand it over: `public.standings` carries RLS with **no policy and
no grant to any client role**. The break-test: adding a purse to a row →
*"another house's purse of 131,457 d. was reachable through the board."*

Ties are `rank()`, not `row_number()` (which invents an order out of heap order) and not
`dense_rank()` (which hides how many are level). Two houses level are **both 1st and the third is
3rd**, `=2` on every tied row so the missing number does not read as a bug.

The board is a RECORD keyed like `price_history`, and **the read is the catch-up** — no cron
dependency, because PGlite has no pg_cron.

### THE FAIR, AND WHERE A TIMED MODIFIER MAY HONESTLY LAND

Decided by elimination, and the rejection is the load-bearing part:

* **Speed — rejected.** `voyage.depart` FREEZES speed into `voyages.speed_profile` (0006:62). A
  weather buff wired to speed would be summed into a stored total the moment a fleet sailed, and
  that freeze is what makes offline settlement byte-identical (proof 01).
* **The daily cap — rejected here on purpose**, because ACCOUNTING lands there in 0027 and two new
  terms in one function on one day is how a composition goes unproven.
* **The port's cut — taken.** `world.spread_effective` (0022) is untouched: it calls `world.spread`
  as its first line, so purser, bargain, floor and cap keep composing exactly as proven.

The calendar is **data, not code** — magnitude, duration, season length and chance all live on the
authored kind row. A `festival_*` knob would have been a second authority.

### THE THREE THAT DID NOTHING

* **SURGEON** — and the agent's own assert caught its own first draft. Shaving the surgeon off the
  loss *fraction* rounds away entirely on a starter Barca: `floor(8 × 0.721) = floor(8 × 0.70) = 5`.
  It works on **hands**. Proved on a real raid, then replayed on the identical roll with a surgeon
  aboard: 8 → 6 where nobody had left 5, and *"We buried 3 of the hands"* became *"We buried 2; the
  surgeon kept the rest."*
* **ACCOUNTING** — multiplies the allowance, never the tally already spent.
* **NAVIGATION — the trap, and it did not get deferred a fourth time.** 0016 deferred it to weather;
  0026 closed that escape hatch by establishing a timed modifier cannot reach frozen speed. So it
  composes THROUGH `voyage.fleet_speed` rather than beside it. Not double-counting, by four
  measurements — and breaking `(1+nav)*(1+skill)` to the sum form made the migration go red.

### A FAIR HAPPENS BECAUSE THE GAME IS PLAYED

`world.buffs()` was the only thing drawing a fair anywhere in the world, and PORT was its only
caller. **A world rule that depends on a screen being looked at is not a world rule.**

`world.snapshot()` was the obvious home and was **the wrong one, measured**: the client calls it
once per session and caches it hard, so winding there moves the bug from "a tab was opened" to "the
app was launched". It is also `STABLE`, so Postgres refuses a write inside it. The winder went into
`world.fleets()` — the 30-second read, already 0009's catch-up read.

    world.fleets()   1.455 ms → 1.695 ms   (+0.240 ms, +16.5%)

Three runs agreed within 0.04 ms. One writer still: 1 function writes `active_buffs`, 3 read it,
`tick_buff_calendar` has exactly 2 callers and the migration names them.

**The break-testing found a real weakness and the guard was fixed, not the test.** The first
idempotence assert compared row COUNTS — and a writer that clears its season and re-draws it leaves
the same number of fairs. It digests the row **ids** now, and that term is what fired.

### TWO CLOCKS, ONE WORD

`duration_game_days` rides the calendar clock (2,880 s/day); the wire carried only
`time_compression` (the voyage clock, 180 s/day). A client printing "lasts 3 days" would have been
**wrong by ×16** — which is why the agent that built the PORT panel printed none of them and wrote
down why instead of guessing.

They are genuinely two clocks and were not collapsed: at one rate either a passage costs an hour per
sea-day or a game year passes in an afternoon. **The defect is the wire, not the model.** The seam is
asserted end to end, with the ×16 as the negative control computed from the two served knobs.

### THE CHART, AND THE BOUNDARY THAT WAS PRODUCING COPIES

A small map on SAIL needed 9 of the 14 files in `features/map/`, and no screen may import another.
The previous agent **refused to copy and refused to weaken the guard**, and wrote the problem up
instead. That was right: `sections.spec.ts` was green the whole time `PortPicker` existed twice.

`src/chart/` is now a layer between domain and features, with one entrance. Three new guards,
each broken on purpose and watched fail:

> *"A layer nobody can reach through the entrance is a layer the next screen copies a file out of,
> which is the silent copy no import check can see."*

**No line is drawn between the two ports** — deliberately, and written into the code. A straight line
would be read as the distance, and straight-line distance is the defect that once showed Seville at
169 nm against the server's 286 *and sorted the list by it*. Distances stay on the row, from the
server: Setúbal 16, Porto 195, Cádiz 248, Seville 286.

### THE GALLEY

내 주방 — the fleet card is three faces now: **SHIPS · CARGO · GALLEY**. Water, food, range, hands,
hold and the daily burn were one run-on mono paragraph that wrapped to four lines at 390px; they are
six labelled rows. The heading came off (the tab already says GALLEY), and the disclosure it carried
moved DOWN onto the `hold` row — the row it is actually about. A dot floating alone above a grid,
attached to nothing, is not better than a heading.

### FOUR THINGS FOUND AND SAID RATHER THAN PATCHED

1. **`RankScreen` printed `PRT`** on the one screen whose job is telling houses apart. The agent
   REFUSED to write a client-side code→name table and reported it — which is why there is one
   authority (`nationNameOf`, beside `portNameOf`) instead of a seventh copy. 0028 serves
   `snapshot.nations`; a `nation_name` on the row was rejected because `snapshot.ports[].nation`
   would still be unresolvable and the wire would carry three spellings.
2. **`db.chain.spec.ts:268` was already RED on a correct chain** — pinned to 0024's literal title
   while `LAST` had moved. A guard red on a correct chain gates nothing.
3. **`rpc.surface.spec.ts` was missing `worldBuffs` and `worldStandings`.** 0022 shipped a complete
   server mechanic with no client at all for exactly this reason.
4. **`layout.spec.ts`'s TABS list never included `rank`** — the only tab with a scrolling table the
   390px guard did not measure. Added; 7 pass. `map` and `profile` stay out, and the reason is
   written in rather than left to be rediscovered.

### Gate

`db:check-versions` 28, positive control fired · `db:apply` **28/28 receipts** · `db:proof` **45/45**
markers across 6 files, run four times · `playwright` **162 passed** · tsc, eslint, build clean.

`BALANCE_MEDIAN_IN_BAND` was green on all four proof runs (13.6 / 13.2 / 11.6 / 14.2). It went red
once mid-session and was **measured rather than re-rolled**: six runs on the new chain gave
13.1/12.5/13.8/13.5/12.2/10.3 against six on the unchanged chain at 15.1/9.0/12.4/14.4/12.4/12.1.
The unchanged chain has the WIDER spread. Pre-existing non-determinism in proof 05, already
documented in 0021's header — a flake on the safety net, and worth its own slice.

**Still open:** proof 04 now winds the calendar (0026's "the proofs run in a fair-free world" is half
false, and 0028's header says so). A fair only makes a trade cheaper, so it can only help
`FIRST_SESSION_HOME_RICHER` — and the fixture was deliberately NOT reached into, because a migration
editing a fixture to protect a number nothing pins is the wrong repair.

---

## 2026-08-23 — D17: a fleet of eight, an order said in one breath, and a bargain worth striking

Owner: *"MAKE An order - Command. too much unncessary info. So is Sail, Sell, Hire etc. Too long
explanation. this is a game, make it so. Check all aspect of the game. When buy, i want all the
trade goods on left side, and my fleet info on the right side, showing how much room, how much
negotiation can be done, and so on. This game fleet will be comprised with 8 ships."*

Then, when told this game had no haggling and that adding one was a design decision rather than a
UI change: *"yes add haggling mechanic."*

Four migrations (0021–0024), a new game mechanic on both sides of the wire, a two-pane BUY, and a
verbosity sweep over every screen.

### THE VERBS: 1,212 CHARACTERS → 309

    SAIL   Put to sea and make for another port.        (153 → 37)
    BUY    Take cargo aboard at the price on the quay.  (227 → 43)
    SELL   Sell out of the hold at the price offered.   (242 → 42)

The fine print did not go: 0021 adds a served `note` field and **proves the mechanics MOVED rather
than being retyped** — six phrases must be present in the old `help` and in the new `note`. The
card prints `help`; the ⓘ prints `note`. Nothing is authored client-side, because `cmd.verb_schema()`
is the one authority for the grammar and a client gloss would be a second one.

COMMAND also deleted a paragraph that printed the selected verb's own sentence **a second time, in
full, 200px below the card**. That was the loudest instance of the owner's complaint.

### EIGHT SHIPS, AND THREE CAPS THAT WERE FICTION

The design had always said a fleet is 1–8 hulls (`fleet_ship_max = 8`, §C.4) and B.3's formation
penalty had a band for **7+ that no fleet could ever reach**. What blocked it was `ship_max = 4`.

Raising it turned up the real defect: **all three caps were read by nothing.**
`fleet_ship_max` had never been read by any function, trigger, constraint or client since 0001 —
a sentence in a `description` column. `ship_max` and `fleet_max` were *served and printed as hard
limits* (RANK's gauge, FLEETS' "1/4 ships") while no server rule held them.

One authority now — `public.assert_house_caps()` — **on the table as a trigger, not inside a verb**,
so a future shipyard verb inherits the cap instead of re-deriving it. The caps were proven to bite
SEPARATELY: a 9th hull refused from one fleet while the same hull was accepted into a second.

    1 hull   4.9125 kn · free hold  55.8 t · crew  8
    8 hulls  4.6669 kn · free hold 446.4 t · crew 64      ← the 0.95 band, exercised at last

### THE BUY SCREEN IS TWO PANES

Goods left, the fleet's own state right, sticky while the list scrolls, at `md` and up. The
breakpoint was measured, not chosen: at `sm` the left pane is ~290px and the buy/sell/%NBR columns
wrap — the exact crushed-column signature `layout.spec` fails a build over.

**The rail is written FIRST in the DOM with `md:order-last`**, because at 390px the working pane is
**11,718px tall** and a rail placed after it would sit eleven thousand pixels below the list it
belongs beside.

The goods list is uncapped now — it was showing 12 of 68 and printing "56 more, narrow the filter".
The owner asked for *all* the goods.

### HAGGLING — AND THE HONEST FORM OF IT

0016 seeded a HAGGLING skill with effect `SPREAD` and the note *"not yet read by any rule."* This
made it real, and the mechanic lands exactly there.

**The lever is the spread, never the mid.** The mid is the world's price — identical for every house
on the quay. The spread is the port's cut, and that is what a factor can be talked out of. The
inline `spread × (1 − purser)` of 0017 became a named authority, `world.spread_effective()`, so the
rule about what a house executes at has ONE place to change.

* **Save-scumming is structurally impossible** — the attempt row is written and counted BEFORE the
  roll, and the attempt index is part of the RNG key. A retry is a different draw that has already
  cost a chance.
* **No new randomness** — it reuses `voyage.rng`, the IMMUTABLE primitive that keeps the world
  secret server-side. A second RNG in a chain whose offline-equivalence proof rests on there being
  one would have been a real defect.
* **A failure hardens the ODDS, not the price** — hardening the price would make `world.market()`
  print an ask the trade does not charge, since market() is served without knowing who has haggled.
* **Purser and bargain compose multiplicatively**, not additively: 25% + 30% is 47.5% off, not 55%.

### AND IT SHIPPED AS A ROUNDING ERROR, AND WAS SENT BACK

Driven in a browser, the finished mechanic saved **19 ducats on 40 tuns — 0.36%.** Three finite,
hardening attempts for a third of a percent. That is not a mechanic, and it would have read as
broken rather than subtle.

0024 retuned it: step 0.15 → 0.25, cap 0.30 → 0.75, floor 0.55 → 0.20. A full bargain is now
**2.88% of stake — 22% of a 13% voyage.**

**The brief asked for "a fifth to a third of a voyage's margin" and a third is arithmetically
impossible**, and the agent said so rather than fudging: a round trip pays one whole spread, spreads
average 3.84%, so even a bargain of 100% — the quay keeping *nothing* — is 3.84% of stake, 30% of a
voyage. Reaching a third means widening the spread itself, which taxes every unhaggled trader. Not
done; recorded with the measured projection.

`BALANCE_MEDIAN_IN_BAND` measures the UNHAGGLED median and still reads 12.9%. A bargained trader now
sits at 15–17%, at or just over the top of the band — **stated, not absorbed.**

### THE REGRESSION I PUT ON THE LIVE SERVER

0018's grant sweep — which I pushed to production yesterday — revoked `public.current_player_id()`
from `authenticated`. **Every RLS policy in the chain calls it**, so a direct client SELECT raised
42501. It was invisible only because every read goes through a `world.*` definer function.

It was worse than first reported: **11 tables, not 6.** And the agent swept all five ways a function
can be caller-evaluated — policy, CHECK, DEFAULT, GENERATED, index expression — rather than taking my
list. Triggers are deliberately excluded: EXECUTE on a trigger body is checked at `CREATE TRIGGER`,
not at fire time, so including them would report four defects that are not defects.

`public.caller_evaluated_functions()` is the third member of the family beside `client_write_grants()`
and `client_executable_writers()`. It **refuses to grant anything VOLATILE**, so 0018's property
cannot be re-opened by accident.

**Proof 03's hole is closed.** It tested INSERT denial and never a SELECT, which is exactly why a
broken read wall was invisible to it. It now runs with a THIRD house present, so isolation is proven
by ownership rather than by arithmetic — after the agent caught its own first assert ("A + B = the
whole table") being true on an empty database and **false on production, which carries a real
house**.

### TWO THINGS MY OWN GUARD CAUGHT

`tests/duplication.spec.ts`, written two days ago, failed this work twice:

1. **83% recipe similarity** between the haggle block's head row and the Ledger's entry head — two
   screens that never met, typing the same idea. Now `headRowClass()`.
2. **0022 re-cut five functions without the word "supersede" in its header.** It genuinely does
   supersede `world.quote`, `do_buy`, `do_sell`, `world.skills` and `client_rpc_entry_points`, and
   they move in one file for 0017's reason: a bargain `world.quote` honours but `do_buy` never
   spends is the same defect as checking room with one function and placing cargo with another's
   copy.

### UNITS

`9.4 d` was voyage-days and `8,000 d.` was ducats — **one letter, two units, a full stop apart, side
by side on FLEETS and PORT.** Days spell the word now. `t` and `kn` stay short; nothing collides
with them.

### Gate

`db:apply` 24/24 receipts · `db:proof` **45/45** markers across 6 files · `playwright` **159 passed**
· tsc, eslint, build clean.

**One honest caveat:** the first full run had two failures — `rpc.firstSession` and the chain-rebuild
spec — and the second run was clean. Both are the flake class 0024 documented and fixed for proof 04:
`tick_market_drift` uses `random()` by design, so every apply builds a different market and a spec
that needs one specific profitable round trip to EXIST can miss. Proof 04 now draws from the OU
process's stationary distribution keyed on authored codes. **`tests/rpc.firstSession.spec.ts` has the
same root cause and has not been given the same fixture.** It is a lottery, it is known, and it is
written here rather than left to surprise someone.

---

## 2026-08-22 — D16: the audit, and the day the game could not tell you where to sell

Owner: *"after all things are made, run audit on the all parts of the game. Make it playable. But
most of all, sort out your code so that it is well tidy and organized. No spaghetti."*

Seven background agents across two waves, partitioned by disjoint file domains, none permitted to
run git or the suite so that one working tree could not be fought over.

### THE VERDICT: playable, and the machine is good

An agent drove the real game at 390×844 and completed the loop twice through the UI alone — read a
market, composed a buy without typing, sailed, queued a sell while at sea, watched it run on
arrival. 8,000 → 8,131 d. Zero crashes, zero console errors across eight tabs, no sideways scroll,
and `Aborted()` **could not be reproduced in 13 cold loads**.

### AND THE THING THAT WAS ACTUALLY WRONG

**The metric the entire UI was built on is mathematically incapable of pointing at a profit.**

`%NBR` compares a price against ports within 600 nm — which is almost exactly *the set of ports
reachable in one leg*, so neighbours share a price BY CONSTRUCTION. Measured: over 2,100
(port, good) pairs, **145 read "buy", 13 read "sell", 1,872 "hold"**. A player at Lisbon saw seventy
rows and no SELL anywhere. The auditor followed the screen's own printed rule and the quay's own
recommendation and **lost 199 d. in 16 minutes**.

Worse, where the band did fire it could be wrong about money: salt reads 109.6 at Porto — a SELL by
the screen's rule — and carrying it there from Lisbon **loses 77 d.** A ratio of mids contains
neither port's tax, neither spread, nor the order's own price impact. Widening the radius cannot fix
that.

**0019 mints `world.trade_routes()`**: for each good a port sells, the reachable port that pays most
for it — priced end to end through the same `world.quote()` a committed trade executes at, over the
SAILED leg distance, and only to ports the fleet may actually reach. MARKET now names voyages:

    Black Pepper → Saint-Louis  +1,640
    60 t · pay 7,747 d. here, receive 9,387 d. there · 1,534 nm, 13.01 days · 21.2% on the outlay

%NBR is **kept and unchanged** — it honestly answers "is this cheap locally?" — and simply taken off
the advice job. Its band headings read `CHEAP HERE` rather than `BUY`, and a card says plainly:
*"%NBR says cheap HERE — not profitable."*

**Three folds were required before ranking was even possible**, each because the answer would
otherwise have had two authors: `voyage.reach_from` (one shortest path — a second Dijkstra could
have quoted 195 nm for a voyage that sails 248), `voyage.sail_refusal` (one answer to "may she sail
there?", found the expensive way when the first draft recommended a voyage `cmd.issue` then refused
with `E_ENDURANCE`), and `world.market` computing %NBR once instead of four times.

**The agent caught its own ranking bug by reading its output**: ranked by profit-per-sea-mile it put
*"wax to Setúbal, 16 nm, +49 d."* above *"+1,847 d."* — the original defect in a new column.

**And it is proven cheap without being wrong.** Proof 05 gained a marker: at ALE an EXHAUSTIVE scan
of 483 (good, destination) pairs found 1,034 d. at best, and the shortlist found the same 1,034 d.
`world.market` also got FASTER — 800 ms → 245 ms.

### THE P0, and it was real

**55 SECURITY DEFINER functions were executable by `anon`**, 17 of them writers, all bypassing RLS.
Proved by exploiting it: as `anon`, `public.fleet_unload()` ANSWERED.

The root cause was not the REVOKE — it was **`IN SCHEMA`**. Measured on a fresh PG 18.3: the
per-schema form of `alter default privileges` records rows that LOOK right while the function is
still anon-executable, so a catalogue assert passes vacuously. Only the schema-less form works.
0018's governing assert is therefore BEHAVIOURAL — create a probe writer after the fix and require
the privilege check to say no. Its first draft used the catalogue check, and **its own assert caught
its own draft**.

    anon-executable 55 → 0 · authenticated 65 → 18 (exactly catalog.ts) · pg_default_acl 0 → 1

### THREE WAYS THE GAME WAS LYING, all measured and all fixed

* **`affordableUnits()` never read the purse** — two of four offered buys refused instantly on a
  fresh save. The FOURTH copy of a bug the log says was killed twice. **Deleted, not patched.**
* **PORT teleported to Acapulco** when the fleet was at sea, and lost a chosen port on every tab
  change. Underneath, "where does her next order happen" had FOUR spellings and the fourth was the
  bug. One function now.
* **The SAIL picker showed straight-line distance** — Seville 169 nm against the server's 286 — and
  that wrong number sorted the list, so "nearest first" was not.
* **OFFICERS and ACADEMY rendered off the right edge** with no scroll affordance: `scrollWidth 401`
  against `clientWidth 332`. The newest features were the ones a player could not find. The strip
  wraps now — 293/293, six of six on screen — and the agent **overruled a comment I had written**
  claiming wrapping would jump the panel height. It was right: the ON and OFF arms differ only in
  colour.

### NO SPAGHETTI — the law, and the teeth

`docs/NO_SPAGHETTI.md` is the law. `tests/duplication.spec.ts` is what makes it bite: six shapes
that fail CI, **each proved able to go red** by mirroring the tree and injecting the defect.
Thresholds measured, not guessed — the closest honest pair sits at 0.71 against a 0.75 cut.

Twelve duplications ripped out, deleted rather than adapted. The headline: **"how much fits in this
hull" had seven implementations** — four server, three client — and MarketScreen's had forgotten
water and food since the day it was written, on the screen where you decide what to buy. Also:
`fold()` was private to COMMAND, so MARKET silently stopped finding `São Vicente`; `.replace('_',
' ')` written three times, each replacing only the FIRST underscore; `portByCode[code]?.name ?? code`
written **seven** times with one already drifted; and **67 lines of Quay JSX pasted verbatim inside a
JSX comment** by my own PORT refactor, invisible to the compiler.

`useWorld()` with no selector is now banned — it re-rendered every bare subscriber twice per read,
and reading is how time passes here.

### THE FINDING WORTH KEEPING

> **A boundary that forbids borrowing converts sharing into a silent COPY that no import check can
> see.**

`sections.spec.ts` was green the entire time `PortPicker` existed twice. "No screen imports another
screen" is satisfied perfectly by a copy. The boundary was producing the duplication it existed to
prevent — which is why the import guard alone was never going to be enough, and why the duplication
guard had to be written.

### Two defects of mine, both found by agents

The sticky first column painted `bg-surface` while D12 made panels `bg-panel`. And **0014's
self-assert was a lottery** — `limit 1` with no ORDER BY — measured at 3 failures in 7 runs. Same
class as D11h's drift assert, which this project had already recorded, and I reproduced it anyway.

### Gate

`db:apply` 20/20 receipts · `db:proof` 33/33 markers · `playwright` **157 passed** · tsc, eslint and
build clean. Verified stable over five consecutive applies and six consecutive proofs, because
prices drift with the wall clock and one green run proves nothing about a flake.

### Still open

The local world is still demolished on every chain change — rows are rescued to localStorage and
**never put back**, so every migration still resets every player. The real answer is the server, and
the Supabase CLI on this machine is not authenticated. Nothing has been pushed to the live project.

---

## 2026-08-22 — D13: four migrations, and two of them change a rule

Owner: *"do the migrations - price history, player row, officers, skills"* — the four server gaps
D12 named as the real ceiling.

### The problem every one of them hit: 0007 is DEPLOYED

Fame wants to be a counter each verb increments. A skill wants to be XP each verb awards. Officers
want a hook in the trade and the voyage. **All three mean editing migrations that have already run**,
which this chain does not do. So each migration had to find the shape that fits the constraint —
and in two cases the constrained shape is better than the obvious one.

* **Fame is DERIVED** (0014), not counted: `public.player_fame()` reads the append-only ledger every
  time it is asked. It cannot drift from the record, and it is retroactively correct for every
  voyage sailed before the migration existed. A stored total would have been a second authority for
  something `events` already knows.
* **A skill is a CHOICE, so it is STUDIED** (0016), not earned: derived XP would level itself, and
  then it is not a decision, it is a second fame. `cmd.study_skill()` costs money and requires a
  port with an academy — and **`ports.has_academy` has existed since 0002 with nothing reading it.**
  A flag nothing reads is scenery; it has a consequence now.
* **Two files SUPERSEDE one function each** — `voyage.fleet_speed()` (0015) and
  `voyage.endurance_days()` (0016). That is the sanctioned way to change a rule here (README §1:
  "a change goes in a NEW file that supersedes the old one") and it is not re-cutting 0006, which
  still proves its own claims when the chain replays in order.

**The supersedes are no-ops when the new thing is absent, and that is asserted rather than assumed.**
An unofficered fleet reads 0006's exact 4.9125 kn; an unstudied captain reads 0006's exact endurance.
That is what keeps `04_first_session` — which sails an unofficered, unskilled Barca — honest.

### An officer or a skill that changes nothing is decoration

Both migrations could have shipped tables and a hiring RPC with the effect left for "later". Each
wires exactly ONE thing instead, and **says out loud which of the rest are inert**:

    NAVIGATOR    -> voyage.fleet_speed()      READ
    QUARTERMASTER / SURGEON / PURSER          seeded, NOT READ YET
    SEAMANSHIP   -> voyage.endurance_days()   READ
    NAVIGATION / ACCOUNTING / HAGGLING        seeded, NOT READ YET

`world.officers()` and `world.skills()` carry a `takes_effect` flag per row, the self-asserts check
it both ways, and the UI prints *"No rule reads this yet — this bonus changes nothing today."* The
same posture 0010 and 0012 take about an absent pg_cron: report it, never pretend.

NAVIGATION is deliberately the inert one on the skill side: **0015's navigators already own speed**,
and two authorities for one number is the thing this project forbids.

### 0013, and the sentence that had to be deleted

`public.price_history` is keyed `(port, good, slot)`, so a retried tick is a no-op by construction
rather than by a check somebody has to remember. It samples 14,980 rows per slot and prunes past a
288-slot window; both directions are proven, and the prune is proven by **ageing a row on purpose**,
because on a table this young a prune that removes nothing looks identical to one that works.

The slot formula got a name. 0010 computes `floor(epoch / drift_slot_seconds)` inline and cannot be
re-cut, so `public.drift_slot_of()` is minted as the named authority and the self-assert **proves it
returns the slot `tick_market_drift()` itself reports** rather than assuming the two agree.

MarketScreen printed, on screen: *"No seven-day line is drawn … nothing in the chain keeps one yet."*
That sentence is now false, so it is gone, and a TREND sparkline stands where it was. Three docs that
listed `history7` as not-served were corrected too.

### What the client got, so this is not half a slice

Seven RPCs (`worldPriceHistory`, `worldPlayer`, `worldOfficers`, `worldSkills`, `cmdHireOfficer`,
`cmdPostOfficer`, `cmdStudySkill`), their types, and the store. Then:

* **MARKET** draws the line. `Sparkline` refuses to interpolate (a gap in the record is a gap in the
  line), refuses to scale to zero (a 2% move would look like a halving), and draws nothing under two
  points.
* **PORT** gains two faces — **Officers** and **Academy** — because §3a's second trap is "the action
  lives on the wrong screen". An officer signs on at a quay; a trade is learned at an academy. The
  Academy face is only offered where `has_academy`, since a face that always refuses wastes a tap.
* **RANK** stops counting. It used to derive voyages and turnover from one 50-row ledger page and
  had to admit the window; fame is the server's now, over the whole record. What is left derived is
  a fact about the PAGE, and it says so.
* **PROFILE** shows the house — company, nation, level, founded, where she lies.

### Proved

`db:apply` **16/16 receipts**, `db:proof` **31/31 markers**, `playwright` **149 passed** against a
served build. tsc + eslint clean. Every new migration is LF (checked, not assumed — the CRLF trap).

**Three test pins moved deliberately:** the chain's LAST migration, its human sentence, and the RPC
catalogue's allow-list, which exists precisely so that adding an RPC is an edit somebody made on
purpose.

### Two things found on the way

1. `ledger.event_id` does not exist — the column is **`ref_event_id`**. Caught by the first apply,
   which is the whole argument for PGlite: it cost thirty seconds instead of a CI round trip.
2. A fleet cannot be set to "at sea" by nulling its port alone: `fleets_position_is_unambiguous`
   (0004) ties status and port together. The constraint doing its job — a fleet cannot be nowhere.

### Still not done

**No standings table**, and that half is a DESIGN decision rather than a missing SELECT: a table of
captains needs a rule about who may see whose figures. **Buffs** have no table. Three officer
specialties and three skills are inert by design and say so. And the price line stays empty in local
play, because nothing schedules a tick under PGlite — on the live server, where D11e proved pg_cron
runs, the record fills every ten minutes.

---

## 2026-08-20 — D12c: the rest of the screens

Owner: *"keep going, do the rest of the screens."* (D12b, logged only in its commit until now, made
a verb an action card carrying the server's own `spec.help`, and added §3a to the direction doc.)

### PORT is one place with faces now

It was four sibling Cards down a page. At 390px the fourth began roughly 1,200px down and, in
practice, was never read. It is one panel with a tab strip — **Quay · City · Services · Alongside**,
the reference's 기본/교역/시설/투자 — with the same content and the same order lines.

**The Quay opens first, deliberately.** §3a's second trap is *"the action lives on the wrong
screen"*, and the most-praised patch in that game's four-year convenience backlog added no feature
at all: it moved selling provisions onto the buy screen, where the need arises. What you can DO here
opens first; what the city IS is one tap away.

Composing it introduced two duplications immediately — `DRAFT 5` and the `HARBOUR` eyebrow each
printed twice, once in the PageHeader and once in the new panel head. Both deleted from the panel.
Same rule that took the purse off two screens in D12, broken again within ten minutes of writing it
down.

### Three primitives the design system was missing

**`TabRow`** — a real `role="tablist"`, and it **scrolls sideways rather than wrapping**: a wrapped
second row of tabs changes the panel's height when the selection changes, which makes everything
below it jump.

**`Gauge`** — a resource drawn as **countable segments**, not a smooth bar. EVE draws its capacitor
in fragments for the reason that matters on a phone: you can *count* blocks and reason "four left,
that is 40 tuns", where a bar forces arithmetic against a denominator that is not on screen. This
game already had the idea in one place — the Market's six-cell text `stockBar` — and this is that
idea as a primitive. The partial segment is **shaded, not rounded up**: a hold with a sliver free
must not read as a hold with a whole block free.

FLEETS uses it for the two facts that decide the next order, **hold and worst hull**, which were
buried one tap and a scroll down in the detail panel. Whether to buy is "how much room is left";
whether to sail is "how sound is the worst hull". The figure stays beside the blocks, because a
gauge you cannot read exactly is a mood ring and this is a ledger.

**`Input`** — the audit found four hand-written recipes differing in border, focus ring, padding and
whether they cleared 44px. Auth and the register are migrated.

### RANK and PROFILE stopped being placeholders

RANK was 18 lines naming three things that would exist one day. The honest position is narrower and
more useful: **the client can say what you are worth; it cannot say what that is worth relative to
anyone**, because no other house's figures cross the wire and nothing in the chain computes a table.

It now shows the real figures a standing would be computed FROM — purse, fleets, ships, and from the
ledger: voyages completed, ports reached, trades struck, taken in, paid out — and states the missing
half as a fact, naming the four things a standing needs first.

**The derived counts say what window they looked at.** `world.events` is ONE page of the ledger (the
store fetches the default 50), so "voyages completed" is not a lifetime total and must not be printed
as one. Purse, fleets and ships are exact, because those are served whole.

PROFILE keeps the session half, which was always real, and replaces the bullet list of promises with
**the world half** — which backend answered, the world's size, the time compression. A player asking
*"am I on the live server"* or *"why did my purse reset"* had nowhere to look. What is still absent
is named as server work rather than drawn as empty fields.

### Everywhere else

* **LEDGER**: the delta is `text-xl`. It was the same size as the "balance" caption beside it, which
  gave the number a player scans a ledger FOR the same weight as the one they merely check. Its
  filter chips are the `chip` primitive now.
* **MAP**: the corner panels take the panel material and keep their blur — they sit ON the world and
  must let the coastline stay legible. **The blur stops there**: CCP measured window blur at up to
  32 ms a frame and drop it entirely at low shader quality, so two small panels over a static SVG is
  a budget that survives and a screenful of panels is not. The chart's water is `bv-sea` now — the
  map is not a different place, it is the same world seen from further up.
* **AUTH**: the first thing anyone sees was a flat `bg-app` field, the colour of an unstyled page.
  It is the lit sea, so signing in and playing are visibly the same place.

### Proved

**149 passed** against a served production build, twice — once before the map and input changes and
once after. All 12 layout tests, the K.1 fold test, and the four-viewport map label specs. tsc and
eslint clean. Every tab screenshotted at 390×844 and checked for sideways scroll: **all eight clean.**

### Still not done

COMMAND's argument pickers are still the old chrome inside the new action cards, and the Market's
port picker still truncates 214 ports to 40 with an on-screen admission that it cannot show the
world. The server gaps are unchanged and are the real ceiling: **no price history, no player row, no
officers, no skills, no fame.** Each is a migration, and until they land there are screens here that
are correct and still look empty.

---

## 2026-08-20 — D12: it was a document, so it was made of something

Owner: *"this is not a proper game. see other games such as 대항해시대 오리진 — find korean images,
gameplay videos, images. Refer to them and make the UI the same, or even better. Refer to
Runescape 3, EVE online as well. They have good UI. USE the best tools for each tasks, and make a
proper game."*

### The reference was LOOKED AT, not remembered

Marketing art teaches nothing about UI, so the App Store shots were a dead end — they are 60%
character illustration. The usable captures are on Line Games' own Korean guide site, which
documents the game with real in-game screenshots (`static.pcs.line.games/gameguide/guideContent/`).
Twenty-six were downloaded and read. They live **outside the repo**: they are Line Games'
copyright, and what this project keeps is what was learned, never their art.

The single most useful frame is 세계지도 — the world map with the port-info panel docked at the
right. It gives the whole layout grammar in one picture, and the row inside it is the lesson:

    (icon) 포탄     101%   574
    (icon) 돌소금   105%   516
    (icon) 인쇄물    99%   306

**Four facts, one line, no prose** — and the price index is a coloured pill riding directly behind
the name, not a column you swipe to reach. D11h moved `%NBR` to second position by reasoning about
it. The reference proves the position by shipping it, and proves the *shape* we had not got to.

`docs/UI_DIRECTION.md` is the write-up: the diagnosis, the layout grammar, a pattern table, the
material read off the captures, what RuneScape 3 and EVE Online add on top, and **eight rules** the
client now builds to. It states plainly that it overrides `docs/DESIGN.md`'s UI austerity on the
owner's instruction — and that it changes nothing about the architecture.

### The doctrine that had to be retired, in its own words

`src/index.css` opened with: *"TEXT-FIRST: this game is words, numbers and tables … the type
carries the design and **the chrome stays quiet**."* That sentence is why the app looked like a
web form, and it was load-bearing — it was the reason nothing was made of anything. It is replaced
in place, with the owner's instruction quoted beside it, rather than quietly deleted.

**The palette survived unchanged.** It was never the problem. Cold ink-blue layers, warm parchment
text, brass accent — all still exactly what they were. What was missing was *material*.

### What material means, concretely

Fourteen new tokens, **every one derived via `color-mix` off the existing palette**, so retuning
`--color-accent` retunes the material with it. A literal would have been a second palette.

    panel / panel-2 / panel-head    the ink layers pushed warm, toward oiled wood
    hairline                        the 1px gold rule under every panel header
    brass / brass-2 / brass-rim     the primary action's fill, rim and lit top edge
    sea / sea-lit / sky / sea-deep  the world behind the glass
    cheap / dear / even             one meaning per colour, rule 7

and four compositions no single utility expresses: `.bv-panel-head`, `.bv-cut` (a 7px chamfer —
metal, where a 12px radius reads as a web card), `.bv-brass`, and `.bv-sea`, a **pure-CSS lit
horizon**. That last one is deliberate: this repo has no art at all, and a gradient in the
stylesheet costs zero bytes and can never 404.

### One panel, not two

The tempting move was a new `GamePanel` beside `Card`. That is two authorities for "what a panel
is", which is the thing this project keeps having to rip out. Instead **`Card` became the game
panel**: same name, same callers, new material, plus a `head`/`foot` slot — because the reference's
header bar is FULL-BLEED and a caller cannot make one from inside the padding without negative
margins. Cards that pass neither are exactly what they were and simply inherit the new skin.

### The frame

`TopBar` is the persistent chrome the app never had: wordmark, a live-read dot, and the purse. It
carries **one** figure, because the purse is the only number this server actually keeps — the
reference shows four currencies and inventing three more would be decorating the UI with facts the
game does not have. It carries **no back chevron**, because eight tabs is a flat model and a
chevron with nowhere to go is worse than none.

Wiring it found a real duplication: COMMAND and LEDGER were each printing the purse in their own
header. **Three copies of one figure**, and the two that scroll away were the wrong ones to keep.
Both deleted.

The shell root is now `.bv-sea` and does not scroll; each screen scrolls its panels over it, so the
horizon stays put the way it would from a deck.

### The chip, which the design system was missing

The audit found **twelve hand-written copies** of one pair of recipes across Command, Market and
Fleets — drifting in border colour and hover between copies. `buttonClasses` now has `chip` and
`chip-on`. Two variants rather than a boolean, because it is a pure string function and every
caller already knows which state it is drawing.

### MARKET, measured

`PriceIndex` is the %NBR pill and the one treatment of the figure the game is played from. It is
deliberately **not** a `Badge`: Badge is the status-WORD pill at 10px, and rule 2 says the number is
the hero. **The tone comes from the server's own `advice`** — never from comparing `pct` against a
threshold on this side of the wire.

Two measurements drove the rest, taken in a real browser at 390×844:

* the panel header's first cut put the tap-affordance line inside the bar, which grew it to ~100px
  and **cost two price rows above the fold**. On a screen whose whole job is rows, the chrome does
  not get to eat them. One line in the bar; the affordance moved to the body.
* the row printed the category under the name, making every row 62px — **four rows above the fold**.
  The category is a fact about the good, not about its price today, so it moved to the row's title.
  **Four became five**, and the row is still the 44px the reach law requires.

`TradedRow`'s `block` prop is gone with it: it existed only to tint the %NBR figure, and the pill
now carries that meaning from `advice`. Two renderings of one fact; this was the copy to delete.

### Proved

**149 passed, 0 failed** against a served production build — including all 12 layout tests and
`MARKET puts a complete price row above the fold, per K.1`. The fold measured directly in the
browser afterwards: `{foldY: 731, rows: 70, above: 5, firstText: "Black Pepper 83% 131 120 ██████
glut"}`. tsc + eslint clean.

### What this did NOT do, and is next

The frame and the material are in; **six screens still wear them without being re-composed**. PORT
is still four sibling cards where the reference is one place with faces; COMMAND's verbs are still
text buttons rather than the reference's hero action cards; FLEETS has no status orbs; RANK is
still an 18-line placeholder. And the honest blockers stand, all of them server-side rather than
visual: **no price history** (so no sparkline can be drawn honestly), **no player row** (so PROFILE
and RANK cannot be driven at all), no officers, no skills, no fame. Each is a migration, not a
component — and they are why the UI still looks empty in the places where it is behaving correctly.

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

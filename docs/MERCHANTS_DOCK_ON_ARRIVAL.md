# MERCHANTS_DOCK_ON_ARRIVAL — a merchant docks the instant she arrives, the way a player does

**Status: PLAN, 2026-10-15. Nothing in this file is built. No migration, no code, no DB change.
Prod head is 0121 (`docs/RESUME.md:18`). This plan is ONE build step, M1, to be cut AFTER the
economy's 0122–0123 (`docs/ECONOMY_LOOP.md:727-728`) because 0123 restates `world.npc_fleet_card`
(`docs/ECONOMY_LOOP.md:728`) and M1 must slice the LIVE body of that read.**

The owner, 2026-10-15: *"the merchant npc should also be like me."*

Every `NNNN:line` below is `supabase/migrations/20260818000NNNN_*.sql`; client paths are under
`src/`. Where a function has been re-cut by later slices, the line cited is the last full definition
or the slice that put the words there.

---

## 0. The answer in ten lines

1. **A player's fleet docks on the first read after her eta** because every read and every command
   settles her first: `world.fleets()` loops `voyage.settle` over the house's fleets before it
   answers (0009:161-165), `world.standing_routes()` does the same for every route fleet
   (0092:800-804), and `cmd.issue` settles *"BEFORE judging the order"* (0008:485-487).
2. **A merchant docks only when the minute sweep reaches her.** `public.tick_arrivals()` (0010:54-87,
   cron `* * * * *` at 0012:97) is the only caller of `voyage.settle` for a merchant; no merchant
   read settles anything — `world.sea_roster`, `world.port_merchants`, `world.npc_fleet_card` and
   `world.fleet_trades` are all declared `stable` (0118:38, 0113:70-71, 0099:241, 0121:214) and
   PostgreSQL refuses a write inside a `stable` function. So an arrived merchant sits "SAILING" at
   her destination for up to 60 s plus the sweep's own run (avg 14.3 s, max 46.8 s,
   `docs/RESUME.md:29`) — at 960× (0100:55-60) that is 16 to 28 voyage-hours of lying off the quay.
3. **The fix composes, it does not fork.** ONE new server-only function, `voyage.settle_due`, locks
   the due merchants exactly as the sweep does (`for update skip locked`, 0010:65-72, 0092:779) and
   calls `voyage.settle` — the one catch-up (0007:34, 0027:237). It decides nothing: arrival is
   judged inside `voyage.settle` (0027:410), the lap close, the rest and the next lap inside
   `cmd.advance → cmd.run_standing_route` (0027:425, 0092:641-646, 0101:94-107, 0114:674-680).
4. **The four merchant reads call it first, on exactly the merchants they report**, then answer as
   before: the roster (all merchants, bounded), the harbour's list (the merchants whose routes call
   there), the card and the trade history (that one fleet). Each read goes `stable → volatile`, the
   shape `world.fleets()` has had since 0009 (0009:149-154, no `stable`; likewise 0092:788-793).
5. **Bounded so a map read can never settle hundreds**: a count knob, a wake sub-cap and a
   wall-clock budget checked before each settle, with a 500 ms `lock_timeout` inside each
   per-fleet subtransaction (the `npc_tend` pattern, 0114:386-510; 0097:41). Worst case per read is
   about 3 s against the 8 s `authenticated` statement timeout (0117:10-14).
6. **The post-arrival work needs no new split.** The executor already splits it by the rest: an
   arrival at home is dock + lap close + a 120 s hold (cheap: 0092:641-646, 0101:101-107; the lap
   close's trades build is 3.95 ms, `docs/DEV_LOG.md:8993`); the dear lap-start plan (mean 461 ms,
   max 1,230 ms, `docs/DEV_LOG.md:8959-8960`) runs only when the rest ends (0114:674-676 after
   0101:101-107 has returned). An intermediate stop is dock + lines + trades + depart in one call,
   ~61 ms measured (0105:107: 17,868 ms for 295 at once).
7. **The sweep is not tightened in M1.** It stays the fallback for merchants nobody is looking at.
   Aligning departures to the sweep would be a second ETA author (0100:41); a cron job per arrival
   would be a second scheduler (0012:92-99, 0078:193-201). A 30-second cadence is possible only if
   prod's pg_cron accepts `'30 seconds'` and only after M1's measurement (§6).
8. **The client changes nothing.** The map already places a merchant as a pure function of time
   and puts her ON the destination roadstead at her eta (`live/seaRoster.ts:35-37, 50-51, 66-67`)
   — but as a SAILING mark, because the one where-rule is voyage-first (`domain/fleet/where.ts:69-78`)
   and the chart may never arrive her itself (`chart/drift.ts:26-28`). The docked hull at her berth
   (`chart/liveWorld.ts:169, 176-182`) appears when the server has docked her and the next roster
   delta carries it (≤ 30 s, `live/worldStore.ts:370`; the harbour list and the card re-ask every
   7.5 s, `app/AppShell.tsx:44-53`, `live/useServedRead.ts:104-128`).
9. **One knob rolls it back instantly** (`merchant_settle_on_read` false → every read is its
   pre-image to the byte, asserted), and a forward migration restores `stable` and drops the
   wrapper. No table, no cron, no data.
10. **Why the 2026-10-08 decision "the map read does not settle" (N13) is revisited and what of it
    stands**: §7.

---

## 1. The concepts, before the first line (NO_SPAGHETTI §7B)

| | |
|---|---|
| **Concept** | *The merchant catch-up on read*: the read that reports a merchant settles her first, as a player's reads settle his. |
| **Where it lives, and why** | `voyage.settle_due(...)`, server-only, in the `voyage` schema beside `voyage.settle` — the catch-up is a decision about the world, so it is a migration, never client maths (`docs/NO_SPAGHETTI.md:107, 112-116`). It is a CALLER of `voyage.settle`, `cmd.advance` and the route executor; it re-derives nothing: the arrival test is `voyage.settle`'s own (0027:410), the hold and the lap boundary are `cmd.run_standing_route`'s (0092:604, 0092:641-646, 0101:101-107). |
| **Second caller** | Four on day one (the roster, the harbour's list, the card, the trade history). A fifth is plausible: `tick_arrivals` itself could loop the same function for merchants — named, not done in M1 (§6). |
| **The wrong shape, and how it would be found** | (a) a client rule "eta passed ⇒ docked": a second mover, forbidden by `chart/drift.ts:26-28` and the one where-rule `domain/fleet/where.ts:24-30`; (b) a copy of `voyage.settle`'s arrival branch inside a read: `tests/duplication.spec.ts:356-399` demands a supersede header for any re-created function, and the self-assert below counts the callers of `voyage.settle(` in `pg_proc`; (c) a second sweep: 0012:92-99 forbids a second schedule authority. |

---

## 2. What happens today, exactly

### 2.1 The player's path (the model)

`world.fleets()` — *"the read is the catch-up. Nine hours offline resolve here, in order, before a
single number is reported"* — `for r in select id from public.fleets where player_id = v_player loop
perform voyage.settle(r.id); end loop;` (0009:161-165). `world.standing_routes()` does the same per
route fleet (0092:800-804). `cmd.issue`: *"Bring the fleet up to date BEFORE judging the order"*,
`perform voyage.settle(p_fleet);` (0008:485-488). All three are volatile (no `stable` marker:
0009:149-154, 0092:788-793; 0008's `cmd.issue` writes by definition).

### 2.2 The merchant's path (the gap)

- `voyage.settle(p_fleet, p_now)` (0027:237-429): locks the fleet `for update` (0027:272), the
  SAILING voyage `for update` (0027:275); with no voyage it runs `cmd.advance` (0027:276-279);
  resolves the due sea-days (0027:281-407); then **arrival**: `if p_now >= v.eta` (0027:410) →
  voyage `ARRIVED` (0027:411), fleet `DOCKED` (or `UNABLE_TO_SAIL`) with `port_id = v.dest_port_id,
  version + 1` (0027:412-416), the `VOYAGE_REPORT` event (0027:417-424), then
  `perform cmd.advance(p_fleet, p_now)` (0027:425). Later slices only scale the wage
  (0114:622-630); the 0122 plan slices the arrival branch's `emit_event` lines
  (`docs/ECONOMY_LOOP.md:286`) — M1 does not touch this body.
- `cmd.advance` (0007:812-865) runs her queue; at queue-dry, 0092's HUNK A refills it once through
  `cmd.run_standing_route` (0092:1238-1245, `cmd.run_standing_route` at 0092:1243).
- `cmd.run_standing_route` (0092:575-721, sliced since): route `for update` (0092:602); the hold
  (0092:604); `DOCKED` only (0092:606); **LAP BOUNDARY at stop 0**: `cmd.standing_route_close_lap`
  (0092:641-646) — which writes `lap_id = null, updated_at = now()` (0092:555), `stock_out`
  (0116:86-103) and `trades` (0121:188-197); then the pacing block as 0101 cut it: a merchant's
  rest floor `max(closed_at) + route_rest_voyage_days × 86400 / time_compression` (0101:94-100),
  `hold_until` written and `return 0` (0101:101-107); merchants' pace is the knob, 0
  (0117:151-159, 0117:39-43), the rest is 120 real s (0116:45-50). When the hold has passed:
  the lap-start re-plan `v_plan := public.npc_plan(p_now, sr.id)` under `v_npc and sr.lap_id is
  null and sr.stop_cursor % v_n = 0 and sr.updated_at < now() - interval '1 minute'` (0114:674-680),
  the re-read of the chosen loop (0120:687-710), the lap row (0092:678-684), the lines
  (0092:686, with ≤ 3 sink quotes per stop: 0114:718-728), the enqueue (0092:700-709), and
  `stop_cursor = …, updated_at = now()` (0092:712); an error pauses the route `error` (0092:714-719).
  Back in `cmd.advance` the orders run — SELL, BUY, PROVISION, REPAIR, then SAIL → `voyage.depart`.
- **Who calls `voyage.settle` for a merchant: the sweep alone.** `public.tick_arrivals` loops the
  due voyages `for update skip locked` (0010:65-72) and settles each (0010:73); 0092 added the
  wake loop for a held route — `for update of f skip locked`, `hold_until = null`, `cmd.advance`
  (0092:772-783). The job is `byeharu-voyage:arrivals` on `* * * * *` (0012:97), one transaction
  for every arrival on earth (0092:608-609; `docs/NPC_TRADERS.md:1351-1352`), measured avg 14.3 s,
  max 46.8 s (`docs/RESUME.md:29`) against the cron's 2-minute statement timeout (0114:14-15).
- **The merchant reads settle nothing**, by declaration: `world.sea_roster` is `stable`
  (0118:35-41), `world.port_merchants` is `language sql stable` (0113:68-74), `world.npc_fleet_card`
  is `stable` (0099:238-244), `world.fleet_trades` is `stable` (0121:211-217). `world.sea_traffic`
  too (0102:130-136), and it is the retired read: the shipped client never calls it
  (`lib/rpc/catalog.ts:309-319` registers roster, card, trades and port merchants only;
  0118:28-29 says its retirement is a later file).

### 2.3 What the owner sees today, in his own words

At 960× a real minute is 16 voyage-hours (0100:55-60: 1 voyage-day = 90 real s). Between her eta
and the sweep's commit (0–60 s, plus the sweep's own 14–47 s), a merchant:

- on the **map** sits on her destination's roadstead (she is placed at `frac = 1`,
  `live/seaRoster.ts:35`) but drawn as a *sailing* hull, not a berthed one (`domain/fleet/where.ts:70-78`
  classifies any row with a voyage as `sailing`; the berth fan is for `docked` rows only,
  `chart/liveWorld.ts:169, 176-182`); her line reads `to Lisbon · 0s` (`domain/fleet/where.ts:104-107`,
  `lib/format/time.ts:84-85` clamps a passed instant to `0s`);
- in the **city's Port tab** is listed *Ending* or *Passing* (`merchant_doing_at` 0104:188-189) with no
  rest countdown, and the list's own rule for a passed instant is to print *ends soon* and wait
  for the server (`live/merchantWords.ts:40-46`);
- on her **card** shows `status: SAILING` and the old lap (0099:276-289, 0099:313-319);
- in the **trade history** shows the stop's trades only once the sweep has docked and traded her
  (0121:260-265 reads the open lap's orders).

Then the sweep docks her, closes the lap or trades, and the next roster delta (≤ 30 s,
`live/worldStore.ts:368-370`) moves her to the berth.

---

## 3. The design

### 3.1 One wrapper, server-only: `voyage.settle_due`

```sql
-- M1: THE MERCHANT CATCH-UP ON READ. Locks as the sweep locks, settles through the one catch-up,
-- decides nothing. Server-only (revoked from public, anon, authenticated; never an entry point).
create or replace function voyage.settle_due(
  p_fleets    uuid[]      default null,   -- the merchants this read reports; null = every merchant
  p_now       timestamptz default now(),
  p_limit     int         default null,   -- null = wc_int('merchant_settle_per_read')
  p_wake_max  int         default null,   -- null = wc_int('merchant_wake_per_read')
  p_budget_ms int         default null)   -- null = wc_int('merchant_settle_budget_ms')
returns jsonb   -- {settled, woken, busy, failed, over_budget, ms}
```

Body, in order:

1. `if not public.merchant_settle_on_read() or not public.npc_traders_on() then return {…0}` — dark
   or off, nothing (the switch 0097:104-109; proof 12's MERCHANT_DARK stays true:
   `scripts/db/proofs/12_merchant_companies.sql:357`).
2. **Arrivals first, oldest eta first** — the sweep's own order (0010:71):
   `select v.id, v.fleet_id from public.voyages v join public.fleets f on f.id = v.fleet_id
   join public.players p on p.id = f.player_id and p.is_npc where v.status = 'SAILING'
   and v.eta <= p_now and (p_fleets is null or f.id = any(p_fleets)) order by v.eta limit v_limit`.
   `players.is_npc` is the one predicate (0097:10-14). The `eta <= p_now` is a candidate filter, not
   a verdict: `voyage.settle` re-judges it at 0027:410 and a candidate it disagrees with is simply
   not arrived. The sea-day clause of the sweep's predicate (0010:69-70, `day_ends_at … <= p_now`)
   is deliberately NOT here: at 960× a sea-day boundary falls every 90 s for every fleet at sea,
   so a read that chased boundaries would always find hundreds due — N13's objection
   (`docs/NPC_TRADERS.md:835-837`). Days still settle inside `voyage.settle` on the way to an arrival
   (0027:281-407), and the sweep keeps the boundaries for everyone else.
3. Per arrival, in its own subtransaction (`begin … exception`, the 0114:386-510 shape): stop when
   `clock_timestamp() > v_t0 + budget` (counted `over_budget`); `perform set_config('lock_timeout',
   wc_int('merchant_settle_lock_ms') || 'ms', true)`; `perform 1 from public.voyages where id = r.id
   for update skip locked` — not found → `busy` (the sweep or another read holds her, 0010:65-66);
   else `perform voyage.settle(r.fleet_id, p_now)` → `settled`; `lock_not_available` → `busy`;
   `others` → `failed` with `sqlerrm` in the receipt (the merchant is rolled back to where she was;
   the player's read goes on).
4. **Wakes, soonest hold first, capped by `p_wake_max`**: `select f.id from public.fleets f join
   public.players p on p.id = f.player_id and p.is_npc join public.standing_routes sr on
   sr.fleet_id = f.id where public.standing_routes_on() and sr.paused_reason is null and
   sr.hold_until is not null and sr.hold_until <= p_now and f.status = 'DOCKED' and (p_fleets is
   null or f.id = any(p_fleets)) order by sr.hold_until limit v_wake` — the wake loop's own
   predicate (0092:774-778). Per wake: budget check; `perform 1 from public.fleets where id = r.id
   for update skip locked` (0092:779); then `perform voyage.settle(r.id, p_now)` — with no voyage it
   is `cmd.advance` (0027:276-279), which refills through `cmd.run_standing_route` where the hold
   test (0092:604) now passes, the pacing recompute finds the rest over (0101:94-107), the lap-start
   plan runs (0114:674-680), the lap opens and nulls `hold_until` (0092:678-684), the orders run and
   she sails. The sweep's `hold_until = null` (0092:780) is hygiene, not a decision, and is not
   copied: the lap start writes it. Counted `woken`.
5. Return the receipt with `ms` (measured with `clock_timestamp()`).

**Lock order and why it cannot deadlock.** The sweep locks the VOYAGE row (0010:67-72) and then,
inside `voyage.settle`, the FLEET row (0027:272) and, inside the executor, the ROUTE row (0092:602).
The wrapper takes the same order for an arrival (voyage, skip locked → fleet → route) and the wake
loop's order for a wake (fleet, skip locked → route). The one lock order the chain states — fleet,
then route (0093:179-184) — is kept. `npc_tend` and `npc_plan` lock fleet-then-route `nowait`
(0114:387-388, 0120:549-550) and count a held row as busy (0114:505-506, 0120:657-658), so they skip
ours. `cmd.issue` never reaches a merchant: it refuses a fleet that is not the caller's
(0008:470-474), and proof 12 asserts every door refuses a merchant fleet
(`scripts/db/proofs/12_merchant_companies.sql:33`). The one AB-BA that exists today — the sweep holding a player's voyage while
`cmd.issue` holds that player's fleet — is untouched and unchanged by M1 (merchant rows only). The
client's own read order (fleets → routes → traffic, `live/worldStore.ts:689-701`) still holds: the
roster read now takes locks, but only on merchant rows, which no player read ever locks (0009:163
and 0092:801-802 settle `player_id = v_player` fleets only).

### 3.2 The four reads, and what each settles

| Read | Today | M1 | `p_fleets` (exactly what it reports) | Bound |
|---|---|---|---|---|
| `world.sea_roster(p_since)` (map; 0118:35-92) | `stable` (0118:38); delta = routes `updated_at >= p_since` or a voyage `departed_at >= p_since` (0118:86-89) | `volatile`; `perform voyage.settle_due(null, now())` BEFORE the delta select, inside the lit branch (after 0118:47-49) | `null`: the roster's subject is every merchant (full) and whoever moved (delta). A settled arrival moves: at home the lap close and the hold bump `updated_at` (0092:555, 0101:102-105); at a stop the refill bumps it and a new voyage departs (0092:712, `departed_at`). So the same answer carries her | count + wake cap + budget |
| `world.port_merchants(p_port)` (city Port tab; 0113:68-74, body 0104:199-278 carried verbatim 0113:33-38) | `language sql stable` (0113:70-71) | restated whole as `language plpgsql volatile`: `v_ids := array(select nf.fleet_id from public.npc_fleets nf join public.standing_route_stops st on st.route_id = nf.route_id where st.port_id = p_port)` — `npc_fleets.route_id` is the authority 0104 names (0104:265-270), the same `exists` the row builder uses (0104:275-276); `perform voyage.settle_due(v_ids, now())`; then `return (select … 0113's body verbatim …)` | the harbour's merchants: the ones ending here, passing here, and resting here with the rest over | count + wake cap + budget |
| `world.npc_fleet_card(p_fleet)` (card / ship panel; 0099:238-266) | `stable` (0099:241) | `volatile`; after the E_NOT_FOUND gate (0099:260-262): `perform voyage.settle_due(array[f.id], now())` | that one merchant | 1 |
| `world.fleet_trades(p_fleet)` (trade history; 0121:211-233) | `stable` (0121:214) | `volatile`; after the gate (0121:230-233): `if v_npc then perform voyage.settle_due(array[f.id], now()); end if;` | that one MERCHANT. A player's own fleet is deliberately NOT settled here: the beat's `world.fleets()` already settles it (0009:161-165), and two settling reads in flight over one player's fleets is the deadlock `live/worldStore.ts:689-697` guards against | 1 |

Not touched, and said: `world.sea_traffic` (retired for the shipped client, 0118:28-29; its
retirement is the later file that drops it); `world.route_board` (0106:218-262 serves a merchant's
lane and a derived state word, no position — the sweep is enough and its row set is every route);
`public.tick_arrivals` (unchanged; §6); `voyage.settle`, `cmd.advance`, `cmd.run_standing_route`
(unchanged — M1 adds callers, not authors).

**Volatility is required, not optional.** PostgreSQL refuses a data-modifying statement inside a
`stable` function, and PostgREST runs a `stable` RPC in a read-only transaction; the client POSTs
every RPC (`lib/rpc/cloudBackend.ts:26`, supabase-js `.rpc()` default), so `volatile` reads are
called exactly as `world.fleets()` is today. The local backend already runs `tick_arrivals` before
the roster and the harbour reads (`lib/rpc/localBackend.ts:38-41`, the pg_cron stand-in) — kept; the
two are idempotent together.

**The wire does not change.** No key is added to any row or envelope (the key sets are asserted
contracts: 0104:211-214, 0113:33-38, 0118:152-164). The receipt stays inside the server; the
self-assert and the DEV_LOG carry the numbers.

### 3.3 Can the post-arrival work run inside a read? Yes — because the executor already splits it

| Arrival | What `voyage.settle → cmd.advance → run_standing_route` does in the read | Cost (measured) | What the player sees in that read's answer |
|---|---|---|---|
| **Home stop (stop 0), lap open** | dock (0027:411-416); report event (0027:417-424); queue dry → refill → lap close (0092:641-646: sums over the lap's orders 0092:535-548, `stock_out` 0116:86-103, `trades` 0121:195, bounded prunes 0092:565-570, 0121:204-207) → rest floor → `hold_until = closed_at + 120 s`, `return 0` (0101:94-107). **No plan, no trades, no SAIL** here | dock ≈ ms; `lap_trades` 3.95 ms (`docs/DEV_LOG.md:8993`); whole close well under the 61 ms per-arrival average of 0105:107 | `Lisbon`, the docked hull at her berth; the Port tab says **Resting** with the countdown (`merchant_doing_at` 0104:186; `live/merchantWords.ts:43-46`); the card's `last lap` pill is the lap that just closed; the trade history shows it with its stops |
| **Intermediate stop** | dock; refill writes this stop's orders (≤ `npc_lines_per_stop` BUYs, each with one sink quote 0114:718-728; SELLs; SAIL), `stop_cursor`/`updated_at` (0092:712); `cmd.advance` runs them: SELL, BUY, PROVISION, REPAIR, then SAIL → `voyage.depart` | ≈ 61 ms per arrival with trades (0105:107, before 0114's ≤ 3 quotes; say ≤ 100 ms) | she touches the quay and is already away: the roster delta carries a NEW voyage (`departed_at`), the trade history shows the stop's trades, the Port tab says **Passing** then **Away** |
| **Rest over (a wake)** | `cmd.advance` → refill: hold passed (0092:604), rest over (0101:94-107), **the lap-start plan** (0114:674-680; 0120's choice), lap row, lines, orders, SAIL | plan mean 461 ms, max 1,230 ms (`docs/DEV_LOG.md:8959-8960`; the save door is 0.3–0.7 s of it, `:8962`) + lines/trades/depart ≈ 0.1 s | **Starting** → she sails; the card prints the chosen loop |
| **Refused SAIL / executor error** | the order fails and halts her (0007:838-841, 0007:861-862) or the route is paused `error` (0092:714-719) | ms | **Laid up** (0104:181) or stopped, exactly as the sweep would have left her; `npc_tend` clears or re-plans her within the hour (0115:163-170) |

So the only dear piece is the wake, and it is sub-capped (`merchant_wake_per_read`, default 2) and
budgeted. No new split is needed and none is introduced; splitting dock from trade would be a
second executor order and a second place a stop is "done".

### 3.4 Cost per read, and the ceilings

Per settle: arrival ≈ 0.06–0.1 s; home arrival ≈ 0.01 s; wake ≈ 0.5–1.3 s. Defaults: 12 arrivals,
2 wakes, 1,500 ms budget checked BEFORE each settle, so the worst overrun is one wake (≈ 1.3 s):
worst case ≈ 2.8 s + the read itself (roster full ≈ 0.5 s, 0118:22-24; a delta, the harbour, the
card and the history are tens of ms, `docs/DEV_LOG.md:8994`) ≈ 3.3 s, against the 8 s
`authenticated` statement timeout (0117:10-14, `docs/DEV_LOG.md:137-138`). Expected case: the world
has tens of arrivals and wakes a minute (the sweep's 14.3 s a minute at 0.06–1.2 s each,
`docs/RESUME.md:29`), a handful of live players (the count is not recorded in the repo; read it off
`auth.users` before setting the knobs), the map asks every 30 s and an open city or card every
7.5 s — so most arrivals are settled within seconds
by whoever is looking, each read settling a few, and the sweep finds what is left. Total work is
unchanged; it moves earlier and spreads. A lock a read cannot get within 500 ms (the drift tick's
`port_goods` update, 0010:109-115; the hourly upkeep's 2 s `lock_timeout`, 0114:572-573) is `busy`,
never a wait the player feels.

If a read ever did exceed 8 s, the whole statement fails 57014 and the settles roll back — the
0117 failure (0117:10-14). That is why the budget is small, the lock timeout is short, and both
are knobs.

---

## 4. The client: what is already true, and what is not

**Position is a pure function of time — confirmed.** `live/seaRoster.ts:22-24` turns a roster row
into the drawn row at `nowMs`; `voyageAt` (`:26-71`) takes `frac = min(1, max(0, (nowMs − dep) /
(eta − dep)))` (`:35`), `done = frac × Σ legs` (`:36-37`), finds the leg (`:38-47`) and places her
`a + (b − a) × legFrac` on it (`:50-51, :66-67`). At `nowMs ≥ eta` she is at the last vertex of the
served course, which is the voyage's frozen path end (0118:67 serves `voyage.course_of(v.path)`;
0047:315-323 builds it from `path[0].a` and every `b`), i.e. the destination's served roadstead
(0076's "a harbour is reached from its roads"; the same point the chart draws a docked merchant
at, 0102:261-262, `chart/liveWorld.ts:169, 182`).

**But she is drawn as SAILING until the server docks her.** The one where-rule is voyage-first:
`whereabouts()` returns `sailing` for any row with a voyage (`domain/fleet/where.ts:69-78`) and
`docked` only when the voyage is null and `port` is set (`:79`). The chart fans the berth only for a
`docked` row (`chart/liveWorld.ts:169, 176-182`, `chart/FleetsLayer.tsx:412`). The drift rule says
in as many words that the client *"cannot round a corner, skip a leg, or arrive"*
(`chart/drift.ts:26-28`), and the harbour list says a passed rest instant is *"the server flips her
on its next tick … counting up would be the client inventing a state"* (`live/merchantWords.ts:40-41`).
So the client is RIGHT not to dock her, and M1 changes no client line. After M1 the server docks
her on the first read after her eta; the roster delta carries the docked row within
`ROSTER_ASK_EVERY_MS` = 30 s (`live/worldStore.ts:368-370`, `:703`), and the Port tab and the card
show it on their next beat, 7.5 s (`app/AppShell.tsx:44-53` at 960×: 90 s ÷ 12; re-asked by
`live/useServedRead.ts:104-128`; `live/useMerchantsHere.ts:32-34`; `live/useMerchantCard.ts:4-10`).

Optional, the owner's call, client-only, not in M1: `ROSTER_ASK_EVERY_MS` 30 s → 15 s halves the
map's lag at the cost of one delta read more per half-minute per viewer (a delta is milliseconds,
0118:24).

**A known gap, pre-existing, named:** a dock that moves neither her route nor a voyage — a merchant
whose route is paused or detached — is invisible to the delta (0118:86-89 reads `standing_routes.
updated_at` and `voyages.departed_at`; `fleets` carries no timestamp, 0004:66-81) until the
10-minute full read (`live/worldStore.ts:374-376`). Today the sweep's docks have the same hole.
The honest fix is one trigger-written `fleets.moved_at` read by the delta — one authority, a
follow-up M2, not M1.

---

## 5. M1 — `a_merchant_docks_the_moment_she_arrives` (the one build step)

**Version:** the chain's head + 1 when it is cut, arbitrated by `npm run db:check-versions`
(`supabase/migrations/CHAIN.md:3-4`), after 0122 and 0123 (`docs/ECONOMY_LOOP.md:727-728`) and
beside the ships plan's S1 (`docs/RESUME.md:36` names 0124 for it; whichever lands second takes
the next number). Header per `supabase/migrations/README.md:52-86`: the owner's words, what says
the opposite (the four `stable` declarations, N13), what it does and does not, the measured
numbers, and the word **supersede** for the four reads (`tests/duplication.spec.ts:356-399`).

**Supersedes** (by slices of the LIVE bodies, each hunk asserted to occur exactly once —
the 0114:606-619 helper, LF-normalised 0114:611): `world.sea_roster` (0118), `world.npc_fleet_card`
(0099 as sliced by 0123), `world.fleet_trades` (0121); and restates `world.port_merchants` (0113)
whole, body carried verbatim, with its pre-image kept under `pg_temp` for the parity assert
(0113:51-65). **Does not touch:** `voyage.settle`, `cmd.advance`, `cmd.run_standing_route`,
`public.tick_arrivals`, the cron, `world.sea_traffic`, `world.route_board`, any table, any client file.

**Contents, in order:**

1. Knobs (`world_config`, `on conflict do nothing`, each described):

   | key | default | what it is |
   |---|---|---|
   | `merchant_settle_on_read` | `true` | THE switch. False: every merchant read is its pre-image to the byte; the sweep alone docks merchants (today's world). One reader, `public.merchant_settle_on_read()` |
   | `merchant_settle_per_read` | `12` | arrivals a read may settle (eta ascending) |
   | `merchant_wake_per_read` | `2` | of those, rested merchants it may put back to sea (the dear ones: a lap-start plan each) |
   | `merchant_settle_budget_ms` | `1500` | wall-clock budget, checked before each settle; the overrun is at most one settle |
   | `merchant_settle_lock_ms` | `500` | `lock_timeout` inside each per-fleet subtransaction; a held lock is `busy`, never a wait |

   Shipped **lit**, because the owner asked for the behaviour and the parity-when-off assert is in
   the same file; the knob is the rollback.
2. `public.merchant_settle_on_read()` (the one reader of the switch, the `npc_traders_on` shape
   0097:104-109) and `voyage.settle_due(...)` (§3.1), both `revoke all … from public, anon,
   authenticated`; neither is registered in `public.client_rpc_entry_points` (0118:102-114 is the
   registry's shape; nothing is added).
3. The pre-images of the four reads cloned under `pg_temp` (0117:45-55's shape), then the slices:
   `stable` → `volatile` and the one `perform voyage.settle_due(…)` line in each, placed after each
   read's dark/E_NOT_FOUND gate; `world.port_merchants` restated whole (§3.2).
4. Grants re-asserted exactly as found (each read `authenticated` only: 0118:98-99, 0104:287-288,
   0099:353-355, 0121:322-323), `public.client_write_grants()` and
   `public.client_executable_writers()` both empty (CHAIN.md:21-26).

**Self-assert** (one `do $$` block, `'M1 self-assert FAIL: …'` / `'… self-assert ok: …'`,
`tests/duplication.spec.ts:339-343`; holds AS FOUND, lit or dark; every probe rolled back):

- (a) **Posture.** `pg_proc.provolatile = 'v'` for the four reads; `voyage.settle_due` exists,
  `has_function_privilege('authenticated', …)` false for it and for the switch reader; the
  registry row set is the pre-image's; 0 client write grants, 0 client-executable writers; the
  knobs read the values above (a pre-existing key is a FAIL, not a drift, the 0114:758-765 rule).
- (b) **One authority.** The count of functions in `pg_proc` (non-temp) whose `prosrc` contains
  `voyage.settle(` equals the pre-image count + 1 (the wrapper); the four reads each contain
  `voyage.settle_due(` exactly once; `pg_get_functiondef('public.tick_arrivals(timestamptz)')` equals
  its pre-image (M1 did not re-cut the sweep); `voyage.settle`'s def equals its pre-image.
- (c) **Parity when off** (NO_SPAGHETTI §3 item 3): with `merchant_settle_on_read` false, on the lit
  world (switch set true inside the rolled-back block, 0118:140-141), `world.sea_roster(null)`,
  `world.sea_roster(now() − 1 h)`, `world.port_merchants(p)` for the first harbour by code that has
  merchants, `world.npc_fleet_card(f)` and `world.fleet_trades(f)` for the first merchant by
  `roster_ord, fleet_id` each equal their `pg_temp` pre-image byte for byte (`is distinct from`).
- (d) **An arrival docks on the harbour's read.** Subject chosen deterministically: the first
  merchant by `nf.roster_ord, nf.fleet_id` with a `SAILING` voyage bound for a HARBOUR (assert one
  exists; if the as-found world has none, `cmd.standing_route_assign_for` one from the switch's
  pass inside the block, the 0116:136-140 fallback). Probe write: `update public.voyages set eta =
  now() − interval '1 second' where id = v` (a probe-only move, like 0118:183; `voyage.recompute_eta`
  stays the live ETA authority and is not called). Then, as `authenticated` through
  `cmd.assume_identity` (0092:1310), `v_pm := world.port_merchants(dest)`. Assert: the fleet is
  `DOCKED` or `UNABLE_TO_SAIL` with `port_id = dest`; the voyage is `ARRIVED`; her row in `v_pm`
  carries `port = dest code`, `voyage` null and `doing in ('resting','starting','passing')`
  (0104:186-189); `select count(*) from public.voyages where fleet_id = f and status = 'SAILING'
  and eta <= now()` is 0 afterwards (nothing left for the sweep: idempotence). If she arrived at her
  stop 0, additionally the lap closed (`closed_at` not null, `trades` not null, 0121:195) and
  `hold_until` lies within 120 ± 1 s of `now()` (0116:45-50 through 0101:94-100) — printed, not
  assumed, since the subject's stop is the world's choice.
- (e) **The map's read carries her in the same answer.** Same probe shape on a second subject
  through `world.sea_roster(now() − interval '45 seconds')` (the client's overlap,
  `live/worldStore.ts:367`): her row is served with `voyage` null (or a NEW voyage whose
  `departed_at >= now() − 1 s`, if the stop was intermediate and she sailed on), and `status`
  not `SAILING`-at-the-old-eta. Both arms are acceptable (§7C) and the receipt prints which.
- (f) **The bounds bite.** `merchant_settle_budget_ms = 0`: the read settles nothing (the subject
  stays `SAILING`; receipt `over_budget ≥ 1`). `merchant_settle_per_read = 1` with two due
  subjects: exactly one is settled (`settled = 1`), the other still `SAILING`. `merchant_wake_per_read
  = 0`: a rested subject (probe write `hold_until = now() − 1 s`, the `tests/npcOn.fixture.ts:62-63`
  method) is not woken by `world.npc_fleet_card(f)`; with the knob at 1 she is: her route has a
  new `lap_id` or she is `SAILING`, or her route is paused with a reason — the disjunction is
  asserted and the arm printed.
- (g) **A player's own fleet is not settled by the trade history.** A probe house's fleet at sea with
  `eta` moved past: `world.fleet_trades(own)` leaves it `SAILING` (the beat's `world.fleets()` is its
  settler, 0009:161-165; the lock-order reason, `live/worldStore.ts:689-697`).
- (h) **Dark, nothing.** `npc_traders_enabled` false: each read's answer is its dark pre-image and
  no merchant row moved (proof 12 MERCHANT_DARK, `scripts/db/proofs/12_merchant_companies.sql:357`).
- (i) **Measured and printed:** `ms` per settle (home arrival, intermediate arrival, wake) from the
  receipts, and the four reads' own ms before and after, in the `self-assert ok` notice — the
  numbers go to DEV_LOG.
- **What the self-assert cannot prove, said:** the `skip locked` / `lock_timeout` path across
  sessions. PGlite is single-connection (`docs/NPC_TRADERS.md:1362`); the shape is asserted (the
  literal `for update skip locked` and `set_config('lock_timeout'` in the wrapper's body) and the
  cross-session case is added to proof 12 beside MERCHANT_NOWAIT (`scripts/db/proofs/
  12_merchant_companies.sql:26`) as **MERCHANT_READ_SKIPS_HELD**: connection A holds a due voyage
  row `for update`; connection B calls `world.port_merchants(dest)` and must return within the budget
  with the fleet still `SAILING`; A releases; `tick_arrivals` docks her. CI's disposable Supabase
  runs it (`claude-memory`: the apply-proof is the net).

**Verification on prod, before `db push`:** the 0119-0121 method (`docs/RESUME.md:18`) — dry-run the
file inside `begin … rollback` on prod (`unwind_the_clock()` first, 0078:157-174, per the runbook),
read the receipt's ms, then push, `wind_the_clock()` (0078:182-207), and watch
`cron.job_run_details` for the arrivals job's duration over the next hour (expected: lower than
14.3 s avg, because reads now take arrivals off it) and `pg_stat_statements` for the four reads'
mean and max (expected under 2 s; a max near 8 s is the signal to lower the budget knob).

**Rollback:** (1) `update public.world_config set value = 'false' where key = 'merchant_settle_on_read'`
— instant, no migration; every read is its pre-image (assert (c)) and the sweep is again the only
docker. (2) A forward migration: `stable` back on the four reads (their old `pg_get_functiondef`
text is in M1's slices), `drop function voyage.settle_due`, `drop function
public.merchant_settle_on_read`; the knobs are inert without readers. Nothing else exists to undo.

---

## 6. The sweep: what M1 leaves alone, and the options measured against the 2-minute limit

- **M1 does not re-cut `public.tick_arrivals`** (0010:54-87 + 0092:772-783). It stays `* * * * *`
  (0012:97) and becomes the fallback for merchants nobody is reading. Its load falls: an arrival a
  read has settled is no longer due (0010:69-70), and a row a read holds is skipped (0010:65-66).
  Its 2-minute ceiling (0114:14-15) is untouched.
- **A 30-second cadence** (pg_cron ≥ 1.5 accepts `'30 seconds'`; prod's version must be read first —
  `select extversion from pg_extension where extname = 'pg_cron'` — it is not known here). Cost:
  the job's fixed cost (the due scan over `voyages`) twice a minute; overlapping runs already divide
  the work (0010:65-66), so a 14 s job on a 30 s cadence is safe, a 47 s max is not. Decision:
  only after M1's measurement, as its own one-line migration re-scheduling by name (0012:95-97
  shape; `wind_the_clock` activates what is defined, 0078:193-201).
- **Aligning departures so etas land just before the sweep**: rejected. `voyage.recompute_eta` is
  the one ETA authority (0100:41) and an eta that bends to a cron is a second author of time, and a
  gameplay distortion the owner did not ask for.
- **A cron job per arrival**: rejected. 830 jobs churning in `cron.job`, a second scheduler beside
  0012's one answer to "how often" (0012:92-99), and the same 1-minute floor on an old pg_cron.
- **Per-fleet subtransactions inside the sweep** (`docs/NPC_TRADERS.md:1351-1352`, TRADE_ROUTES'
  slice-2 item): still open, still not this file.

---

## 7. Why the 2026-10-08 "no viewer-side settle" (N13) is revisited, and what of it stands

N13 rejected a settling map read on numbers (`docs/NPC_TRADERS.md:833-839`, `:1095`): the beat was
3 s at 9,600×, a sea-day ended every 9 s, so *"EVERY beat of EVERY viewer would find every merchant
due"* — 20× the clock's load and 20× the deadlock exposure. Three of those premises are gone:
the clock is 960× (0100:55-60), the map's read is a roster delta every 30 s placed client-side
(0118; `live/worldStore.ts:370`), and M1 settles **arrivals and wakes only, never sea-day
boundaries** (§3.1 step 2), bounded by count and budget and skip-locked (§3.1 step 3). What
stands: *"no viewer locks"* becomes *"no viewer WAITS"* — a held row is `busy` within 500 ms; the
cron still settles everyone (§6); and `world.sea_traffic` itself is left exactly as N13 shaped it
(§3.2). The owner's requirement is the fourth premise that changed.

---

## 8. What the owner will see (plain words)

**Today:** a merchant reaches a city and hangs just off it for up to a minute and a half of real
time — sixteen to twenty-eight hours of ship's time — still drawn as sailing, her line reading
`to Lisbon · 0s`; the city's Port tab lists her as *Ending*; tap her and the card still says
SAILING. Then the minute sweep docks her and, up to half a minute later, the map moves her to her
berth. Her two-minute rest can likewise run to three before she sails.

**After M1:** the first time anyone looks — the map (every 30 s), the city's Port tab or her card
(every 7.5 s while open), her trade history — she is docked at once, exactly as the owner's own
fleet is: the hull sits at her berth, the line says `Lisbon`, the Port tab says *Resting* with the
countdown (at her home) or shows her trading and leaving (at a stop), the card and the history show
the lap that just closed or the stop's trades. When her rest ends she sails the moment someone is
looking, and within the minute otherwise. Nothing about where ships are drawn, how fast they move,
or what they earn changes; only the wait on the quay is gone. If anything goes wrong, one switch
puts the old behaviour back instantly.

---

## 9. Checklist for the implementer (the brief IS the plan, NO_SPAGHETTI §7B)

1. Read `voyage.settle` (0027:237-429), `cmd.advance` (0007:812-865), `cmd.run_standing_route` as
   last sliced (0092:575-721, 0101:84-107, 0114:646-683, 0117:151-159, 0120:687-710),
   `tick_arrivals` (0010:54-87, 0092:770-785), the four reads, and §3.1 — then write `voyage.settle_due`
   with NOTHING of theirs retyped.
2. Cut the four reads from `pg_get_functiondef` on the branch's applied chain AFTER 0122/0123
   (LF-normalised; `supabase/migrations/README.md:43-48`), keep the pre-images under `pg_temp`.
3. Self-assert §5 (a)–(i); break (c) and (f) on purpose once and watch them go red
   (`docs/NO_SPAGHETTI.md:345-348`).
4. Proof 12 gains MERCHANT_READ_SKIPS_HELD; `tests/rpc.surface.spec.ts` pins no volatility
   (grep found none), so no pin moves; `tests/duplication.spec.ts` needs the word *supersede* in
   the header.
5. Dry-run on prod in `begin … rollback`, push, wind the clock, measure (§5 "Verification"),
   write the numbers to `docs/DEV_LOG.md` and the anchor to `docs/RESUME.md`.

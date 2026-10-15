# ECONOMY_LOOP — gold goes round: cities keep a purse, merchants pay into it, cities spend it on the world

**Status: DESIGN ONLY (2026-10-15). Nothing in this file is built. No migration, no code, no production change.**

The owner, 2026-10-15, verbatim: *"i want to economy to be circulative, meaning that there should be a
way for these merchants gold to be reduced, weather it is by investing in cities. Then cities should have
gold too, and the city must use it for the whole world and so on, any ideas?"* — and then approved, in
this order:

1. City treasuries: harbour dues + a sales tax on every trade; wages, provisions, repairs and
   shipbuilding paid INTO the city where they happen (merchant running costs are 0 since 0116 — they come
   back as transfers to cities, not as destruction); merchant refounds funded by cities, not minted.
2. City bounties for goods a city lacks, paid above market from the treasury.
3. City spending: upgrades (docks / market / production → more stock, bigger berths), patrols (lower
   route hazard), aid to poorer neighbours in its region; upkeep so a city cannot grow for ever.
4. Merchant investment in cities (a share of a dock or warehouse, paid a share of its income).

Everything below is grounded in the live chain (`supabase/migrations/`, head 0118) and cites `file:line`.
Where a function has been re-cut by later slices, the line cited is its last full definition and the
slices that touched it are named; a migration that builds this plan must read the LIVE body with
`pg_get_functiondef` (LF-normalised, the 0114:573-590 helper shape) and assert each hunk occurs exactly once.

---

## 0. The answer in ten lines

1. **A city has one purse, `public.port_treasury.ducats`, and ONE mover, `public.treasury_post`**, the
   way a house has `players.ducats` and `public.credit` (0004:216). Nothing else writes a treasury.
2. **Income is never written by a tick: it is posted at the charge**, inside the verb that already knows
   the port (`f.port_id`) and already holds the port's `port_goods` lock. The post is one INSERT into an
   append-only `treasury_flows` table — no second row lock on the trade path, so a busy harbour's trades do
   not queue behind each other any more than they do today.
3. **Every transfer is one function, `public.pay_city(player, port, kind, amount, event)`** = `credit(−)`
   + `treasury_post(+)` in the same transaction; and its mirror `public.city_pays(port, player, kind,
   amount, event)`. The verbs' own `credit()` lines are sliced to call these; their player-side ledger kinds
   do not change, so the client's ledger words are untouched.
4. **One new hourly job, `byeharu-voyage:city` at `:37`**, is the only city-side process: it rolls the
   flows into balances and a per-(port, game-day, kind) daybook, charges upkeep, builds one level per city
   that can afford it, recomputes patrols, moves aid, accrues dividends, asserts `balance = Σ daybook` for
   every city in one statement, and prints world money in its receipt. Every step is one set-based
   statement over 224 harbours with `for update skip locked`; it never waits on the minute tick.
5. **Refounds stop minting.** `npc_tend`'s refound (live via 0115:204-209) is sliced to draw from the home
   harbour's treasury above its reserve, partially if that is all there is, or not at all — a merchant
   whose home is broke sails in ballast (0115) until the harbour earns.
6. **Bounties are the request board (0087), funded.** A harbour posts a request only when its treasury
   covers the premium, escrows it at posting, and `cmd.run_fulfil` pays the escrow — `PREMIUM` stops being
   a faucet.
7. **Upgrades live in a new table, `city_works`, never in the authored `ports.*` columns or the furnished
   `port_buildings` rows** (0067/0089 hold those equal to `data/ports.json`). Each level composes into
   exactly one existing reader: `voyage.sail_refusal` (draft), `world.daily_cap_remaining` and
   `world.spread` (market), `tick_market_drift`'s regeneration (production), `cmd.do_hire`'s pool
   (inn), `voyage.hazard_roll` (patrols).
8. **Investment is the drain.** Shares of a city's works are sold at the level's cost; dividends accrue
   set-based each hour and are PAID when the holder next docks there (one `credit()` on an arrival that
   already happens). A merchant whose purse exceeds twice her capital buys shares at home with the
   surplus — that single rule turns steady-state merchant growth into city works.
9. **The remaining faucet is the market itself** (what the townspeople pay for goods), bounded by
   `npc_min_return_pct`; the remaining sink is city works. Section 1 says exactly what is created and
   destroyed per hour after each step, and section 6 gives the one query that watches it.
10. **Dark first**: `city_treasury_enabled` false, the same shape as `npc_traders_enabled` (0092:125,
    0097). Flows are posted from day one (so the books are full when the switch flips), but no city spends
    and no refound is withheld until `select public.city_treasury_switch(true)`.

---

## 1. The money as it moves today, and after each step

### 1.1 Every faucet and every sink on the live chain

Gold exists only as `players.ducats`, moved only by `public.credit` (0004:216-241, which locks the player
row, refuses below zero, writes one `ledger` row). The kinds through `credit()` on the chain (grep of every
`public.credit(` call) and where each one's money comes from or goes to:

| Kind | Where (file:line) | Direction | Counterparty today |
|---|---|---|---|
| `FOUNDING` | `new_house` 0004:275 → 0096:469 (`p_ducats`), `starting_ducats` 8,000 (0001) | **faucet** | nothing. Each new player: 8,000. Each merchant at seeding: `capital + officer wages + tuition` (`npc_found` 0097:56-58); 0098 founded 60 companies (capital p50 46,000, max 665,000), 0105 founded 761 (capital p50 5,000, max 729,000, Σ 19.7 M) |
| `NPC_REFOUND` | `npc_tend` 0097:574 → re-cut 0114:324 → sliced 0115:204-209: purse < `capital × npc_purse_floor_pct` (0.20) and no refound in `npc_refound_cooldown_game_days` (30 game-days = 24 real h) → `credit(house, 'NPC_REFOUND', capital − purse)` | **faucet** | nothing. The weekly cap was deleted in 0115, so this is unbounded per company at one top-up a day |
| `SELL` | `cmd.do_sell` 0022:770 (sliced 0050, 0061, 0083, 0097 SELL ALL, 0114 floor): `credit(SELL, +q.total)` | **faucet** | the market, an infinite purse. `q.total` is post-tax: bid = mid × (1 − spread/2) × (1 − tax) (0005:433) |
| `PREMIUM` | `cmd.run_fulfil` 0087:449: `credit(PREMIUM, +c.premium_ducats)` | **faucet** | nothing (8-20 % of mid × qty, `contract_premium_pct_*` 0087:172-174) |
| `BUY` | `cmd.do_buy` 0022:674 (sliced 0050, 0061, 0080-0083, 0114 ceiling): `credit(BUY, −q.total)`; ask = mid × (1 + tax + spread/2) (0005:432) | **sink** | the market. The tax inside the ask is destroyed with the rest |
| `WAGES` | `voyage.settle` 0007:887 → 0027:299-307 (`−least(wages, purse)` per settled sea-day) → 0114:626-631 (`× running_cost_mult`) | **sink** | nothing. **Merchants pay 0 since 0116:40-44 (`npc_cost_mult` 0)**, so no merchant WAGES row is written at all (`if v_wages > 0`) |
| `PROVISION` | `cmd.do_provision` 0017:251 → 0114:635-639 (`× running_cost_mult`) | sink | nothing; merchants 0 |
| `REPAIR` | `cmd.do_repair` 0007:697 → 0114:641-646 (`× running_cost_mult`) | sink | nothing; merchants 0 |
| `HIRE` | `cmd.do_hire` 0007:632 → 0097 pool-floor hunk | sink | nothing. Merchants DO pay this (not under `running_cost_mult`): `hire_crew_rate` 20 per hand, ×2.5 urgent |
| `BUILD` | `cmd.do_build` 0072:269 (`−h.ducats`, `hull_recipes`) | sink | nothing. `ship_classes.build_cost` (0002:162) is read by nothing (RESUME open item 3) |
| `TUITION` | `cmd.study_skill` 0016:155 (kind at 0016:237), core in 0096:666 | sink | nothing |
| `OFFICER_WAGE` | `public.sign_officer` 0096 (kind at 0096:564) / door 0015:229 | sink | nothing |
| harbour dues | `port_fee_per_ship` 50 (0001:166) | — | **read by nothing** (RESUME open item 3) |
| pirates | `voyage.settle` outcomes 0027:342-349: `RANSOM` "We paid them off" costs 0; `PLUNDERED` leaves the cargo (RESUME item 3) | — | no money moves at all |

Transfers between purses: **none**. No player-to-player trade (DESIGN G.7 rule 6), no city purse. Every
movement is a house against the void.

### 1.2 The flow today, in one picture

```
            FOUNDING (8,000 / player;  capital at seeding)            NPC_REFOUND (capital − purse, daily)
                     │                                                        │
                     ▼                                                        ▼
   THE MARKET ──SELL (bid, post-tax)──▶ ┌───────────────────────────┐ ──BUY (ask, incl. tax)──▶ VOID
  (infinite)  ──PREMIUM (from nothing)─▶│  players.ducats           │ ──WAGES/PROVISION/REPAIR──▶ VOID   (merchants: ×0)
                                        │  (~830 merchants, a few   │ ──HIRE/BUILD/TUITION/OFFICER_WAGE─▶ VOID
                                        │   real players)           │
                                        └───────────────────────────┘
   Net creation per hour  =  Σ SELL + Σ PREMIUM + refounds  −  Σ BUY  −  Σ costs
   For a merchant since 0114-0117:  SELL ≥ 1.15 × BUY (npc_min_return_pct 15), costs ≈ HIRE only
   ⇒ every merchant lap is net-positive and nothing ever takes it back. That is the owner's complaint.
```

### 1.3 The flow after the four steps

```
                                  (F2) FOUNDING of a NEW PLAYER only (8,000)
                                                 │
  THE MARKET ──SELL──────────────▶ ┌─────────────▼──────────────┐ ──BUY net of tax────────────────▶ VOID (S1)
  (F1: the townspeople's      ◀────│  players.ducats            │
   purchases, the one faucet)      │  merchants + players       │
                                   └───┬──────────────────▲─────┘
       tax on every BUY and SELL ──────┤                  │  REFOUND (from home treasury, above reserve)
       DUES on arrival (50/ship)       │                  │  BOUNTY premium (escrowed at posting)
       WAGES of the leg, on arrival    │                  │  DIVIDEND (accrued hourly, paid on docking)
       PROVISION / REPAIR / HIRE /     │                  │  AID (city → city, inside a region)
       BUILD / TUITION / OFFICER_WAGE  │                  │
       SHARE (investment)              ▼                  │
                                   ┌──────────────────────┴─────┐
                                   │  port_treasury.ducats      │ ──WORKS (build a level) ───▶ VOID (S2)
                                   │  224 harbours              │ ──UPKEEP (per game-day) ───▶ VOID (S2)
                                   └────────────────────────────┘ ──PATROL (a level, upkeep) ─▶ VOID (S2)
```

**What stays a faucet, and why.** (F1) The market's purchases: a city's townspeople buy goods with money
that is not in any purse. Making the treasury the market's counterparty would be exact conservation, but a
broke harbour could then not buy, and with ~830 merchants and the ballast rule a stalled quay is a stalled
loop — the one decision in §7 the owner must take. (F2) A new player's 8,000: a handful of players, stated
and kept. (F3) The seeding faucets (`npc_found`, 0098/0105) happened once; this plan never founds a merchant
again without a treasury paying.

**What stays a sink, and why.** (S1) The market's sales net of tax: the townspeople's goods are paid for and
the money leaves. (S2) City works, upkeep and patrols: stone, timber and sailors' pay outside the game —
the one DELIBERATE sink, sized by knobs so that over a day it absorbs what (F1) minted. Everything else that
is destroyed today (wages, supplies, repairs, hire, build, tuition, officer wages, the tax half of a
BUY) becomes a transfer.

**Near-conservation, stated as arithmetic.** Per hour, with turnover `T` = Σ merchant BUY totals:

- minted by the market: `F1 − S1 ≈ (return − 1) × T` where `return` is what merchants actually realise
  (planned ≥ 1.15; the realised figure is the first thing to measure, §6.1).
- taken by cities from that: tax on both sides ≈ `2 × 0.03 × T` ≈ 0.06 T (the tax is ALREADY inside
  today's prices — this moves it from the void to a purse, it does not change a merchant's margin);
  wages at `npc_cost_mult` 0.25 ≈ 0.006 T (0114 measured wages 2.6 k on 52.5 k bought at mult 1);
  dues ≈ 0.001 T.
- so after step 1 merchants still net ≈ `(return − 1.07) × T` per hour, i.e. the purse growth is only
  trimmed. **Step 1 redirects; step 4 drains**: a merchant above `npc_invest_above × capital` invests the
  surplus above `npc_invest_keep × capital`, and a city spends what it holds above its reserve on works
  (S2). In steady state, Σ merchant purses sits between 1.5 and 2 × Σ capital and every ducat above that is
  city works within an hour. The knobs that size the faucet (`npc_min_return_pct`) and the sink
  (`works_cost_base`, `works_upkeep_pct`) are the two the owner turns if §6's query shows drift.

---

## 2. Step 1 — the treasury, the charges, and refounds that are paid for

### 2.1 Tables

```sql
create table public.port_treasury (
  port_id    uuid primary key references public.ports(id) on delete cascade,
  ducats     bigint not null default 0 check (ducats >= 0),
  rolled_at  timestamptz not null default now(),   -- flows at or before this are in `ducats`
  updated_at timestamptz not null default now()
);
-- one row per HARBOUR (ports.kind = 'HARBOUR', 0036:185), seeded at 0 — no faucet at deploy.
-- RLS: readable by anon + authenticated (world data, like port_buildings 0067:116-122); written by nobody but the server.

create table public.treasury_flows (          -- APPEND-ONLY; the trade path writes here and nothing else
  id         bigint generated always as identity primary key,
  port_id    uuid not null references public.ports(id),
  kind       text not null,                    -- TAX_BUY, TAX_SELL, DUES, WAGES, PROVISION, REPAIR, HIRE, BUILD,
                                               -- TUITION, OFFICER_WAGE, REFOUND, BOUNTY, BOUNTY_LAPSED, WORKS,
                                               -- UPKEEP, PATROL, AID_IN, AID_OUT, SHARE, DIVIDEND, CARRIED
  ducats     bigint not null,                  -- signed: + into the city, − out
  player_id  uuid references public.players(id),   -- the house on the other side, null for city-to-city / void
  ref_event  uuid references public.events(id),    -- the house's event, when there is one (BOUGHT, SOLD, VOYAGE_REPORT …)
  created_at timestamptz not null default now()
);
create index on public.treasury_flows (port_id, created_at);

create table public.treasury_daybook (        -- the city's book: one row per (port, game-day, kind)
  port_id   uuid not null references public.ports(id),
  game_day  int  not null,
  kind      text not null,
  ducats    bigint not null,
  primary key (port_id, game_day, kind)
);
```

Why three tables and not a per-movement ledger like a house's: a house's ledger row needs the house's row
lock (`credit()` takes `players … for update`, 0004:227); a treasury row lock per trade would make every
client PROVISION at Lisbon wait for the arrivals tick whenever a merchant traded at Lisbon inside it
(`tick_arrivals` settles every due fleet in ONE transaction, 0010:66-74, and its locks live to commit).
An INSERT into `treasury_flows` locks nothing. The hourly roll (§4) sums flows into the balance and the
daybook set-based. The daybook is the `trade_daily` shape (0022:702-704: `on conflict … do update set qty
= qty + excluded.qty`) and the `NPC_CARRIED` discipline (0097:804, step 2) bounds it: rows older than
`treasury_days_kept` collapse into one `CARRIED` row per city.

Append-only: a trigger `public.tg_treasury_append_only` refuses UPDATE/DELETE on `treasury_flows` and
`treasury_daybook` unless `current_setting('byeharu.treasury_roll', true) = 'on'`, set transaction-locally
by `tick_city` alone — the `forbid_mutation` re-cut's shape (0097:932-942). It is a sibling trigger, not a
re-cut of `forbid_mutation`, because that one's exemption reads `old.player_id … is_npc`, which these rows
do not have; the header says so.

### 2.2 The movers

```sql
-- THE one way a city's ducats move. Income: one INSERT. Spending: the same INSERT, after a balance check
-- that reads balance + Σ unrolled flows (public.treasury_balance), refusing below the reserve.
public.treasury_post(p_port uuid, p_kind text, p_delta bigint, p_player uuid, p_ref_event uuid) returns bigint
public.treasury_balance(p_port uuid) returns bigint         -- ducats + Σ flows after rolled_at (≤ 1 h of rows)
-- THE two transfers. Nothing in a verb calls credit() and treasury_post() side by side.
public.pay_city(p_player uuid, p_port uuid, p_kind text, p_amount bigint, p_event uuid)   -- credit(−) then post(+)
public.city_pays(p_port uuid, p_player uuid, p_kind text, p_amount bigint, p_event uuid)  -- post(−) then credit(+)
```

Spending writers are exactly three, all hourly and never concurrent (§4.3): `tick_city`, `npc_tend`
(refounds, inside `tick_reconcile` at :07) and `tick_contracts` (escrow, lazy on a read). A lazy escrow
may overdraw a reserve by one premium between two rolls; §3 bounds it with `bounty_reserve_mult`.

Server-only, revoked from `public, anon, authenticated` (the 0050:678 posture); `client_write_grants()`
(0010) stays 0 and the registry spec stays green.

### 2.3 The charges — each is ONE hunk in a live body

| Charge | Live body (last full def → slices) | The hunk, old → new |
|---|---|---|
| BUY tax | `cmd.do_buy` 0022:674 (0050, 0061, 0080-0083, 0114) | after `credit(f.player_id, 'BUY', −q.total, …)` at 0022:761: `perform public.treasury_post(f.port_id, 'TAX_BUY', round(q.total * v_tax / (1 + v_tax + v_spread/2)), f.player_id, v_ev)` where `v_tax := world.tax_rate(f.port_id)`, `v_spread := world.spread(f.port_id)` (0005:306-324). The player's debit is unchanged: the tax was always inside the ask (0005:432); this books the part that was the city's. Derived from the quote's own `total`, so there is no second price rule and `world.quote`'s return type (sliced four times, server-only since 0083:273) is not reopened |
| SELL tax | `cmd.do_sell` 0022:770 (0050, 0061, 0083, 0097, 0114) | after the `SELL` credit at 0022:831: `treasury_post(f.port_id, 'TAX_SELL', round(q.total * v_tax / (1 − v_tax)), …)` — what the bid withheld (0005:433). **This is new money** relative to today (the seller still gets `q.total`); it is part of faucet F1 and is said so in §1.3 |
| harbour dues | `voyage.settle` arrival branch (0027:410-425, live via 0047/0059/0086/0114) | before `perform cmd.advance(p_fleet, p_now)` at 0027:425: `pay_city(f.player_id, v.dest_port_id, 'DUES', least(purse, round(ships × wc_num('port_fee_per_ship') × running_cost_mult(f.player_id))), v_report_event)` — the 0001:166 knob finally read; `least(…, purse)` is the wages' own floor rule (0027:304-307) |
| wages of the leg | same branch, and the per-day hunk 0027:299-312 | (a) per-day hunk: the payload gains `'wages_paid', v_paid` beside `'wages', v_wages` (0027:312) where `v_paid` is the `least()` actually charged; (b) arrival: `treasury_post(v.dest_port_id, 'WAGES', Σ (ve.payload->>'wages_paid') over the voyage's voyage_events, f.player_id, v_report_event)`. The player-side `WAGES` rows stay per sea-day (the client's ledger is untouched); the city receives the leg's sum where the crew is paid off. A voyage that never arrives (ADRIFT / UNABLE_TO_SAIL, 0027:413) leaves its wages in the void — the one small leak, stated |
| provisions | `cmd.do_provision` 0017:251 → 0114:635-639 | `credit(f.player_id, 'PROVISION', −v_cost, ev)` (0017:327) → `pay_city(f.player_id, f.port_id, 'PROVISION', v_cost, ev)` |
| repairs | `cmd.do_repair` 0007:697 → 0114:641-646 | 0007:751 `credit(… 'REPAIR' …)` → `pay_city` |
| hire | `cmd.do_hire` 0007:632 → 0097 pool floor | 0007:690 `credit(… 'HIRE' …)` → `pay_city` |
| build | `cmd.do_build` 0072:169 | 0072:269 `credit(… 'BUILD', −h.ducats …)` → `pay_city` |
| tuition | `cmd.study_skill` 0016:155 (core 0096:666 area) | the `TUITION` credit → `pay_city(…, f.port_id …)` at the port the fleet lies in |
| officer wage | `public.sign_officer` 0096 (kind 0096:564) | → `pay_city` at the officer's `home_port_id` (0015:63) — the inn he is drinking in |
| merchant running costs | knob only | `npc_cost_mult` 0 → **0.25** (0114:80's value, measured there: a quarter of the wage left the average lap at ≈ +2.6 k). The three readers (`running_cost_mult` 0114:95-106 composed in settle / provision / repair) are untouched; dues ride the same multiplier |

`pay_city` inserts the flow with `ref_event` = the verb's own event (BOUGHT, PROVISIONED, …), so a city's
book and a house's ledger point at the same event row.

### 2.4 Refounds, paid by the home harbour

`npc_tend` (live body: 0097:574 → superseded 0114:324 → sliced 0115:150-215). The refound hunk after 0115
is exactly:

```
        perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
          public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
            'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
        v_refound := v_refound + 1;
```

Sliced to:

```
        v_can := greatest(0, least(hh.capital - hh.ducats,
                   public.treasury_balance(hh.home_port_id) - public.treasury_reserve(hh.home_port_id)));
        if v_can > 0 then
          perform public.city_pays(hh.home_port_id, hh.player_id, 'REFOUND', v_can,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', v_can, 'port', <home code>, 'partial', v_can < hh.capital - hh.ducats)));
          v_refound := v_refound + 1;
        else
          v_unfunded := v_unfunded + 1;      -- counted in the receipt (0097:799's jsonb)
        end if;
```

The company loop (`for hh in … where pl.ducats < h.capital × npc_purse_floor_pct`, 0115:~178) stays a
loop: `credit()` is per house and the cooldown bounds it to one refound per company per real day. The
event kind `NPC_REFOUNDED` is kept (the card reads it, `npc_compact` keeps it, 0097 §5.2 step 3). A merchant
whose home cannot pay is not parked (0115): the lap-start re-plan saves SELL-only lines and she sails in
ballast until the harbour has earned. `public.treasury_reserve(port)` = `treasury_reserve_hours` × the
city's mean hourly income over the last `treasury_days_kept` (from the daybook) — one reading, used by
every spender.

### 2.5 Knobs (step 1)

| Key | Start | Why |
|---|---|---|
| `city_treasury_enabled` | `false` | dark first (0092:125 shape). Flows are posted regardless; spending and the refound change wait for the switch |
| `npc_cost_mult` | 0 → **0.25** | 0114's measured-safe value; it is what 0114 shipped before 0116 zeroed it. Raise towards 1 only after §6.1 shows laps still positive |
| `port_fee_per_ship` | 50 (exists) | finally read. ~0.1 % of turnover; a knob, not a lever |
| `tax_rate` | per port 0.03 (exists, CHECK 0–0.08, 0002:101) | the Mayor band of DESIGN H.3; the lever for a single city |
| `treasury_reserve_hours` | 6 | a city keeps six hours of its own income before it refounds, posts bounties or builds |
| `treasury_days_kept` | 30 game-days (= 1 real day) | the daybook window; ≤ 224 × ~10 kinds × 30 rows |

### 2.6 Client (step 1)

The city tray on MAP (`src/features/map/MapScreen.tsx:355`, `CityMerchants.tsx`) is growing tabs
Market | Port | Inn. **Treasury goes on the Port tab's head**: one line, `Treasury 123,456 d.`, read from a
new `world.treasury(p_port)` (registered in `public.client_rpc_entry_points()`, last full definition 0083:625, rows added by slices through 0118;
catalogue `worldTreasury` in `src/lib/rpc/catalog.ts` beside `worldPortMerchants` :315). Under it, the
daybook for the last game-day as a few rows: `Tax · Dues · Wages · Yard · Inn` in, `Refounds` out. The
LEDGER tab needs nothing: a house's rows keep their kinds; `DUES` is one new word for `docs/WORDS.md`.

### 2.7 Self-asserts (migration 0119, as found, every probe rolled back)

- Shape: the two tables, the trigger refuses UPDATE/DELETE without the GUC and allows DELETE with it;
  `treasury_post` refuses a spend that would take `treasury_balance` below 0 (`E_CITY_BROKE`).
- Every hunk occurs exactly once in each live body (the 0114:573-590 helper), and the pre-image is
  byte-identical outside the hunk.
- A probe house BUYs at a probe harbour: the purse moves −`q.total` exactly as the pre-image (the player
  side is unchanged), and a `TAX_BUY` flow of `round(total × tax / (1 + tax + spread/2))` appears with
  `ref_event` = the BOUGHT event; the same for SELL/`TAX_SELL`. PROVISION / REPAIR / HIRE / BUILD /
  TUITION / OFFICER_WAGE: purse delta + flow = 0, kinds unchanged in `ledger`.
- A probe voyage settled to arrival: a `DUES` flow of `ships × 50 × mult` and a `WAGES` flow equal to Σ
  `wages_paid` over its `voyage_events`, both pointing at the VOYAGE_REPORT event; the per-day payload
  carries `wages_paid` ≤ `wages`.
- `running_cost_mult(merchant) = 0.25`, `(player) = 1`.
- Refound: a probe merchant under the floor with a funded home → `REFOUND` flow − and `NPC_REFOUNDED`
  event with `partial` false; home at exactly reserve + 100 → a refound of 100, `partial` true; home at
  reserve → no flow, no credit, receipt `refound_unfunded` = 1. The live `npc_tend` body no longer
  contains `'NPC_REFOUND', hh.capital - hh.ducats`.
- The 0097 scan: no body in `cmd`, `world`, `public`, `voyage` contains `auth_uid is null`.
- Grants: `treasury_post`, `pay_city`, `city_pays`, `treasury_balance` not executable by `anon` /
  `authenticated`; `world.treasury` executable by `authenticated` only and present in the registry;
  `client_write_grants()` = 0.
- Dark: with the switch off, `npc_tend` refounds nothing and reports every under-floor house as
  `refound_dark`; flows are still posted (asserted: a probe BUY posts tax while dark).

### 2.8 Server cost (step 1)

- **Trade path**: +1 INSERT into `treasury_flows` per BUY/SELL/PROVISION/REPAIR/HIRE/BUILD, +2 per
  arrival (dues, wages). No new lock. Inside the transaction that already holds the `port_goods` row.
- **Rows/hour**: ≈ (merchant trades + player trades) + 2 × arrivals + charges. With ~830 fleets on
  laps of 2–8 stops and up to `npc_lines_per_stop` 3 lines (0097), the ceiling is a few thousand flows an
  hour; the realised figure is read from `cron.job_run_details` of the city job on the first day (its
  receipt prints `flows_rolled`). Flows are deleted after the roll, so the table holds ≤ 2 h of rows.
- **No new cron for step 1** if the roll is left to step 3's job; until step 3 lands, `tick_reconcile`
  (0097 hunk at :7, 61–72 s of its 120 s) must NOT carry the roll — it is already at the edge. The roll
  is therefore step 1's one new job too: `byeharu-voyage:city` at `37 * * * *` (§4.3), doing only the
  roll + the reconcile assert until step 3 fills it in. Expected < 1 s: 224 balances, ≤ 2 k daybook
  upserts, one `delete … where created_at <= rolled_at`.

---

## 3. Step 2 — bounties: the request board, funded by the treasury

The board already exists and is the right shape. `public.trade_contracts` (0087:178-202): a harbour posts
`contract_posts_per_day` (1) requests a game-day for a good it does NOT offer (0087:46-49: never for what
it sells — a request for an offered good is an instant arbitrage on one quay, bid + premium vs ask), lot
`1–3 × trade_step_tuns`, premium 8–20 % of mid fixed per unit at posting, open `contract_deadline_days` (4).
`public.tick_contracts(port, now)` (0087:272-331) posts, expires and prunes **lazily on a read**
(`world.contracts` 0087:352, `cmd.run_fulfil` 0087:412: "the read is the catch-up"; no cron, 0087:337).
`cmd.run_fulfil` pays the premium from nothing (0087:449).

### 3.1 Slices

| Live body | Hunk |
|---|---|
| `public.tick_contracts(uuid, timestamptz)` 0087:272 | in the posting loop, before the INSERT (0087:319): `continue when public.treasury_balance(p_port) − public.treasury_reserve(p_port) < round(v_per_unit × v_draw.qty) × wc_num('bounty_reserve_mult')`; after a successful INSERT: `treasury_post(p_port, 'BOUNTY', −premium_ducats, null, null)` — **escrow at posting**. In the expire UPDATE (0087:297-299): `… returning premium_ducats` → `treasury_post(p_port, 'BOUNTY_LAPSED', +Σ, …)` for every row just expired (one INSERT … SELECT) |
| `cmd.run_fulfil(uuid, uuid)` 0087:~400-460 | 0087:449 `credit(f.player_id, 'PREMIUM', c.premium_ducats, v_event)` stays — the escrow already left the treasury; the flow that pays it is written at posting. The row's `fulfilled_by` is kept. The player-side kind `PREMIUM` and the receipt (0087:455-460) are untouched |
| `public.contract_draw(uuid, int, int)` 0087:216 | `seq` runs `1 .. posts(port)` where `posts(port) = least(wc_int('bounty_posts_max'), 1 + floor(treasury_balance / wc_int('bounty_post_per_ducats')))` — a rich city asks for more; the draw itself stays pure in (port, day, seq, secret) |
| `world.contracts(p_port)` 0087 | serves `funded: true` on every row (an unfunded request is never posted, so the client needs no new state); the Market tab prints the rows it already prints on PORT › Trade (`src/live/useRequests.ts`, `useFulfilPreview.ts`) |

"Goods a city lacks" is kept as 0087 defines it (not on the roster). Asking for an OFFERED good whose
stock is under target is the owner's phrase read literally, and it is unsafe as 0087:46 says: a 20 %
premium exceeds spread + tax (6 % + 3 %), so a fleet could buy at the ask and deliver at the bid + premium
on the same quay. It is §7 Q3.

Merchants do not fulfil requests (the planner reads `world.trade_routes`, 0019:676, not the board). This
step keeps bounties a player's income and a city's spend; letting `cmd.standing_route_lines` (0114) add a
FULFIL line for a merchant is a later slice and said so.

### 3.2 Knobs

| Key | Start | Why |
|---|---|---|
| `bounty_reserve_mult` | 2 | a request is posted only when the treasury above reserve covers it twice — a lazy post cannot overdraw the hourly spenders by more than half a premium |
| `bounty_posts_max` | 3 | the board stays short |
| `bounty_post_per_ducats` | 50,000 | one more request per 50 k in the treasury |
| `contract_premium_pct_min/max` | 0.08 / 0.20 (exist) | unchanged |

### 3.3 Self-asserts (migration 0120)

Wind a probe harbour at balance 0: posts 0, the pre-image posted 1. Fund it: posts 1, a `BOUNTY` flow of
−`premium_ducats`; Σ(treasury + escrow) unchanged. Warp past expiry, wind: `BOUNTY_LAPSED` + the same
sum. Fulfil with a probe house: `PREMIUM` ledger row = the row's `premium_ducats` (0087:937's own
assert), no treasury flow at fulfilment, world money (Σ purses + Σ treasuries) before − after = exactly
the sale's own market movement. The receipt's keys are 0087's.

### 3.4 Server cost

Per read of a harbour's board: one `treasury_balance` (≤ 1 h of flows by index) and ≤ 3 flow INSERTs
per game-day per harbour. Rows/hour: ≤ 224 × 3 / 0.8 h ≈ 800 at most, in practice tens. No cron.

---

## 4. Step 3 — city spending: works, patrols, aid, upkeep; the one hourly job

### 4.1 Tables

```sql
create table public.city_works (
  port_id      uuid not null references public.ports(id) on delete cascade,
  kind         text not null check (kind in ('docks', 'market', 'production', 'inn', 'patrols')),
  level        int  not null default 0 check (level between 0 and 5),
  paid_day     int  not null,          -- upkeep charged through this game-day (the regen's last_regen_day shape, 0010:120)
  updated_at   timestamptz not null default now(),
  primary key (port_id, kind)
);
create table public.sea_patrols (        -- derived each hour from city_works.patrols, read by voyage.hazard_roll
  sea_id uuid primary key references public.seas(id),
  level  int not null check (level between 0 and 5)
);
```

Not `ports.*` and not `port_buildings.tier`: `has_yard`, `yard_tier`, `max_draft`, `dev_*`, `crew_pool`
are authored in `data/ports.json` and world-guard holds the applied world equal to the file (0067
header), and `public.furnish_harbours` (0089) holds `port_buildings` to `harbour_buildings`. A level a
city raises lives in its own row and composes into a reader; the authored truth is never written.

### 4.2 What a level does — one reader each

| Work | Reader (live) | Composition |
|---|---|---|
| `docks` — bigger berths | `voyage.sail_refusal` E_DRAFT (0036:443-447: `max(class.draft) > dest.max_draft`) | `dest.max_draft + public.city_level(dest, 'docks') / wc_int('docks_draft_per_levels')` (2 → +1 draft at levels 2 and 4). Also the dues: `DUES × (1 + 0.1 × level)`? No — one effect per work; dues stay the knob |
| `market` — more to trade | `world.daily_cap_remaining` (0027:445: `daily_cap_fraction × stock_target`) and `world.spread` (0005:306) | cap × `(1 + wc_num('market_cap_per_level') × level)`; spread − `spread_per_dev × level` (the dev_commerce rule, one more term, same floor). The per-company allowance is "how much stock a city lets one house move a day"; the stock itself is the production work's |
| `production` — more stock | `public.tick_market_drift` regeneration UPDATE (0010:111-121, `production_rate × (v_day − last_regen_day)`) | `production_rate × (1 + wc_num('production_per_level') × cw.level)` via a `left join city_works cw on cw.port_id = pg.port_id and cw.kind = 'production'` — the statement is already set-based over 132 k `port_goods` rows; the join adds ≤ 224 rows |
| `inn` — hands return | `cmd.do_hire` draws `ports.crew_pool` and only `cmd.do_dismiss` (0086:219) refills it; **no tick regenerates it** (NPC_TRADERS §2, measured) | a NEW set-based hourly statement in `tick_city`: `update ports p set crew_pool = least(cap, crew_pool + wc_int('inn_hands_per_level') × cw.level) …` with `cap = size_tier × wc_int('inn_pool_per_tier')`. The authored 0003 values are the seed; a city with no inn level never regains hands (today's rule, kept) |
| `patrols` — safer sea | `voyage.hazard_roll` (0006:666-690; live body is 0059's `encounter_at`, 0059:13): `v_p := least(hazard_p_max, greatest(0, v_base × hazard_mult))` | `× (1 − wc_num('patrol_hazard_cut') × coalesce((select level from sea_patrols where sea_id = …), 0))`. `sea_patrols.level` = `least(5, Σ city_works.patrols.level over the sea's harbours)`, rewritten by `tick_city` in one INSERT … ON CONFLICT. `hazard_roll` runs once per settled sea-day per fleet at sea (~800 × 40/h); a one-row lookup on a ≤ 60-row table |

Pirates cost no money today (`RANSOM` 0, `PLUNDERED` leaves cargo, RESUME item 3) — a patrol's value is
crew not lost (DRIVEN_OFF / PLUNDERED / STRIPPED take crew, 0027:364-370) and therefore `HIRE` not paid.
Low until pirates cost something; stated, not papered over.

### 4.3 `public.tick_city(p_now)` — one job, one transaction, every step one statement

Cron: `byeharu-voyage:city` on `37 * * * *`. Why :37: `reconcile` is `7 * * * *` (0012:99) and runs
61–72 s; `arrivals` is every minute (0012:97); `drift`, `price-snapshot` and `buff-calendar` are
`tick_cron_expression(600)` = `*/10` (0012:98, 0013:199, 0026:468) → :00 :10 :20 :30 :40 :50. :37 is clear
of all of them except the minute tick, which is unavoidable. Defined INACTIVE by its migration (the 0078
rule, 0026:470-475) and started by `wind_the_clock()` (0078:182, which activates whatever
`clock_jobs()` names — a `byeharu-voyage:%` name is picked up without touching 0078). Local mode (PGlite,
no pg_cron): the stand-in calls it the way it calls the other ticks (NPC_TRADERS §8.5, X13).

Never waits: `set local lock_timeout = '2s'` (the 0097:971 line) and every UPDATE goes through a
`select … for update skip locked` CTE (the `tick_arrivals` idiom, 0010:72); a row the minute tick holds
is skipped this hour and caught the next. Each step in its own `begin … exception when others` block
with its error in the receipt (the 0097:972-987 shape), so one broken step cannot hide a broken book.

```
 1. ROLL      set_config('byeharu.treasury_roll','on',true);
              with f as (select * from treasury_flows where created_at <= p_now for update skip locked),
                   d as (insert into treasury_daybook (port_id, game_day, kind, ducats)
                           select port_id, world.game_day(created_at), kind, sum(ducats) from f group by 1,2,3
                         on conflict (port_id, game_day, kind) do update set ducats = treasury_daybook.ducats + excluded.ducats),
                   b as (update port_treasury t set ducats = t.ducats + x.s, rolled_at = p_now
                           from (select port_id, sum(ducats) s from f group by 1) x where x.port_id = t.port_id)
              delete from treasury_flows where id in (select id from f);
 2. CARRY     daybook rows with game_day < today − treasury_days_kept → one CARRIED row per port (insert…select, delete)
 3. UPKEEP    update city_works cw set paid_day = today  from port_treasury t …
                 charging  Σ_levels works_upkeep_pct × cost(level) × (today − paid_day)  as a −UPKEEP flow;
              where the treasury cannot pay: level = level − 1 (decay, never debt), flow 0, counted
 4. BUILD     one level per city per hour, at most: the city whose balance − reserve ≥ cost(level+1) for
              its LOWEST-level work (ties by kind order docks, market, production, inn, patrols) — a window
              function picks one (port, kind) row per port; −WORKS flow; level + 1
 5. PATROLS   insert into sea_patrols select sea_id, least(5, sum(level)) … on conflict do update
 6. INN       the crew_pool regeneration statement (§4.2)
 7. AID       per region (ports.region_id, 25 regions, 0003:115): median balance m; donors = balance >
              aid_donor_mult × m give aid_rate × (balance − aid_donor_mult × m); recipients = balance <
              aid_recipient_mult × m, split by shortfall. One CTE: two flow INSERTs (AID_OUT, AID_IN) and
              the balances move at the next roll. Σ over the region is unchanged to the ducat (rounding
              goes to the largest recipient)
 8. ACCRUE    step 4's dividend statement (§5)
 9. ASSERT    select count(*) from port_treasury t join (select port_id, sum(ducats) s from treasury_daybook group by 1) x
                using (port_id) where t.ducats <> x.s   → must be 0, else raise (the whole hour rolls back,
              the receipt says which city, like tick_reconcile's purse assert 0010:144-146)
10. RECEIPT   jsonb: flows_rolled, built[], decayed[], aid_moved, patrols, world_ducats =
              (select sum(ducats) from players) + (select sum(ducats) from port_treasury), ms per step
```

`cost(level) = works_cost_base × works_cost_growth ^ (level − 1)`; the `BUILD` step reads a city's
`treasury_reserve` so it never spends the hours of income the refound and bounties need.

### 4.4 Knobs

| Key | Start | Why |
|---|---|---|
| `works_cost_base` | 20,000 | level 1 of a work ≈ two hours of a middling harbour's tax; a rich harbour builds one level an hour until upkeep bites |
| `works_cost_growth` | 1.6 | level 5 = 131 k; the H.2 exponent's spirit on a city's scale |
| `works_level_max` | 5 | the `port_buildings.tier` range (0067:109) |
| `works_upkeep_pct` | 0.02 per game-day of each level's cost | a level 1 work costs 400 / game-day ≈ 12 k a real day; five works at level 5 ≈ 160 k a real day — a harbour that earns less decays. **This is the "cannot grow for ever"** |
| `docks_draft_per_levels` | 2 | +1 draft at docks 2 and 4 |
| `market_cap_per_level` | 0.10 | +50 % daily allowance at level 5 |
| `production_per_level` | 0.10 | +50 % production at level 5 — a producer port only (`production_rate` is 0 elsewhere, 0010:119) |
| `inn_hands_per_level` / `inn_pool_per_tier` | 2 per hour / 40 | a level-5 inn restores 10 hands an hour, never past `size_tier × 40` |
| `patrol_hazard_cut` | 0.10 per sea level | −50 % at a fully patrolled sea; `hazard_p_max` (0.060) still clamps above |
| `aid_donor_mult` / `aid_recipient_mult` / `aid_rate` | 2.0 / 0.5 / 0.10 per hour | a city twice its region's median gives a tenth of its excess an hour to cities under half the median |

### 4.5 Client (step 3)

**Port tab**: under the treasury line, one row per work — `Docks ●●○○○`, `Market`, `Production`, `Inn`,
`Patrols` — with the level and, when the city is saving, `next 32,000 d.`; a small `−decayed` word when
upkeep failed last hour. Nothing to press: a city spends by itself (the owner's words: "the city must use
it for the whole world"). **Inn tab**: `Hands 38 / 120` with `+10 an hour` when the inn has a level.
**Market tab**: the daily allowance it prints already (`useBuyCapacity.ts`) grows with the market level
and needs no new word. **MAP**: a patrolled sea is a later atmosphere slice (`docs/MAP_ATMOSPHERE.md`),
not this one. All of it is `world.treasury(p_port)`'s one read.

### 4.6 Self-asserts (migration 0121)

- The job is defined, inactive, named `byeharu-voyage:city`, and `clock_jobs()` lists it; `tick_cron_expression`
  is not used (the hour has no slot knob) — the literal `37 * * * *` is asserted once in `cron.job`.
- `tick_city(now)` on the live world inside a rolled-back probe: completes, its receipt carries every key,
  `ms` per step is printed in the receipt and the self-assert refuses > 20 s total.
- Roll: Σ flows before = Σ daybook delta + Σ balance delta; flows table empty of rows ≤ p_now; the ASSERT
  step passes; the trigger refuses a DELETE of a daybook row outside the GUC.
- Build: a probe harbour at reserve + cost(1) builds exactly one level (its lowest), −WORKS flow; at reserve
  + cost(1) − 1 builds nothing. Upkeep: warp one game-day, charge = `0.02 × cost(1)`; at balance 0 the level
  decays to 0 and no flow is written. Σ(treasuries) + Σ(WORKS, UPKEEP flows) is conserved.
- Composition, each against its pre-image with the level at 0 (byte parity) and at 5: `voyage.sail_refusal`
  admits a draft `max_draft + 2`; `daily_cap_remaining` × 1.5; `world.spread` − 5 × `spread_per_dev` (floored);
  the regen statement's `production_rate × 1.5` on a probe producer row; `hazard_roll`'s `p_hazard` × 0.5
  with `sea_patrols` 5 (recomputed from DESIGN B.6's own arithmetic as 0059:740-748 does); `crew_pool` +10
  and never past the cap.
- Aid: a probe region with balances (100 k, 10 k, 1 k): the donor gives `0.10 × (100 k − 2 × 10 k)`, the
  recipient under 5 k receives it, Σ unchanged to the ducat.
- `skip locked` and `lock_timeout` literals present in the live body; the job's receipt prints `world_ducats`.

### 4.7 Server cost (step 3)

- One hourly transaction at :37: 10 statements over 224 harbours, ≤ 60 seas, ≤ 1,120 works rows, ≤ 2 h of
  flows. Estimated 0.5–3 s on prod (the roll's daybook upsert over a few thousand flows is the largest).
- Rows written per hour: balances 224, daybook ≤ 224 × 10 kinds (new rows only on a new game-day; ~1,800
  rows per real day), `city_works` ≤ 1,120 updates, `sea_patrols` ≤ 60, `ports.crew_pool` ≤ 224, flows
  for UPKEEP/WORKS/AID ≤ ~1,500, the CARRY ≤ 224 inserts + ≤ 2,240 deletes. Total ≈ 5 k row writes/hour,
  ~0.5 MB/hour before vacuum; `autovacuum_vacuum_threshold = 2000, scale_factor = 0` on `treasury_flows`
  and `treasury_daybook` (the 0095/0097 shape).
- `tick_market_drift` gains one `left join` on ≤ 224 rows inside an UPDATE that already touches 132 k
  rows once a game-day — unmeasurable. `hazard_roll` gains a PK lookup per settled sea-day.
- `tick_reconcile`: unchanged except the refound slice (fewer, not more, credits).
- Disk: the three tables at steady state ≈ 10–15 MB on a 341 MB database.

---

## 5. Step 4 — merchants (and players) buy a share of a city's works

### 5.1 Tables and rules

```sql
create table public.city_shares (
  port_id    uuid not null references public.ports(id) on delete cascade,
  kind       text not null,                 -- a city_works kind
  player_id  uuid not null references public.players(id) on delete cascade,
  shares     int  not null check (shares > 0),
  accrued    bigint not null default 0,     -- dividends earned, not yet paid
  accrued_day int not null,                 -- accrued through this game-day
  primary key (port_id, kind, player_id)
);
```

- A work at level L has `L × shares_per_level` (100) shares. A city OFFERS shares while it is saving for
  its next level (`balance − reserve < cost(L + 1)`), at `cost(L + 1) / shares_per_level` each; the
  purchase is `pay_city(player, port, 'SHARE', price × n, event INVESTED)`. The money is what builds the
  level at the next :37 — a merchant's surplus becomes city works (S2) within the hour.
- **Dividend**: `dividend_share` (0.5) of the work's income of the game-day × `shares / (L × 100)`.
  Income per work is read from the daybook, one kind each: docks ← `DUES`; market ← `TAX_BUY + TAX_SELL`;
  production ← `TAX_SELL` of producer goods? no — `TAX_SELL` wholly; inn ← `HIRE`; patrols ← nothing
  (a patrol pays no dividend; its shares exist so a city can fund one). A kind that two works claim would
  pay twice, so the map is a table in the migration header and asserted disjoint.
- **Accrual is set-based** (step 8 of `tick_city`): one UPDATE over `city_shares` joining the daybook for
  game-days between `accrued_day` and today, writing `accrued` and a −DIVIDEND flow per (port, kind). Not
  one `credit()` per holder per hour.
- **Payout rides an arrival**: in `voyage.settle`'s arrival branch (the same hunk as dues, §2.3), after the
  dues: `for each city_shares row of (f.player_id, dest port) with accrued > 0: credit(player, 'DIVIDEND',
  accrued, v_report_event); accrued := 0` — one or two credits on an arrival that already pays dues. A
  holder who never comes back is never paid; the city keeps the float. The flow was already posted at
  accrual, so the books stay conserved whether or not the holder calls.
- **Merchants invest** in `npc_tend`'s existing per-company loop (0115's refound loop body, §2.4):
  purse > `npc_invest_above` (2.0) × capital → buy `floor((purse − npc_invest_keep × capital) / price)`
  shares of the HOME harbour's currently offered work, at most `npc_invest_max_per_hour` (50) companies an
  hour, oldest-purse-first, under `npc_upkeep_spent()` (0114:107-119) like everything else in the hour.
  Through the same door a player uses: `public.invest_for(p_player, p_port, p_kind, p_shares)` (the 0092:310
  `_for` core precedent), skin `cmd.invest(p_port, p_kind, p_shares)` + `cmd.preview_invest` (the 0087
  `fulfil` / `preview_fulfil` pair), docked-only, not a queue verb (no change to `cmd.parse`'s grammar
  0008:207 / 0072:292).

### 5.2 Knobs

| Key | Start | Why |
|---|---|---|
| `shares_per_level` | 100 | a share of a 20 k level is 200 d.; a 5,000-capital merchant can hold a few |
| `dividend_share` | 0.5 | half the work's income to its holders, half to the city |
| `npc_invest_above` / `npc_invest_keep` | 2.0 / 1.5 × capital | a merchant invests only her surplus and keeps six months of capital; the floor the refound watches is 0.2 |
| `npc_invest_max_per_hour` | 50 | bounds the loop inside the hour's budget |
| `invest_min_ducats` | 1,000 | no dust purchases |

### 5.3 Client

**Port tab**, under the works: `Shares · Docks 40 / 100 offered · 200 d. each` and, for the viewer,
`You hold 12 · 1,340 d. owed` with one `Invest` press that opens the amount tray (`useOrderPreview.ts`'s
step tray with `cmd.preview_invest`). A merchant's sheet (`src/live/MerchantSheet.tsx`, from
`world.npc_fleet_card`) gains one line, `Invested 24,000 d. at Lisbon`, from the card. Words for
`docs/WORDS.md`: Shares, Invest, Dividend.

### 5.4 Self-asserts (migration 0122)

Buy: refuses a kind the city does not offer (`E_NOT_OFFERED`), more than offered (`E_OVERSUBSCRIBED`),
under `invest_min_ducats`; purse + treasury conserved; the INVESTED event. Accrue: a probe daybook of 10,000
`DUES` on a day, 50 of 100 docks shares held → `accrued` 2,500, a −DIVIDEND flow of 2,500 at the city.
Payout: settle a probe voyage into that harbour → `credit(DIVIDEND, 2,500)`, `accrued` 0, no flow (already
posted). `npc_tend`: a probe merchant at 3 × capital buys down to 1.5 × capital at her home, counted in the
receipt; at 1.9 × buys nothing. The hour's budget cuts the loop (the 0114 `deferred` count).

### 5.5 Server cost

Accrual: one UPDATE over ≤ (224 × 5 × holders) rows — a few thousand at most; one INSERT … SELECT of
flows. Payout: ≤ 2 `credit()`s per arrival with holdings (merchants hold at home, so once per lap). Purchases:
≤ 50 `credit()`s an hour inside `tick_reconcile`'s existing budget (each ≈ 1 ms). Rows/hour ≈ 1–3 k.

---

## 6. Balance: targets, the watch query, the levers

### 6.1 Targets

No production figure was read while writing this (a read-only aggregate was started and did not return);
the numbers below rest on 0114's measured laps (sold 56.1 k / bought 52.5 k / wages 2.6 k) and the
0098/0105 capital sums. The first thing 0119 does on day one is read them for real, through §6.2.

| Measure | Target | How it is read |
|---|---|---|
| Share of merchant turnover that reaches cities | 6–10 % (tax 6 % + wages 0.6 % at mult 0.25 + dues) | `select kind, sum(ducats) from treasury_daybook where game_day >= today − 30 group by kind` against Σ `standing_route_laps.bought` over the same day |
| Merchant realised return | 1.05–1.15 × bought per lap, after costs; never a falling mean over a day | `select avg(net / nullif(bought,0)) from standing_route_laps where closed_at > now() − interval '1 day'` |
| Σ merchant purses | 1.5–2.0 × Σ `npc_houses.capital`; flat over a day once step 4 is on | `select sum(p.ducats) / sum(h.capital) from players p join npc_houses h on h.player_id = p.id` |
| Treasury turnover | a city spends what it earns within ~1 real day: Σ treasuries ≈ 12–24 h of Σ city income | the daybook's in vs out over 30 game-days |
| Refounds | falling to near zero; `refound_unfunded` near zero after the first day | `tick_reconcile`'s receipt in `cron.job_run_details` |
| World money | slope ≈ 0 over a day (± the sum of new players' 8,000s) | §6.2 |

### 6.2 The one query

```sql
-- world money, hour by hour, from the city job's own receipts (cron keeps the return value)
select start_time, (return_message::jsonb ->> 'world_ducats')::bigint as world_ducats,
       (return_message::jsonb ->> 'world_ducats')::bigint
         - lag((return_message::jsonb ->> 'world_ducats')::bigint) over (order by start_time) as delta
  from cron.job_run_details
 where jobname = 'byeharu-voyage:city' and status = 'succeeded'
 order by start_time desc limit 24;
```

A positive `delta` every hour of more than ~1 % of world money is inflation (the market faucet is winning);
a negative one is deflation (works are over-charged, merchants will hit the floor and refounds will drain
the cities). The daybook by kind says which side: `TAX_*`/`WAGES` in vs `WORKS`/`UPKEEP` out.

### 6.3 The levers, live (`update public.world_config set value = … where key = …`)

| Drift | Turn |
|---|---|
| Inflation: merchant purses climb | `npc_min_return_pct` 15 → 12 (a smaller faucet; 0114 measured p95 four-hour drift at 9.2 %, so not below 10); `npc_invest_above` 2.0 → 1.5 (invest sooner); `npc_cost_mult` 0.25 → 0.5 |
| Cities hoard | `treasury_reserve_hours` 6 → 3; `aid_rate` 0.10 → 0.25; `works_cost_base` down |
| Cities broke, refounds unfunded | `works_upkeep_pct` 0.02 → 0.01; `works_cost_base` up (fewer levels); a port's `tax_rate` up within the 0–8 % band |
| One harbour runs away | its `ports.tax_rate` (the Mayor band) and `aid_donor_mult` |

None of these needs a migration; each is one knob with one reader.

---

## 7. Risks, and the questions only the owner can answer

**Risks (handled, stated):**
- *The arrivals tick grows.* Each merchant arrival adds two flow INSERTs and up to two dividend credits;
  each trade one INSERT. Against an average of 11 s a minute that is a few hundred ms. The hourly job never
  touches a fleet row and skips what is locked, so the :07/:08 deadlock pattern (reconcile vs arrivals on
  fleets) has no new edge.
- *`tick_reconcile` is at 61–72 s of 120.* Step 1 and 4 add only to `npc_tend`'s company loop (fewer
  minting credits, ≤ 50 investment credits) under the existing 60 s deadline (0114:73-76). The roll and
  every city step live in the new job, not here.
- *Lazy bounty escrow vs the hourly spenders* can overdraw a reserve by one premium; `bounty_reserve_mult`
  2 and the `check (ducats >= 0)` on the balance bound it; `treasury_post` refuses below zero.
- *Merchant purses today.* Since 0116 merchants have earned at zero cost for a day; some purses will be far
  above capital. Step 4 will drain them into their home harbours' works within hours of its switch — a
  visible burst of building in the richest harbours on day one, said here so it is not read as a bug.
- *A world-guard proof may compare `ports.crew_pool` to the file.* The inn regeneration writes it (as
  `do_hire` already does); if a proof holds it equal, the proof learns the column is live (it must already,
  because hiring moves it).

**Questions for the owner:**
1. **Should the market itself be the city's purse?** That is full conservation: a city pays sellers from
   its treasury and keeps buyers' money. A broke harbour then cannot buy and ~830 merchants find closed
   quays. Recommended: no — keep the market external and tune the works sink (§1.3). Decide before 0119.
2. **Merchant running costs: 0.25 or 1.** You said on 10-14 that merchants should always earn and 0116 set
   their costs to 0. 0.25 is 0114's measured-safe value; 1 makes them pay what a player pays and some laps
   will lose. Recommended 0.25, raised by knob after a day of §6 readings.
3. **"Goods a city lacks": only goods it does not sell (0087, safe), or also roster goods whose stock is
   under target (the literal reading, an arbitrage on one quay unless the premium is capped under
   spread + tax)?** Recommended: as 0087.
4. **Upgrades decay or go into debt?** Recommended decay (a level lost, never a negative treasury) — it is
   the "cannot grow for ever" rule with no new state.
5. **Who else may invest?** Players through `INVEST` (built here), merchants at home only (built here), or
   merchants anywhere on their loop (one more line in `npc_tend`, later).

---

## 8. Migrations, in order, and what each re-cuts

| # | Name | New | Live bodies sliced (hunks asserted exactly once) | Switch |
|---|---|---|---|---|
| 0119 | `a_city_keeps_a_purse` | `port_treasury`, `treasury_flows`, `treasury_daybook`, trigger; `treasury_post`, `treasury_balance`, `treasury_reserve`, `pay_city`, `city_pays`; `world.treasury`; `tick_city` (roll + assert only); cron `byeharu-voyage:city` inactive | `cmd.do_buy`, `cmd.do_sell`, `cmd.do_provision`, `cmd.do_repair`, `cmd.do_hire`, `cmd.do_build`, `cmd.study_skill`, `public.sign_officer`, `voyage.settle` (2 hunks), `public.npc_tend` (refound), `public.client_rpc_entry_points` | `city_treasury_enabled` false; `npc_cost_mult` 0.25 |
| 0120 | `a_harbour_pays_for_what_it_asks` | — | `public.tick_contracts`, `public.contract_draw`, `world.contracts` | same switch |
| 0121 | `a_city_spends_on_the_world` | `city_works`, `sea_patrols`; `tick_city` steps 2–7, 9 | `voyage.sail_refusal`, `world.daily_cap_remaining`, `world.spread`, `public.tick_market_drift`, `voyage.hazard_roll`, `cmd.do_hire` (cap read) | same switch |
| 0122 | `a_merchant_buys_a_share_of_the_quay` | `city_shares`; `invest_for`, `cmd.invest`, `cmd.preview_invest`; `tick_city` step 8 | `voyage.settle` (payout, same arrival hunk), `public.npc_tend` (purchases), `world.npc_fleet_card`, registry | same switch |

Deploy by the runbook (`unwind_the_clock()` → `db push` → `wind_the_clock()`), 0119 alone first, a day of
§6 readings with the switch off (flows posting, nothing spending), then `city_treasury_switch(true)`,
then 0120–0122 one at a time. Every migration's self-asserts hold as found and roll back their probes;
none runs a long block on prod through `db query` (RESUME 10-14 rules).

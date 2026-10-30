# 2026-10-29: 0277, the ledger names its points (R4's migration)

> **Renumbered to 0284 on 2026-10-30 (0277 → 0283 → 0284: prod passed 0277; 0283 went to the hull-durability fix).** Authored as 0277; prod passed it while it waited (0278–0282
> deployed), and a version below the prod head can never be pushed. The file and its self-assert were
> re-cut to `20260818000284_the_ledger_names_its_points.sql` — unchanged in substance; every "0277" below
> reads "0284".

R4's first half, from `docs/COMMAND_REDESIGN.md` §4 ("What is missing today, and what R4 adds"):
the ledger names **no port, no fleet and no voyage**. `ref_event_id` points at an event whose
payload usually carries only the fleet's *name* (`BOUGHT`, `PROVISIONED`, `REPAIRED`);
`INSURED` alone carries `port` and `voyage_id`. Report groups by point (port / voyage / earlier),
so the point must live on the row. This slice adds the three columns and the one filler trigger.
**It changes no writer, no knob, no client read.** The `world.report` function and the Profit → Report
client face are the slice's second half (its own PR).

## What 0277 does

- `public.ledger` gains three **nullable** `uuid` columns: `port_id`, `fleet_id`, `voyage_id`.
  Old rows keep null (append-only, no backfill) and read as the point "Earlier".
- **One** BEFORE INSERT row trigger, `ledger_points`, calls **one** function,
  `public.tg_ledger_points()`, which fills the three at insert. Every writer gets it for free
  because the trigger sits on the table.
- **No foreign keys on the three columns — decided.** A restricting FK would make
  `npc_compact`'s deletion of an NPC house's ended voyages fail the hourly reconcile; `ON DELETE
  SET NULL` and `ON DELETE CASCADE` would run an UPDATE / DELETE against the append-only trigger
  (`forbid_mutation`, 0004) and raise. The columns are Report's points, advisory by design; a
  dangling id reads null in Report's join.
- **No new index.** Every read the trigger makes is served by an existing index: events PK,
  `fleets_player_name_unique (player_id, lower(name))`,
  `voyages_one_sailing_per_fleet (fleet_id) where status = 'SAILING'`,
  `voyages_fleet_ended_0249 (fleet_id, eta) where status <> 'SAILING'`. The trigger's cost on a
  row with no event (WAGES, TAX, the compactor's roll) is one null check.

## The one resolution rule (decided by default; the owner may reverse it)

At INSERT, when a row arrives with every point null:

1. **fleet** = the ref event's `payload->>'fleet'` name, resolved to **exactly one** of
   **this player's** fleets **at this instant** (`lower(name)`; the unique index makes two
   impossible, so "exactly one" is the rule stated, not a defence). Zero — the fleet was renamed
   or is gone — reads **null**.
2. **port** = that fleet's own dock, `fleets.port_id` — null while she sails (by
   `fleets_position_is_unambiguous`). The payload's `port` **code** is never resolved: one
   authority (the fleet), one meaning (where the money moved from the fleet's point of view).
3. **voyage** = the fleet's current voyage (the one SAILING; at most one by the unique index),
   else the one she most recently **ARRIVED** on (by `eta`; the 0249 partial index serves the
   read). An ABORTED voyage is never attributed.

**Never a guess, never a raise:** no event; an event that names no fleet; a name that names no
fleet of hers; an event of **another player** (the event must be the row's own player's); a fleet
with no voyage — all read null, and a null point is always acceptable. No cast that can fail
(`->>'fleet'` is text-or-null), no lookup that can error (indexed probes and keyed reads only).
A row that arrives with a point already set keeps it — a writer that knows better has spoken
(none does today). The instant is the inserting transaction's: the trigger sees the writer's own
uncommitted state, which is exactly the state the writer acts on.

**Timing consequences, said plainly:** a SAIL's PROVISION is bought while the fleet is still
docked, so it reads the origin port and the *previous* voyage (the next voyage does not exist
yet at insert time). INSURANCE is paid just after departure: fleet + voyage fill, port reads
null (she sails). INSURANCE_PAID and PORT_FEE at arrival fill whatever the fleet's instant state
is at the moment settle writes them. These are the rule applied honestly, not guesses.

## The writers — the design's claim, verified in the chain

The design says "public.credit and public.pay_city are the only writers." **True for every
gameplay row, with two refinements:**

1. `public.pay_city` (0122:344-361) never inserts into the ledger directly — it **composes**
   `public.credit` (the player's leg) and `treasury_post` (the city's flow). So pay_city rows are
   credit rows.
2. One compactor body inserts directly: `public.npc_compact_houses` (0257, re-cut 0258/0265) — the
   `NPC_CARRIED` roll, with a **null** ref event and a past `created_at`. `npc_compact_house` and
   `npc_compact` compose it (0265: "runs THE rules, public.npc_compact_houses (unchanged,
   md5-asserted)"). The trigger's first branch leaves the roll row's points null — correct: a
   roll-up row has no single point, and the cost is one null check.

Every direct `insert into public.ledger` in the live bodies is therefore in `public.credit` or
`public.npc_compact_houses` — pinned by a body scan in the migration's self-assert (it refuses if
a third writer exists, which is exactly the verification the design asked for). The trigger sits
on the table, so **every** writer — including any future one — gets the points by construction.

## What stays null, by kind

| kind | why the point stays null |
|---|---|
| `FOUNDING` | the FOUNDED event carries no fleet key |
| `TAX` | no ref event (`do_sell`, 0122:542 / 0128) |
| `WAGES` | no ref event (`do_sell` 0128:249 passes null; settle's 0122:615 has none) |
| `DONATION` | DONATED: a port code only, no fleet |
| `SHARE` | INVESTED: a port code only, no fleet |
| `DIVIDEND` | SURPLUS_GIVEN: no fleet |
| `TUITION` | ENROLLED: no fleet |
| `NPC_REFOUND` | NPC_REFOUNDED: no fleet |
| `MERCHANT_SURPLUS` | SURPLUS_GIVEN: no fleet |
| `GRANT` | no ref event |
| `NPC_CARRIED` | no ref event (the compactor's roll) |
| `PROBE_*` | self-assert rows, rolled back |
| every old row | append-only; no backfill — reads "Earlier" |

Filling (when the name still resolves): `BUY`/`SELL` (BOUGHT/SOLD), `PROVISION`
(PROVISIONED), `REPAIR` (REPAIRED), `HIRE` (HIRED), `INSURANCE`/`INSURANCE_PAID`
(INSURED/INSURANCE_PAID), `PORT_FEE` paid at the port call (settle's VOYAGE_REPORT),
`TOW` (TOWED), `PREMIUM` (FULFILLED) — all carry the fleet name. A row whose event names a
fleet renamed since reads null, never guessed.

## The probe plan (all rolled back; never a DELETE from an append-only table)

The migration's self-assert, through the **real** `public.credit` on a probe house at Lisbon
(plus a second house for the cross-player control):

1. no ref event → all three null (the old writers' shape, and the compactor's);
2. an event that names no fleet → null;
3. a name that is no fleet of hers ("Ghost 0277" — the renamed/gone case; two fleets of one name
   is structurally impossible, and `fleets_player_name_unique` is pinned in the guard) → null;
4. an event of **another player** whose own fleet answers to the name → null;
5. her fleet by name, docked, never sailed → fleet + port fill, voyage null;
6. after an ARRIVED voyage → all three fill, voyage = the arrived one;
7. the fleet put to sea with a SAILING voyage → fleet + voyage fill (SAILING preferred),
   port null;
8. a re-run of the same insert on the same state → the same triple;
9. a row that arrives with points already set keeps them;
10. positive control: an UPDATE of a filled row is still refused (append-only bites);
11. nothing survives the rollback (players, fleets, events, ledger rows, voyages).

Plus the structural asserts: the three columns are three nullable uuids; the trigger is the one
BEFORE INSERT row trigger; `ledger_append_only` and `ledger_reconciles` are still there; **the md5
of every other function in public / cmd / world / voyage is unmoved** and the client registry
count is unmoved (nothing else in this file touches an existing body); the writers' body scan.

## The gate (one cached run, 2026-10-29)

`node scripts/db/proof.mjs standing` — chain 262 migration(s) (261 restored from the prefix cache,
0277 applied), 262 self-assert receipts, world-guard ok, `11_standing_route.sql` 5/5 PASS in 0.5 s.

**First run RED, the defect it caught:** the writers' scan expected
`{credit, npc_compact_house, npc_compact_houses}`; the live head has
`{credit, npc_compact_houses}` — after 0265 the NPC_CARRIED insert lives in
`public.npc_compact_houses` alone, and `npc_compact_house`/`npc_compact` compose it. Fixed the
expected set and the header/notice wording; **no rule changed** — the trigger never referenced the
compactor bodies, only the verification did.

The self-assert's verbatim receipt:

```
0277 self-assert ok: THE LEDGER NAMES ITS POINTS. Three nullable point columns and one BEFORE INSERT row trigger on the ledger; every other function in the four schemas unmoved by md5, the registry unmoved; the writers are public.credit and public.npc_compact_houses (public.pay_city composes credit — verified); the rule through the real writer, rolled back: no event / no fleet name / a ghost name / another player''s event all read null; her fleet by name fills fleet + port at her dock, then all three with the arrived voyage, then fleet + voyage (port null) once she sails; the re-run is identical; points already set are kept; the append-only bite still bites; nothing left behind.
```

## PROD CHECKS (before the push; read-only; in the PR body)

1. The three pinned indexes exist on prod (`fleets_player_name_unique`,
   `voyages_one_sailing_per_fleet`, `voyages_fleet_ended_0249`) — one SELECT from `pg_indexes`.
2. The writers' scan as a read-only SELECT: functions whose body matches
   `insert\s+into\s+public\.ledger` = `public.credit`, `public.npc_compact_houses` — nothing else.
3. A sample of the live catalogue: how many ledger rows have a ref event whose payload carries a
   `fleet` key (the rows this slice will start filling), and a spot-check that today's BOUGHT /
   SOLD events' fleet names still resolve to the players' current fleets (the null rate of the
   rule on live data, before the columns exist).
4. The prod head, and that `public.tg_ledger_points` does not already exist (double-apply guard).

## The after-check (prod, read-only, after the push)

- The next hourly reconcile runs green (the trigger cannot raise, and the compactor's
  NPC_CARRIED rows keep null points — verified in the probe; `reconcile_runs` receipt).
- An hour later: a SELECT counting new ledger rows with `fleet_id is not null` (rows written
  after the push), and a spot-check of one player's fresh BUY/SELL rows: `port_id` = the port of
  the trade, `voyage_id` = the voyage just arrived on.
- No beat degradation: the trigger adds at most two index probes per fill and one null check per
  other row; the arrivals beat timing is the instrument (`arrivals_beats_kept`).

## Forward rollback

This file is purely additive. A forward slice reverses it:

```sql
drop trigger ledger_points on public.ledger;
drop function public.tg_ledger_points();
alter table public.ledger drop column port_id, drop column fleet_id, drop column voyage_id;
```

## Overhead

Three index probes per filled row (events PK, fleets unique, voyages partial), one null check
per unfilled row. No new index, no new knob, no writer change, no client change. The self-assert
scans every function body twice (the md5 and the writers' scan), the same cost 0272's self-assert
already pays.

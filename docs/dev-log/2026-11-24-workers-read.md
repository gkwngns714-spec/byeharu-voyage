# 2026-11-24 — `workers-read`: the workers and their actions (0496, proof 199)

The owner: *"it is like madevor's rs3 jagex game idle game, but instead of doing with only 1 player, i do it with multiple"*.
Plan: `docs/design/hq-corp-2026-11-24.md` A2.1, A2.2, A2.5, B3 and the slice `0495 rate-ledger`. This is its read half, minus
`world.company_rate`, which 0493 built. Server only: the HQ worker list (H1) hooks the two reads up afterwards.

**2026-11-25, before its deploy:** a repeating run's `per_hour` is now its DAY'S, the tick's wait is in `interval_s`, and the Best
run carries no rate (three more functions). The measurements and the rule: `docs/dev-log/2026-11-25-per-hour-honest.md`. Where the
text below says otherwise, that file is right.

## Server (0496; no switch, no coin, no table, no cron; nothing written)

- `world.workers()`: client read. One row for each of her fleets, then her land party.
- `world.actions(worker)`: client read. `worker` is a row's `id` (`fleet:<uuid>` or `party:<n>`). Only what the server would take.
- `public.action_shape`: the one shape (A2.1), and the one place `per_hour`, `xp_per_hour` and `items_per_hour` are worked out.
- `public.job_trip`: a job's legs from `public.fleet_job_sails` (0494, the authority), priced by `world.trip_cost` (0360).
- `public.sea_actions_for`, `public.land_actions_for`, `public.workers_for`, `public.away_parties_for`: the cores, server only.
- `public.away_report_for`: one hunk adds `parties`; every existing key is kept.
- `public.client_rpc_entry_points`: one hunk adds the two reads.
- Grants: the six cores revoked from public, anon, authenticated and service_role; the two reads for authenticated alone.
- All plpgsql. The shape is IMMUTABLE, the other seven STABLE.

### The shape

```json
{
  "id": "sea:fixed:quicksilver:LIS:SET:sell",
  "kind": "sea", "skill": "trading", "level": 1,
  "interval_s": 135,
  "inputs":  {"coin": 433315, "items": []},
  "outputs": {"coin": 453439, "items": []},
  "xp": [{"skill": "trading", "xp": 1773}, {"skill": "exploration", "xp": 0}],
  "cost": {"total": 16, "back": {"wages": 8, "stores": 0, "dock_fee": 0}},
  "net": 20108, "per_hour": 536213, "xp_per_hour": 47280, "items_per_hour": 0,
  "basis": "quote",
  "job": {"kind": "fixed", "params": {"good": "quicksilver", "buy": "LIS", "sell": "SET"}},
  "good": "quicksilver", "buy": "LIS", "sell": "SET", "end": "sell", "units": 225, "returns": true, "varies": false
}
```

- A sea action carries `job` (what `cmd.set_fleet_job` takes). A land action carries `action` (what `cmd.land_send` takes).
- Ids: `sea:best`, `sea:fixed:<good>:<buy>:<sell>:<sell|store>`, `sea:haul:<yard>`, `land:<job>`. A running action and its option
  share the id.
- A worker row: `{id, kind, fleet, name, at, state, worker_state, action, progress, stop, runs, measured}`.
  - `state`: idle, working, waiting, stopped. `worker_state`: a fleet's one state (`public.fleet_state`), a party's phase.
  - `progress`: `{from, to, leg}`. Sea: the voyage's `departed_at` and `due_at`, leg out / back / way, `from_port`, `to_port`.
    Land: this trip's start and `next_home_at`, leg = the phase, with `turns_home` and `in_packs`.
- The away report's `parties` row: `{party, action, good, state, phase, since, seen_at, turns_home, turns_booked, in_packs, waiting,
  xp_due, stop, next_home_at}`; `stop` is cap, shed_full or done.

### No second estimator

| Figure | Its quote |
|---|---|
| A run's good, harbour, units, buy cost, profit, seconds out | `world.best_sales` (the card) |
| The sale, whole | `world.quote` |
| The sail back; a bring-home's trip home and back | `world.trip_cost` over `public.fleet_job_sails`' legs |
| A bring-home's units and cost | `public.fleet_buy_capacity`; `public.fleet_job_ends` when the home shed binds |
| A land job | `public.land_terms`, the terms Send freezes |

- **A sea run's interval is the whole cycle:** the card's seconds out + the dock turn there (`world.trip_stop_seconds`) + the sail
  back + the turn at home. `net` = the card's profit less the sail back's wages, stores and dock fees.
- The Best run is one way (its next run starts where it sold): `returns` false, `varies` true.
- What the quotes do not serve, said in the file: a card has no split of tax, wages, stores and dock fee on the way out (only
  `world.good_board`'s full row has, a second's work a good). So `cost.total` = sale - buy - net, and the sail back's parts are
  `cost.back`. A new harbour's 25 Exploration is not counted. No coin moves ashore yet (wages: 0498).

### Only what the server would take

- A run whose way out or back the leg judge shuts is not offered (0494: range, stores, no course).
- A door shut for every option answers `closed {code, sentence}` and no option: dark (`E_NOT_IN_USE`), a standing route
  (`E_ROUTE_TAKEN`), the party out (`E_LAND_OUT`), a haul waiting (`E_SHED_FULL`).
- A land job whose terms name a refusal (level, materials, no land in reach) is not offered.
- Bring home is offered only docked, away from home, lit, and when `public.fleet_job_end` and the shed take it.
- The probe and the proof set every served option through the real doors: none refused.

### Basis (the field `basis` on every action)

| Basis | When |
|---|---|
| `runs` | her own completed runs: her fleet's ledger rows since the job was set (24 h at most), from her first BUY to her last, when at least 3 BUYs lie there (two whole runs) |
| `quote` | an option; in `world.workers`, a Best run under way (the card its plan took, kept on the job) |
| `terms` | a land job: the terms frozen at Send |
| `none` | not priced yet (a fixed job before two whole runs): null figures |

`world.workers` asks no quote (a quote is a second's work a fleet). A fixed job with too few runs reads `none`; `world.actions` serves
the same id with its quote while she lies at the job's buy harbour.

## Decided by default (the owner may reverse)

- The fixed runs priced there and back are the 8 best cards of her harbour (in the Best run's own order). Bring home lists every
  good the harbour sells.
- "Enough runs" is 3 BUYs (two whole runs). A run is measured BUY to BUY.
- A fleet at sea is quoted from the harbour she is bound for; one at anchor gets the Best run unpriced.
- A party that is out has no options (the door would refuse): the client offers "call home" first.
- Client rate: `world.workers` no more than once in 60 s (and once after a command or when a stamp passes); `world.actions` when the
  Assign sheet opens, no more than once in 300 s a worker, never on a timer. Both are served as `ask_s`.

## Measurements (local PGlite, this PC, one company)

- 0496 applied on the chain's snapshot at 0494: self-assert passed, 3.9 s. 22 options set through the doors, none refused.
- `world.workers()`: 2 to 7 ms (budget 100 ms).
- `world.actions(fleet)`: 744 to 1,017 ms (budget 1.5 s). `world.best_sales` alone is 440 ms of it. 9 options at Lisbon, 13 at Porto.
- `world.actions(party)`: 32 to 52 ms.
- Proof 199: 8/8. Proofs 184, 195, 197 (they read the away report): 7/7, 5/5, 7/7 with 0496 applied.
- Load: no rows, no tables, no cron. 0 new rows a minute.

## Client

- `src/lib/rpc/types.ts`: `WorkersView`, `WorkerRow`, `WorkerAction`, `WorkerProgress`, `WorkerActionsView`, `AwayPartyRow`;
  `FleetJobsReport` gains optional `parties`.
- `src/lib/rpc/catalog.ts`: `worldWorkers`, `worldActions`. `tests/rpc.surface.spec.ts`: the pin.
- No screen, no wrapper in `lib/rpc/index.ts`: H1 adds them.

## Not verified

- Prod: nothing was read.
- `tests/rpc.surface.spec.ts` was not run locally (with no built image it applies the chain from zero); its pin list was edited and
  CI runs it. `tsc -b`, eslint on the touched files, `db.budget` and `news.lint` passed; 455 versions distinct. The before / after reads are in `scripts/ops/harness/workers-read/`.
- The dock turn was 0 s in every local run (the local economy is open, so `world.trip_stop_seconds` is 0; it is `port_prep_seconds`
  while the economy is closed).
- `world.actions` on real Postgres 17 was not timed. Its cost on prod is the client's to read (`ms`); the after-check cannot call it
  (it reads the caller).
- The `runs` basis was read from planted ledger rows. Proof 199 shows a real BUY's row carries its fleet; whole real cycles were not
  played (a transaction has one instant).
- A bring-home's stored units an hour on the `runs` basis read STORED events by the fleet's NAME (the event carries no id): two
  fleets of one company with one name would share them.

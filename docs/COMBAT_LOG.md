# COMBAT LOG: the design for slices C1-C4 (docs/COMBAT_LOG.md)

Owner, row 315: *"combat - like a log, with action that i choose to do such as when pressed fight, it keeps on fighting, when flee, it tries to flee etc - showing logs, damages etc. system, engaging"*.

Read-only design, 2026-11-12, against the local chain at 0350. Nothing was run on prod and no file was changed. Every choice marked **default** was decided without asking; the owner may reverse it.

## 0. The answer in twelve lines

1. **C1** keeps the numbers the engine already computes. The raid's skin adds one compact `log` to its answer; `voyage.settle` already copies every extra key of that answer into the day's payload, so the day needs no hunk. One hunk carries it into the VOYAGE_REPORT. Human fleets only: an NPC raid stays byte for byte.
2. One client component, `FightLog`, draws it in History and on the arrival card. An old event with no `log` draws its English sentences as today.
3. **C2** stores a standing order per fleet (no row = Fight), frozen on the voyage's segments at departure beside `danger` and `raider`, and read by the one engine as `opts.a_order`.
4. **Flee**: her guns are silent, she takes that round's fire, then rolls to slip on a new stream. **Pay**: RANSOM before a shot, `ransom_share` of the cargo at cost. **Fight**: today.
5. The choice is real. An unarmed coaster should never Fight; a good lookout makes Flee beat Pay; guns make Fight best against a small raid and worst against a large one (arithmetic in 2.5).
6. Engine parity is asserted as text: a `pg_temp` copy of the live engine against the new one on 0320's own matrix, plus prod's `golden.sql` digest before and after.
7. **The plan's frame is wrong in one place.** A new argument on `voyage.fight_resolve` or `voyage.fight` would be a new function (Postgres overloads), and proof 28 holds the 5-argument one by name. So the skin's body moves to a new `voyage.raid_report(..., opts)` and `fight_resolve` stays as a one-line wrapper.
8. **C3**: a battle freezes its sheet at the start and re-runs the engine to round N with the stance list. No per-round engine state. Determinism is a prefix property, proved below.
9. A battle's hold must burn nothing. Today a 600 s hold adds about 7 voyage days of stores, wages and hazard rolls through `voyages.delay_hours`.
10. **C4 as written: no-go.** It needs `voyage.settle` to suspend inside its most-cut arm, for a raid she is rarely watching. Build **C4-lite** instead: the raid is told when its day settles and the client paces the same log.
11. Combat pays by how it ended (C5, rides R1). Running pays a little, paying pays nothing.
12. No board, no art, no dice, no forecast, no PvP.

## 0.1 What was checked, and what was not

**Checked in the repo:**
- `public.fight_sides` and `public.fight_volley`: created by 0320, never re-cut. 0323, 0334 and 0340 only call them. The guard allows `public.wc`, `public.wc_num`, `public.fight_volley`, `public.armour_soak`, `voyage.rng`.
- `voyage.fight_resolve`: 0189, re-cut 0202, 0204, 0213, 0276, replaced whole by 0320, two hunks by 0323. Proof 28 holds the pre-0320 body whole, by digest, under the 5-argument name.
- `voyage.fight`: 0189; hunks 0198, 0276, 0323. Its live last line is 0323's: `return voyage.fight_resolve(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), voyage.fleet_hulls(p_fleet));`.
- `voyage.settle`: last whole body 0027, cut by about 30 files since; the latest are 0314, 0322, 0330, 0334, 0339. The day's payload takes `(v_fight - 'rounds' - 'outcome' - 'sentence' - 'hull_lost')` (0189, hunk 4), so any new key of the skin lands in `payload.fight` unasked.
- The day's payload already holds `crew_before`, `crew_lost`, `base_loss`, `surgeon_pct` (0027) and `cargo_lost` (0213).
- `voyage.depart`: 0047; hunks 0330, 0334, 0339. `voyage.freeze_danger` (0330) and `voyage.freeze_raiders` (0339) write keys on each segment of `voyages.path`.
- `cmd.divert` keeps sailed segments whole and sails on through `voyage.depart` (0330's header), so a turn freezes again.
- `public.fight_points` (0127) is the only reader of a stored outcome. It pays EVADED and DRIVEN_OFF.
- An anonymous RANSOM moves no gold today. `public.pirate_ransom` runs only for a named raider (0339).
- `voyage.total_days` is `ceil((sim_hours + voyages.delay_hours) / 24)` (0006), which is why a hold burns days.
- The client reads fights only from the player's events (`world.ledger`, 50 a read). It has no realtime channel: it polls.
- `attack_on()` is read in five places: `battle_open`, `attack_for`, and the cargo, navy and pirate ship cards.

**Not verified (read these first):**
- Prod's switches. By the chain's last writer (0204) `combat_bite` is true and `armour_turns_pct` 0.5; `pirates_bite`, `attack_enabled`, `navy_enabled` were false at their deploys. The plan says two reports disagree on `combat_bite`. **If it is false, C1 and C2 show nothing until the fight is lit.**
- Prod's knob values. Every figure below is the seed value from 0189, 0322 and 0135.
- The live text of `voyage.settle`. Anchors below are the latest hunk texts in the repo, not prod's body. R1 (0352) may cut the same function first.
- Whether `world.fleets()` settles a sailing fleet on every read. Several doors do; DESIGN D.2 says reads do. The design is correct either way.
- The hunk history of `voyage.total_days` and `voyage.days_complete` after 0006 (needed only for C3).
- The human raid rate, `voyage.escort_score`'s exact formula, and how long `voyage_events` and `events` rows are kept.

## 1. C1: the log with damage

### 1.1 What is kept

One new key, `log`, built by the skin (never by the engine) and only when asked.

```json
"log": {
  "v": 1,
  "order": "FLEE",
  "first": "THEY",
  "foe":  {"n": "Şebek (xebec)", "k": 2.3, "crew": 81, "hull": 1219, "ship": "Black Joke"},
  "you":  [["Gaivota", 400, 400, 8]],
  "r":    [[1, "L", 1, 0, 0, 0, 1, 2, 1, 41.2, 358.8, 1219, [[1, 10]], 0.06]],
  "end":  "FLED",
  "board": [8, 81, 0.31],
  "after": [["Gaivota", 358.8]]
}
```

| Key | Meaning |
|---|---|
| `v` | Shape version. The client draws only a version it knows |
| `order` | Her order in this fight. Absent means Fight (C2) |
| `first` | YOU, THEY or BOTH: who saw whom |
| `foe` | Raider class name, hulls (`k`), crew, hull at the start; `ship` only for a named pirate ship |
| `you` | Each of her hulls in fleet order: name, hull before, full hull, crew before |
| `r` | One array a round: round, range (L, M, C), then **you** can / fired / hits / damage dealt, then **them** the same four, her hull left, their hull left, her ships struck `[[ship index, % of her size]]`, and the slip chance if she ran that round |
| `end` | STOOD, SLIP, BROKE, THREW, TERMS, TAKEN, GAVE; C2 adds FLED and PAID |
| `board` | Her crew, their crew, the ratio. Only when boarded |
| `after` | Each hull's hull after the shot (start less `hull_lost`) |

**Per-ship hull by round is not kept (default).** The engine gives the fleet's hull left each round and which ship was struck for what percent. For a one-ship fleet that is the ship. Exact per-ship figures by round would need an engine change, and C1 makes none. `after` is exact.

**Per-ship crew after is not kept (default).** The crew is lost in `voyage.settle` after the fight, and the day already keeps the fleet's `crew_before` and `crew_lost`. The log's loss line reads those.

### 1.2 Where, and how much

| Where | What | Size |
|---|---|---|
| `voyage_events.payload.fight.log` | The day's own record. No settle hunk: the subtraction carries it | About 0.6 kB |
| `events.payload.fights[i]` (VOYAGE_REPORT) | `log`, and `loss {crew_before, crew, cargo, ransom}` read from the day | About 0.7 kB |

- **Human fleets only (default).** `voyage.raid_opts` answers `{}` for an NPC company, so the skin builds nothing and an NPC day is the payload it was.
- **WAL:** about 1.5 kB a human raid with row overhead. The human rate is not measured. At one an hour it is about 36 kB a day.
- **Why not every fleet:** all fleets fought 6 raids an hour in October and 48 an hour in 0192's lit window. At 48 that is about 0.7 MB a day that nobody reads.
- **Ledger read:** ten raid reports among the last 50 events add about 7 kB to a `world.ledger` answer. The client asks again only when its signature moves.
- `scripts/ops/harness/combat-log/raids-rate.sql` measures the real rate and payload size before the PR.

### 1.3 Who writes it

| Function | Change |
|---|---|
| `voyage.raid_report(voyage, day, raider, escort, ships, opts)` | **New.** The skin's body, moved (see 5.1). Builds `log` when `opts.log` is true |
| `voyage.fight_resolve` (5 arguments) | Becomes `return voyage.raid_report(..., '{}'::jsonb);`. Same name, same answer, word for word |
| `voyage.raid_opts(voyage, day, fleet)` | **New, STABLE.** `{}` for an NPC; `{log: true}` plus the order for a human |
| `voyage.fight` | One hunk: calls `raid_report` with `raid_opts` |
| `voyage.settle` | One hunk, in the report: a fight's entry gains `log` and `loss` when the day has a log |
| `public.fight_sides` | **Not touched by C1** |

### 1.4 Old events

`payloadFights` returns `{line, rounds, log?, loss?}`. `log` is parsed strictly: version 1, every array the right length, or null. With a log the component draws numbers; with none it draws `rounds` in today's `<ol data-testid="battle-report">`, unchanged. A BATTLE_REPORT has no log until C3 and takes the same fallback. The English `rounds` stay in every new payload, so a cached old bundle keeps working.

### 1.5 The layout

One list item a round. On a desktop it is one line; on a phone the same item wraps to two by a CSS grid (never by spaces: the font is not fixed-width). Bars are text cells with the percent always printed beside them, 10 cells wide on a desktop and 5 on a phone.

Desktop (1280):

```
Day 4. Sail sighted to windward. We ran, and got clear of them.
Raid · 2 Şebek · 81 crew                       Order Flee · They saw first
 #  Range   You            Them           Hull                     Foe hull
 1  Long    Run            1/2  −41       ▮▮▮▮▮▮▮▮▮▯  90%          ▮▮▮▮▮▮▮▮▮▮ 100%
 2  Long    Run            0/2            ▮▮▮▮▮▮▮▮▮▯  90%          ▮▮▮▮▮▮▮▮▮▮ 100%
 3  Long    Run  Slip 6%   2/2  −79       ▮▮▮▮▮▮▮▯▯▯  70%          ▮▮▮▮▮▮▮▮▮▮ 100%
Result  Fled, round 3
Lost    Hull −120 (30%) · Crew 0 · Cargo none
Gaivota  Hull 400 → 280
+2 Reputation
```

Phone (390; proved at 320 too):

```
Raid · 2 Şebek · 81 crew
Order Flee · They saw first
1 Long   You run · Them 1/2 −41
         ▮▮▮▮▯ 90%   Foe ▮▮▮▮▮ 100%
2 Long   You run · Them 0/2
         ▮▮▮▮▯ 90%   Foe ▮▮▮▮▮ 100%
3 Long   You run · Them 2/2 −79
         ▮▮▮▯▯ 70%   Foe ▮▮▮▮▮ 100%
Result   Fled, round 3
Lost     Hull −120 (30%) · Crew 0
```

- A cell reads `hits/shots −damage`. No guns, Out of range, Caught unready and Run replace it when true.
- A boarding is its own line before the result: `Boarding  8 crew against 81`.
- **History:** the log hangs under its day's line, where the sentences hang today.
- **Arrival card:** one line a raid (`Raid, day 4: Fled · Hull −30%`) and a **Log** button that unfolds the same component inside the card, scrolling within it. The card's 20 s timer stops while a log is open.

### 1.6 The words

One new dictionary, `src/lib/i18n/dict/fight.ts`.

| Key | EN | KO |
|---|---|---|
| raid | Raid | 습격 |
| order | Order | 명령 |
| orderFight / orderFlee / orderPay | Fight / Flee / Pay | 전투 / 도주 / 지불 |
| round | Round | 라운드 |
| rangeL / rangeM / rangeC | Long / Medium / Close | 원거리 / 중거리 / 근거리 |
| you / them / foe | You / Them / Foe | 아군 / 적 / 적 |
| hull / crew / cargo | Hull / Crew / Cargo | 선체 / 선원 / 화물 |
| noGuns | No guns | 포 없음 |
| outOfRange | Out of range | 사거리 밖 |
| unready | Caught unready | 기습당함 |
| run | Run | 도주 중 |
| slip | Slip {n}% | 이탈 {n}% |
| sawFirstYou / sawFirstThey / sawFirstBoth | You saw first / They saw first / Seen together | 먼저 발견 / 먼저 들킴 / 동시 발견 |
| boarding | Boarding | 백병전 |
| result | Result | 결과 |
| lost | Lost | 손실 |
| ransom | Ransom | 몸값 |
| log | Log | 기록 |
| end_STOOD | Stood off | 대치 |
| end_SLIP | Slipped away | 따돌림 |
| end_BROKE | Drove off | 격퇴 |
| end_THREW | Threw back | 격퇴 |
| end_TERMS | Paid off | 몸값 지불 |
| end_TAKEN | Plundered | 약탈당함 |
| end_GAVE | Surrendered | 항복 |
| end_FLED | Fled | 도주 성공 |
| end_PAID | Paid | 지불함 |
| oddsFoe | Raiders | 해적 |
| oddsSlip_poor / fair / good | Poor / Fair / Good | 낮음 / 보통 / 높음 |

`map.attackWord_*` (Weaker, About even, Stronger, Far stronger) are reused for the raiders' word. Refusal words go in `codes.ts`.

## 2. C2: a standing order per fleet

### 2.1 Storage and doors

```
public.fleet_raid_orders (
  fleet_id   uuid primary key references public.fleets(id) on delete cascade,
  raid_order text not null check (raid_order in ('FLEE', 'PAY')),
  set_at     timestamptz not null default now())
```

- **No row is Fight.** A player who never chooses has none. A merchant never has one. RLS on, no client grant.
- A side table, not a column on `fleets`: no lock on a hot table, and `world.fleets()` is not cut.
- **`cmd.raid_order(p_fleet uuid, p_order text)`** answers `{ok, order}` or the refusal envelope. FIGHT deletes the row. Refusals: `E_NO_HOUSE`, `E_NO_SUCH_FLEET`, `E_BAD_ORDER`, `E_NOT_IN_USE` (dark).
- **`world.raid_read(p_fleet uuid)`**, STABLE: `{order, guns, slip, pay, foes[{danger, word}]}` (section 6.2).
- **When it may change:** any time, in any state. It takes hold at the next departure. A turn at sea is a departure, so the water ahead takes the new order and the water behind keeps the old.
- Switch `raid_orders_enabled`, false at deploy.

### 2.2 Frozen at departure

`voyage.freeze_order(p_segments jsonb, p_fleet uuid)`, STABLE: with the switch off or no row it answers `p_segments` unchanged, byte for byte; else each segment gains `order`.

`voyage.depart`, one hunk on 0339's line:

```
old:  values (p_fleet, v_player, voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), v_total, ...
new:  values (p_fleet, v_player, voyage.freeze_order(voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), p_fleet), v_total, ...
```

`voyage.leg_order(p_leg jsonb)` is the one reading: `p_leg->>'order'`, or null with the switch off, so one knob write ignores every frozen order at once. Cost: one primary-key probe of a near-empty table per departure.

### 2.3 The engine: six hunks on `public.fight_sides`

Live body is 0320's create with no later hunk. `public.fight_volley` is **not** touched: a running side is silenced through its existing `p_unready` argument. Two new knobs, `fight_flee_base` 0.15 and `fight_flee_floor` 0.05; `fight_evade_per_sighting` 0.03 and `fight_evade_max` 0.30 are reused.

New options, each absent by default:
- `a_order`: a word for every round, or a list with one word a round whose last word stands for the rest.
- `rounds`: fight no further than this round, at least 1, and say the fight is still open. C3 uses it; it is cut here so the engine is re-cut once.

**E1, declarations.** Old: `  v_ratio  numeric;` then `begin`. New adds:

```
  v_ord    jsonb := p_opts->'a_order';
  v_ao     text;
  v_cap    int := coalesce((p_opts->>'rounds')::int, 1000000);
  v_fled   boolean := false;
  v_paid   boolean := false;
  v_open   boolean := false;
  v_pf     numeric;
```

**E2, the loop's head.** Old: the `for g in 1 .. jsonb_array_length(v_ranges) loop` line and `v_fought := g;`. New, between them:

```
    v_ao := case jsonb_typeof(v_ord) when 'string' then v_ord #>> '{}'
                                     when 'array' then coalesce(v_ord ->> (g - 1), v_ord ->> -1) end;
    if g > v_cap or v_ao = 'PAY' then
      if g = 1 then v_la := v_h0a; v_lb := v_h0b; end if;
      if g > v_cap then v_open := true; else v_paid := true; v_outcome := 'RANSOM'; end if;
      exit;
    end if;
```

**E3, her volley.** In the `'you'` call, `g = 1 and v_first = 'B'` becomes `(g = 1 and v_first = 'B') or coalesce(v_ao = 'FLEE', false)`.

**E4, the slip roll.** After the break-off test's `end if;`, before `end loop;`:

```
    if v_ao = 'FLEE' then
      v_pf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')));
      v_rows := jsonb_set(v_rows, array[(g - 1)::text, 'flee'], to_jsonb(round(v_pf, 4)));
      if voyage.rng(p_seed, p_round, format('fight:%s:flee', g)) < v_pf then
        v_fled := true; v_outcome := 'EVADED'; exit;
      end if;
    end if;
```

**E5, the boarding.** `if v_outcome is null then` becomes `if v_outcome is null and not v_open then`.

**E6, the answer.** The last `jsonb_build_object(...)` gains `|| case when v_fled then '{"fled": true}'::jsonb else '{}'::jsonb end`, and the same for `paid` and `open`.

**What the three orders do:**

| Order | Rule |
|---|---|
| Fight | Today. No option is passed |
| Flee | Each round her guns are silent. Their fire lands by today's rule (a side out-ranged at long range still cannot fire). If they have not broken off, she rolls: base 0.15 plus 0.03 a point of sighting lead, never under 0.05 or over 0.30. Away is EVADED with `fled`. Never away in six rounds: boarded, at their strength as it stands |
| Pay | After sizing-up and the first-sight slip (a raid that stands off, or that she slips, costs nothing): RANSOM with `paid`, no shot, no hull, no hands |

**Outcome codes do not grow (default).** A flight is EVADED with a flag. Every reader of the five outcomes is unchanged, and `fight_points` pays it as it pays a slip today. Reputation reads the log's `end` instead (6.3). The other way is a sixth code, FLED, with no experience; it needs no hunk either, since every reader falls to its zero branch.

**A running side fires nothing (default).** It is what makes Flee a cost for a gunned fleet.

### 2.4 Pay: the price, the payee, the refusals

- **Price:** `public.ransom_take(public.fleet_stock_at_cost(fleet))`, 8 % of the cargo at cost. `ransom_take` stays the one reader of `ransom_share`.
- **Payee:** new `public.raid_ransom(p_pirate uuid, p_company uuid, p_basis bigint)`. A named raider: `public.pirate_ransom`, as today. An anonymous raid: `public.pay_city` to `public.pirate_capital()`, kind RANSOM, moved, under the same two guards (purses lit, hoard under `pirate_hoard_cap`).
- **Refused, and she fights:** nothing aboard (price 0), or no payee (no pirate capital, or purses dark). `voyage.raid_opts` decides this before the fight and passes Fight with `pay_refused`, so the log can say why.
- **A purse that cannot pay pays what it holds (default).** This is `pirate_ransom`'s own rule. The outcome never depends on the purse, only the sum does, so a raid settled late ends the same way. The stricter rule is in section 7, R3.
- **Not insured.** She chose to pay. Insurance pays plunder, as today.
- `voyage.settle`: where 0339 pays a named raider on RANSOM, a branch comes first: `if coalesce((v_fight->>'paid')::boolean, false) then v_ransom := public.raid_ransom(v_pirate, f.player_id, public.fleet_stock_at_cost(p_fleet));`. The payload gains `ransom_paid` on such a day only.
- **This breaks one sentence of 0339**: "dark, no RANSOM moves". A player's Pay moves RANSOM with `pirates_bite` dark. Proofs 30 and 46 are read for that assertion and amended if they hold it.

### 2.5 Is the choice real? Arithmetic from the seed knobs

Raiders are xebecs: hull 530, crew 35, attack 60, accuracy 38, reach 26, armour 12, sighting 11, tier 2; one is strength 12.7.
- A xebec shot hits 22.8 % at long range, 30.4 % at medium, 38 % at close: 1.67 hits a shot over six rounds.
- A hit is 42 raw (31.5 to 52.5), less armour at `armour_turns_pct` 0.5.
- Plunder takes 25-50 % of every good, 37.5 % on average.

**A weak trader:** one barca, hull 400, crew 8, no guns, armour 5, sighting 8, cargo 30,000 d. at cost, against one xebec.

| Order | What happens | Expected cost |
|---|---|---|
| Fight | She cannot fire. About 1.67 hits of 41 take 17 % of her hull. Boarding: (8 × 0.15 + 3) × 0.83 = 3.5 against 11.25, ratio 0.31, PLUNDERED | Cargo 11,250, hull 17 % |
| Flee | Lead −3, so 0.15 − 0.09 = 0.06 a round; away within six rounds 31 %; caught 69 %, boarded as above | Cargo 7,760, hull about the same or less |
| Flee with a lookout (sighting 20) | Lead +9, capped at 0.30 a round; away 88 %, under fire about 2.9 rounds | Cargo 1,350, hull about 7 % |
| Pay | 8 % of 30,000 | 2,400 d., nothing else |

**For an unarmed hull Flee is never worse than Fight.** Pay beats Flee without a lookout; a lookout turns that round. Insured (she keeps 10 %), Flee's expected loss is about 776 d. and beats Pay.

**A gunned fleet:** one nau, hull 1,800, crew 60, attack 120, accuracy 55, reach 70, armour 30, sighting 14, cargo 200,000 d.

| Raid | Order | What happens |
|---|---|---|
| One xebec | Fight | She out-ranges them: three long rounds only she fires, 33 % a round, a hit about 79 against a break at 79.5. They break in about 86 % of fights; otherwise boarding at 18 against 11.25 at most, ratio 1.6, thrown back. **She wins every time.** Cost: at most 1 hand and 2-4 % hull |
| One xebec | Flee | Throws the win away. Caught, she throws them back anyway |
| One xebec | Pay | 16,000 d. for nothing |
| Five xebecs (63.5) | Fight | Her 2.4 expected hits take 7 % of their 2,650; no break. They take about 10 % of her hull. Boarding 16.2 against 52, ratio 0.31, PLUNDERED: cargo 75,000, 6 hands |
| Five xebecs | Flee | 0.24 a round. The three long rounds cost her nothing (they are out-ranged): away untouched 56 %, away by round six 81 %. Caught 19 %: expected cargo loss 14,250 |
| Five xebecs | Pay | 16,000 d., certain |

So guns make Fight right against a small raid and wrong against a large one. Flee and Pay sit within 2,000 d. of each other against the large raid, and insurance or a lookout decides. **There is no single best answer, and the danger she sails into is the input**, which is the pre-fight read of 6.2.

### 2.6 The defaults

| Who | Order | Why |
|---|---|---|
| A player who never chooses | Fight (no row) | Byte for byte today |
| A merchant, cargo, navy or pirate ship | Fight (never a row; `raid_opts` answers `{}`) | NPC raids byte for byte, asserted |
| A new player's unarmed barca | Fight, with the Send tray's read saying Raiders: Far stronger | A default of Flee for a gunless fleet is better play but changes live results unasked. Open point O2 |

## 3. C3: live rounds for the timed battle

### 3.1 The round clock

**Chosen: re-run from a frozen sheet to round N. No start state.**

- At `battle_open` the two sides' hulls are written once to `battles.sheet {a, b}`. 0334 froze a navy ship's sheet for the same reason. It also removes the per-hull reads (about 2.5 ms a hull) from every later round.
- Round g is due at `started_at + g × round_seconds`. The stance of a side for round g is her latest stance row with `set_at` at or before that instant; none means her opening stance.
- `public.battle_advance(battle, now)` locks the battle and, for each due round not yet logged, calls `fight_sides(battle id, 1, sheet.a, sheet.b, {a_order: [...], b_order: [...], rounds: g})`, inserts row g of the answer, and closes the battle when the answer is not `open`.

**Determinism:**
1. Every draw is `voyage.rng(seed, round, 'fight:<g>:...')`, a keyed hash. Round g's draws do not depend on how many rounds are run.
2. Round g's inputs are the hulls after round g − 1. By induction these are a function of the sheet and the stances of rounds 1 to g − 1, all stored.
3. `rounds` only leaves the loop early. So a run to N is the first N rows of a run to N + 1, as text.
4. So the log written round by round, a late catch-up in one call and a full re-run agree. A minute job that runs late writes the same rounds, because stances are read by their due instant, not by `now()`.

The self-assert proves point 3 on 200 crafted fights for N = 1 to 7. The proof plays one battle three ways (tick by tick, one late call, with and without a stance change) and compares rows.

**Cost:** a six-round battle costs 21 round computations instead of 6. At 0.44 ms a whole fight on PGlite that is nothing.

### 3.2 Tables and bodies

| Thing | Kind |
|---|---|
| `battles.sheet jsonb`, `round_seconds int`, `rounds_done int default 0`, `next_round_at timestamptz` | New columns. The table has 0 rows on prod |
| `public.battle_rounds (battle_id, g, at, row jsonb, primary key (battle_id, g))` | New: the growing log, one row a round in C1's `r` shape |
| `public.battle_stances (battle_id, fleet_id, set_at, stance, primary key (battle_id, fleet_id, set_at))` | New, append-only |
| `public.battle_advance(uuid, timestamptz)` | New |
| `cmd.battle_stance(p_battle uuid, p_stance text)`, `world.battle(p_battle uuid)` | New doors |
| `public.tick_battles` (0323, never cut) | Hunk: selects `next_round_at <= now` and calls `battle_advance`. Still one read of a partial index, still LIMIT 50 |
| `public.battle_open` (0323; hunks 0327 ×1, 0333 ×2) | Hunk: writes the sheet, the clock and each side's opening stance |
| `public.battle_resolve` (0323; hunks 0327 ×3, 0333 ×3, 0340 ×1) | Hunk: the fight is the last advance's answer. With no sheet and no stance it is today's one call |
| `public.battle_words` (0323, never cut) | Hunk: the report carries the log |
| `public.fight_sides` | Second re-cut: `b_order` (the side that closes may run) and a hull's `from` (the first round a called ship is on the sheet). Absent: byte-identical, same parity |
| `voyage.hold` (0323, never cut), `voyage.total_days`, `voyage.days_complete` | Section 3.5 |

### 3.3 The stance door

`cmd.battle_stance` runs `battle_advance` first (an act must not reason about a stale round), then writes a stance row at `now()`, and answers `{ok, round_next, next_at}`. The new stance applies from the next round.

Refusals: `E_NO_BATTLE`, `E_NOT_YOUR_BATTLE`, `E_BATTLE_OVER`, `E_BAD_STANCE`, `E_NOT_IN_USE`.

| Stance | She attacked (side b) | She was set upon (side a; C4 or a navy hunt) |
|---|---|---|
| Fight | Keeps closing, round after round, to the boarding | Today |
| Flee | **Break off.** From the next round her guns are silent, she takes that round's fire, then rolls by the same rule with the lead turned round. Away: status BROKEN_OFF (its first writer), no loot, the beaten row of `attack_crew_lost`, regard stands | Section 2.3 |
| Pay | Not offered: she started it | RANSOM before the next round |

This differs from WORLD_POWERS 5.2, which lets the attacker leave for certain after one round's fire. The owner's words are "it tries to flee". **Default: a roll, one rule for both sides.** One knob floor at 1.0 gives 5.2's rule back.

### 3.4 What the client reads

- No realtime exists in the client. **Poll `world.battle(id)` every 5 s while a battle card is open, and never otherwise.** It is a primary-key read of at most 8 short rows.
- `world.battle` is STABLE: it reads rounds and does not advance. The minute job and the stance door advance.
- If rounds run faster than a minute, a watching client needs a volatile `cmd.battle_look` that advances and reads. Not needed at 60 s.
- The fleet card keeps "In battle 7:24" from `busy_until`. The battle card shows the log, a countdown to the next round, and two buttons.

**An offline player:** the job advances every round. Her stance is her last one. As a defender her opening stance is her fleet's standing order (C2), so the offline case is C2 by construction.

### 3.5 The clock, and a hold that burns nothing

- **Length (default): `battle_seconds` stays 600**, the owner's figure for a navy's answer, with `round_seconds = battle_seconds / (rounds + 1)`, about 86 s.
- **Recommended to the owner: 420 s.** That is one round a minute, in step with the minute job, so an offline battle and a watched one keep the same clock.
- **Today's cost:** `voyage.hold` writes the hold as delay hours, `voyage.total_days` counts them, and a 600 s hold at compression 960 adds about 7 days of stores, wages and hazard rolls. 0323 recorded this as a default. It is wrong for a battle: she stood still for ten minutes.
- **The fix:**
  - `voyage.hold` writes `free: true` on its row.
  - A new leaf `voyage.hold_free_hours(voyage)` sums the free holds.
  - `voyage.total_days` and the cap in `voyage.days_complete` subtract it, never below 0.
  - `voyage.recompute_eta` and `voyage.delay_before_day` are not touched: the day she was held on is longer by the hold, the arrival moves by the hold, and the count of days is the count of a voyage never held.
- **Proof:** a held voyage and its unheld twin settle the same days, the same stores, the same wages and the same rolls, and the arrival differs by exactly the hold.
- **Cost:** one more index probe of an empty range per call on the position path. 0323 measured its own probe at about 5 µs.
- **Risk:** a fair wind may make up a hold's hours today. With free holds that sum must be clamped. The proof holds a fair-wind day after a hold.

### 3.6 What lighting `attack_enabled` exposes

One switch opens all of this:

| Door or effect | Behind it | Its own switch |
|---|---|---|
| `cmd.attack`, `cmd.preview_attack` | Cargo ships, navy ships, pirate ships. A human target is refused (`E_HUMAN_TARGET`) | None |
| The Attack button on the cargo, navy and pirate cards | `card.attack` | None |
| `public.battle_open` | Both fleets stop: a hold at sea, IN_BATTLE in port or at anchor. Orders queue; `cmd.divert` refuses; a standing route reads blocked | None |
| `public.navy_call`, escorts | A country's ship sails to the battle | `navy_enabled` |
| `public.attack_close` | LOOT moved under the three caps; crew loss both sides | None |
| Regard | −150 cargo, −250 navy, pirate knob | `regard_enabled` |
| WANTED rows | Written at the close. The hunt needs `navy_hunt_per_day` above 0 | That knob |
| A sunk NPC ship | Home as a wreck, or sails on at hull 0 | `npc_refits_enabled` |
| The battles job | Real work each minute | None |
| BATTLE_REPORT events | A human attacker's ledger | None |

**Known and unsolved:** an unarmed cargo ship loses at least 92 % of fights and never fires (0327's sim). Lighting attacks before `convoy_armed_enabled` is free gold, 240,000 d. a company a day.

**The after-check for that light (30 minutes, read-only):**
- battles opened and closed, none FIGHTING past its clock plus 2 minutes;
- every battle's `battle_rounds` equal to a re-run of its sheet;
- LOOT in the ledger equal to the sum of the reports' loot, and no company over `loot_per_company_day`;
- no fleet IN_BATTLE or with a `busy_until` after its battle closed;
- no failed run of the battles job;
- the arrivals beat (avg ≤ 3 s, p95 < 5 s);
- a held voyage's settled day count equal to its unheld count.

**Rollback:** `attack_enabled` false; running battles finish.

## 4. C4: a raid on an online player as a live battle

**Recommendation: no-go as written. Build C4-lite.**

**What the plan's C4 needs:**
- When a PIRATES day settles for a human, `voyage.settle` must stop mid-loop: write no row for the day, open a battle, hold the voyage, and return.
- The battle's close must then do everything the PIRATES arm does: crew, cargo, insurance, stow, ransom, loot book, payload, the wreck check. So that arm must be lifted into one function both callers share.
- That arm is the most-cut text in the chain (0027, 0168, 0189, 0202, 0213, 0276, 0279, 0330, 0339) and it runs inside the arrivals beat, whose bound broke once already when the fight was lit (3.18 s against 3 s).

**Does law D.2 survive?** Only in a weaker form. The rolls stay the same if the battle keeps the raid's seed (voyage, day) and streams: a live battle she never touches ends exactly as the instant one under her standing order. But whether it is live depends on who called settle and when, and her arrival moves by the battle. The law becomes "the same recorded choices settle the same", no longer "a pure function of time".

**The least-bad rule, if the owner wants it anyway:**
- live only when the settle that meets the day is her own session's and runs within `raid_live_seconds` (30) of the day's instant;
- every other settle (the arrivals job, a late read) resolves it as today under her order;
- kind RAID, a 90 s clock (six rounds of 12 s and a boarding), a free hold, opening stance her standing order;
- one battle a voyage at most.

**Risks:**
- a suspend branch in the hot arm;
- a voyage that waits on the battles job (today nothing at sea waits on it);
- two code paths to one outcome that must stay word for word;
- held arrivals moving standing-route laps;
- a rare payoff: a player must be looking in the 30 seconds of a day that falls about once in 30-60.

**C4-lite (go, after C1 and C2):**
- When a PIRATES day settles for a human, the server tells it then, as one new event kind RAID with the same `log`.
- A raid card (the arrival card's twin) plays the log a line at a time.
- Her agency is the order she set before sailing, with the read of the water (6.2).
- One hunk in the arm, one `emit_event`, no hold, no suspend. D.2 holds in full: the event's time is the only thing that depends on when the day settled.
- If reads do not settle a sailing fleet, the card simply appears at arrival.
- Cost: the same fight is in History twice (the raid, and the voyage's report). The report's copy can drop its log once the RAID event exists.

## 5. Per slice: migration, proofs, checks, cost, rollback, client

### 5.1 C1 + C2, one migration

Number: prod head + 1 when cut. The plan says 0353, after T5 (0351) and R1 (0352). R1 may cut `voyage.settle` and `client_rpc_entry_points` first: cut against prod's bodies after it.

| Function | Create or hunk | History of the live body |
|---|---|---|
| `public.fight_sides` | **6 hunks** (2.3) | 0320 create. No hunk since |
| `public.fight_volley` | Not touched | 0320 |
| `voyage.raid_report` (6 arguments) | **Create**, from `fight_resolve`'s live text by hunks: the head, `opts` into the engine's options, the log, the words of Flee and Pay | New |
| `voyage.fight_resolve` (5 arguments) | **Replaced whole** by the one-line wrapper (as 0320 replaced it: proved by answers, not hunks) | 0189; 0202, 0204, 0213, 0276; whole 0320; 0323 ×2 |
| `voyage.fight_round_line` | **1 hunk**: a round with `flee` says "you run before them", not "your guns cannot reach them" | 0323 create. No hunk since |
| `voyage.fight` | **1 hunk**, on 0323's line | 0189; 0198, 0276, 0323 |
| `voyage.raid_opts`, `voyage.freeze_order`, `voyage.leg_order`, `public.raid_orders_on`, `public.raid_ransom` | **Create** | New |
| `cmd.raid_order`, `world.raid_read` | **Create**, granted to `authenticated` only | New |
| `voyage.depart` | **1 hunk**, on 0339's line | 0047 create; hunks 0330, 0334 ×2, 0339 |
| `voyage.settle` | **3 hunks**: the report's fight entry (0189 hunk 6); the paid branch (before 0339 hunk 3's text); `ransom_paid` (after 0339 hunk 5's text) | 0027 whole; latest cuts 0314, 0322, 0330, 0334, 0339 |
| `public.client_rpc_entry_points` | **1 hunk**: two doors | Latest cuts 0346, 0347, 0348 |
| `public.fleet_raid_orders`; knobs `raid_orders_enabled`, `fight_flee_base`, `fight_flee_floor` | New. No existing key is written | |

Why the wrapper: adding a defaulted argument makes a second function and leaves 5-argument calls ambiguous. Dropping the old one breaks proof 28 and `golden.sql`, which name it. The wrapper keeps both working unedited, and with empty options it is the parity proof itself.

All hunk strings are LF. Bodies are read through `replace(pg_get_functiondef(...), E'\r', '')`. Each hunk occurs once and reverses to its pre-image.

**Self-assert:** one DO block, `statement_timeout` 45 s, `lock_timeout` 5 s, pure fights and the catalog only. It runs no game step and writes no row.
1. **Guard:** not applied before; each hunk's pre-image occurs once.
2. **Engine parity.** A `pg_temp` copy of the live `fight_sides` against the new one, as text, on 0320's matrix: Carlat and Barca × raiders 6, 12, 18, 24 × 120 days; the convoy of three × 10, 24, 60, 120 × 30 days; three against two real hulls × 40 days. Fought three ways: no options, `{a_score, b_score}`, and with `a_order: 'FIGHT'` added. All equal, and all four endings met.
3. **Skin parity.** A `pg_temp` copy of the live `fight_resolve` against the wrapper and against `raid_report(..., '{}')`: 1,080 fights and the two empty seas, as text.
4. **Prefix.** For N = 1 to 7, a run with `rounds: N` is the first N rows of the full run; `open` is set exactly when the full run went further.
5. **Flee.** Every round's `a.fired` is 0; every row's `flee` is the knob formula; `hull_lost.b` is empty; over the matrix at least one fight ends `fled` and one is boarded.
6. **Pay.** A day that stood off or slipped is unchanged; every other day is RANSOM, `paid`, 0 rounds, no hull lost on either side.
7. **Guards.**
   - 0320's no-table test on the new engine body, same allow-list.
   - The new skin and round line read no table.
   - Raiders are still built in one place.
   - New functions are not client-executable except the two doors, each in the registry once.
   - ACL, volatility, definer and config of every hunked function unmoved.
   - No other function and no existing knob moved.
   - 0 rows in `fleet_raid_orders`.
   - `freeze_order` answers its input for any fleet.
   - `raid_opts` is `{}` for an NPC fleet.
8. **Budget:** about 8,000 pure fights. Fails above 40 s.

**Proof (CI), `scripts/db/proofs/NN_combat_log.sql`, next free number:**

| Marker | Proves |
|---|---|
| `LOG_NPC_PARITY` | A merchant's forced raid passage, old bodies against new: every day's payload and the report, byte for byte |
| `LOG_HUMAN` | A human's raid has `fight.log`; `after` equals her ships' hull; rounds equal `rounds_fought`; the report's entry carries the same log and the day's losses; the English `rounds` are word for word the old body's |
| `LOG_LATE` | Settled day by day and settled once at the eta: identical, for each order |
| `ORDER_FROZEN` | Flee, depart, Pay at sea: the raid runs Flee; the next voyage Pay; a turn freezes again |
| `ORDER_FLEE`, `ORDER_PAY` | Each ending through the real `voyage.settle`. Paid: her purse down, the payee up, the sum unchanged, kind RANSOM, no hull, no hands, no insurance claim |
| `ORDER_PAY_REFUSED` | An empty hold, and no payee: she fights, and the log says why |
| `ORDER_DARK` | Switch off: the door refuses, segments unchanged, a frozen order ignored |
| `ORDER_DOOR` | Each refusal; another player's fleet; anon cannot execute |

Proof 28 runs unedited. Mutation controls: `scripts/ops/harness/combat-log/proof-NNNN.mjs`, each mutation red for its own reason.

**Specs:**
- `tests/fight.log.spec.ts`: the parser with and without a log, each `end` word EN and KO, bar rounding, a wrong version falls back.
- `tests/ledger.fights.spec.ts`, extended: an old event draws as before.
- `tests/arrival.card.spec.ts`, extended: the raid line and the fold.
- `tests/rpc.raid-order.spec.ts`: the seam; the control hidden while dark.
- One Playwright spec at 320, 390 and 1280: no sideways scroll.

**PROD CHECKS** (`scripts/ops/harness/combat-log/`, one pure SELECT a file):

| File | Reads |
|---|---|
| `switches.sql` | `combat_bite`, `armour_turns_pct`, `pirates_bite`, `attack_enabled`, `navy_enabled`, every `fight_*`, `ransom_share`, `time_compression` |
| `before.sql` | For each hunk `[function, ord, occurrences]` (must be 1), and each body's md5 |
| `../two-sides/golden.sql` | The 1,080-fight digest, before. After the deploy it must be the same text |
| `raids-rate.sql` | PIRATES days in 24 h by human and NPC; mean `pg_column_size(payload)` |
| `payee.sql` | `pirate_capital()` not null, purses lit, hoard under the cap (check each is `provolatile` 's' first) |
| `after.sql` | Bodies at the wanted hashes, switch false, 0 order rows, two doors registered once |
| `after-lit.sql` | Human raid days with and without a log; orders by kind; RANSOM in the ledger equal to the sum of `ransom_paid` |

**Cost against the arrivals bound (avg ≤ 3 s, p95 < 5 s):**
- Per NPC raid: one more `leg_at_day`, two primary-key reads and one function call, well under 0.1 ms, against about 2.5 ms a hull today.
- Per human raid: the log's assembly, about 0.1 ms on PGlite.
- Per departure: one primary-key probe.
- At 6 to 48 raids an hour nothing should show.
- Measured with `proof-NNNN.mjs --cost` on the cached world (1,000 fights old and new), and on prod by `scripts/ops/harness/raid/after-check.sh` over the 30 minutes before and after.

**The 30-minute after-checks:**
- *The deploy* (the log is live at once, display only): `after-check.sh <start> <end>`, `after.sql`, `golden.sql`. Pass: bounds hold, digest unchanged, every human raid day has a log, no NPC day has one.
- *Lighting `raid_orders_enabled`* (its own step, reported the same hour): `after-check.sh` and `after-lit.sql`.
  - The paired raid bounds compare each raid with the dark table. `after-check.sh` needs one filter so a raid fought under Flee or Pay is left out of that pairing.

**Forward rollback:**
- *Orders:* a new migration sets `raid_orders_enabled` false. `leg_order` then answers null, so every frozen order is ignored at once and the door refuses. Rows and logs stay.
- *The whole slice:* a new migration swaps this file's old and new, puts `fight_resolve`'s body back from the kept pre-image, and drops what it created. Old logs stay readable.

**Client:**

| File | Change |
|---|---|
| `src/lib/rpc/types.ts` | `FightLog`, `FightLoss`, `RaidRead` |
| `src/features/ledger/headline.ts` | `payloadFights` returns `log` and `loss`; a strict parser |
| `src/live/fightLines.ts` (new) | Pure: a log into rows, words and bar cells |
| `src/live/FightLog.tsx` (new) | The one component, `dense` for the card |
| `src/features/ledger/LedgerScreen.tsx` | The log, or the old list |
| `src/app/ArrivalCard.tsx` | An arrival's raids from the report; the line, the Log fold, the timer held while open |
| `src/live/RaidOrder.tsx` (new) | Fight / Flee / Pay as a `Segmented`, with the read's three rows |
| `src/features/map/SendFleet*.tsx`, `src/features/fleets/FleetFold.tsx` | The two mounts of `RaidOrder` |
| `src/lib/rpc/catalog.ts`, `index.ts` | `cmdRaidOrder`, `worldRaidRead` |
| `src/lib/i18n/dict/fight.ts` (new), `index.ts`, `codes.ts` | The words of 1.6; `E_BAD_ORDER` |

### 5.2 C3, one migration, dark

- **Functions:** section 3.2.
- **Self-assert:** engine parity again (the same matrix, `b_order` and `from` absent); the prefix property with both stance lists; hunks once and reversing; `attack_on()` false; 0 battles; no game step.
- **Proof:** a battle played tick by tick, by one late call, and with a stance change at round 3, with rows equal where they must be. Also: break off writes BROKEN_OFF and takes no loot; a called ship fights only from her `from` round; the free hold's twin voyage; the job closes once under a retry; proofs 31 and 34 green on the new bodies.
- **Specs:** the battle card's clock, log and buttons; the stance seam.
- **PROD CHECKS:** each hunk once; 0 battles; no hold row; the bodies' md5; `attack_enabled` false.
- **Cost:** none while dark but one index probe on the day count. Lit: a handful of battles a day, 19 at once at worst (WORLD_POWERS 5.4).
- **After-check:** none owed at deploy. The one in 3.6 when the switch is lit.
- **Rollback:** the switch; then the file reversed.
- **Client:** `src/live/BattleCard.tsx` (the same `FightLog`, a countdown, two buttons, a 5 s poll while open), mounted from the fleet card's "In battle" line and from `AttackSection` after the press.

### 5.3 C4-lite, one small migration

- **Functions:** `voyage.settle`, one hunk after the PIRATES arm's payload: for a human fleet with a log, `public.emit_event(player, 'RAID', {fleet, day, line, log, loss})`.
- **Proof:** an NPC emits nothing; settled late equals on time but for the event's instant; one event a raid day under a re-settle.
- **Cost:** one insert a human raid.
- **After-check:** the fight's, 30 minutes.
- **Rollback:** the hunk reversed.
- **Client:** `src/app/RaidCard.tsx` on fresh RAID events, as `ArrivalCard` reads fresh VOYAGE_REPORTs; a `headline.ts` line.

## 6. What makes it engaging, in text

### 6.1 Pacing and what is revealed when

- **On a card** (arrival, raid, battle) lines appear one at a time: the foe line, who saw whom, each round at 600 ms, a longer beat before the result, then the losses, then the reward. With reduced motion, all at once.
- **In History** the whole log stands at once: it is a record.
- **A live battle** paces itself by the round clock. Between rounds the card shows the next round's range and a countdown: the moment the choice is made.
- **The bars move both ways.** The foe's bar nearing 85 % says they are about to break. Her own bar falling says run. This is why the hull left is on every line.
- **Reasons are printed, not numbers.** No guns, Out of range, Caught unready. A player learns why she lost: buy guns, seat a Gunner, carry a lookout.
- **The slip chance is shown after the roll**, in the log (`Slip 6%`). Before the fight it is a word.

### 6.2 The pre-fight read

`world.raid_read(fleet)`, shown in the Send tray under the picked fleet, beside insurance, where the order is chosen:

| Row | Value | From |
|---|---|---|
| Raiders | Weaker / About even / Stronger / Far stronger | `public.attack_word(her escort score, danger × 40)` for the course's worst water (the mid roll) |
| Slip | Poor / Fair / Good | The flee formula with her best sighting against the raider class: under 0.10, under 0.20, above |
| Pay | 2,400 | `ransom_take` of her cargo now. "Nothing aboard" when 0 |
| No guns | Shown when no hull can fire | Her sheet |

It is a read of the sides and never a forecast. No day's roll is shown, as `cmd.preview_attack` shows none and as `WatersAhead` refuses to.

### 6.3 Rewards (C5, rides R1)

Reputation by the log's `end`, humans only, under R1's daily cap. Figures belong to `docs/REPUTATION.md`; the shape is:

| End | Reputation | Ship and captain experience |
|---|---|---|
| Threw back, Drove off | Full | As today (`fight_points`) |
| Stood off, Slipped away | A third | As today |
| Fled | A third | As today (EVADED) |
| Paid, Paid off | None | None, as today |
| Plundered, Surrendered | None | None |
| An attack won (C3) | Full, plus the loot | Battle progress |

The log's last line says it: `+6 Reputation`.

### 6.4 What must not be added

- No board, grid, map of the fight, ship sprites, projectiles, portraits, or sound that carries information.
- No dice, and no percentages before the fight.
- No per-ship orders, targeting or formations: three orders for a fleet.
- No timer on a raid (C4-lite has none).
- No outcome computed in the client: it draws the server's numbers.
- No forecast of days ahead.
- No player against player, in any slice.

## 7. Risks and open points, each with a default

| # | Point | Default |
|---|---|---|
| R1 | `combat_bite` may be false on prod | Read it first. If false, ship C1 and C2 as built and report that nothing shows until the fight is lit; lighting it is its own step with `after-check.sh` |
| R2 | `voyage.settle`'s anchors come from hunk history, and R1 (0352) may cut it first | `before.sql` must print 1 for every hunk on prod's body before the PR. Cut after 0352 is live |
| R3 | Pay reads the purse when the day settles, which can differ between a watched voyage and a late one | The outcome never depends on the purse; a short purse pays what it holds. Stricter: owe the rest through `public.debt_owe` as a new kind |
| R4 | An empty purse makes Pay free | Accepted: the same holds for a named raider's ransom today. A floor price is one knob if it is abused |
| R5 | Pay moves RANSOM while `pirates_bite` is dark, against 0339's stated dark contract | Pay to the Brethren's capital; amend proofs 30 and 46 if they assert it. Otherwise: offer Pay only while the pirates are lit |
| R6 | A flight is EVADED and earns the experience of a slip | Keep five outcomes; Reputation distinguishes. Otherwise a sixth code, FLED |
| R7 | The flee knobs (0.15, 0.05) are reasoned, not measured | Run `sim.mjs` with each order on prod's recorded raids before lighting, and put the table in the dev-log |
| R8 | The engine is re-cut twice (C2, then C3) | Each re-cut carries the same parity matrix and the prod digest. `rounds` rides C2 so C3 adds only two options |
| R9 | The log's positional arrays are brittle | `v: 1`, and a strict parser that falls back to sentences |
| R10 | The free hold changes the day count on the position path | C3 only, dark. The twin-voyage proof and a measured probe cost, as 0323 did |
| R11 | Lighting attacks is free gold against unarmed cargo ships | Not lit before `convoy_armed_enabled`. The owner's |
| R12 | Navy meetings (0334, dark) ignore her order | Left as built. Flee, and Pay as the fine, can come when the hunt is lit |
| R13 | The arrival card hides after 20 s and a log needs longer | The timer stops while a log is open |
| O1 | Change the order at sea without turning? | No. Frozen at departure, as the plan says. Later it could be read as of the day's instant from an append-only table |
| O2 | A gunless fleet's default | Fight, for parity. Recommended to the owner: Flee when no hull can fire |
| O3 | A second choice when Pay is refused | She fights, which is today. Flee is arguably what a payer wants: one more column if asked |
| O4 | Battle length | 600 s stands. Recommended: 420 s, one round a minute |
| O5 | Break off: a roll, or certain as WORLD_POWERS 5.2 says | A roll, the owner's "tries to flee" |
| O6 | Logs for NPC raids | No. Yes costs about 0.7 MB a day at the busy rate |
| O7 | Should a running side fire stern guns? | No |

### Critical Files for Implementation

- C:\Users\gkwng\byeharu-voyage\supabase\migrations\20260818000320_a_fight_has_two_sides.sql (the engine, its guard, the parity matrix and the skin to move)
- C:\Users\gkwng\byeharu-voyage\supabase\migrations\20260818000339_pirate_ships_sail.sql (the latest hunks on `voyage.settle` and `voyage.depart`, `freeze_raiders`, `pirate_ransom`: the pre-images and patterns to follow)
- C:\Users\gkwng\byeharu-voyage\supabase\migrations\20260818000323_a_battle_takes_ten_minutes.sql (`voyage.fight`'s live line, `fight_round_line`, the hunk loop, battles and `voyage.hold` for C3)
- C:\Users\gkwng\byeharu-voyage\scripts\db\proofs\28_fight_sides.sql (holds the 5-argument skin by name and digest: the reason for the wrapper; with C:\Users\gkwng\byeharu-voyage\scripts\ops\harness\two-sides\golden.sql and C:\Users\gkwng\byeharu-voyage\scripts\ops\harness\raid\after-check.sh)
- C:\Users\gkwng\byeharu-voyage\src\features\ledger\headline.ts (`payloadFights`; with C:\Users\gkwng\byeharu-voyage\src\features\ledger\LedgerScreen.tsx and C:\Users\gkwng\byeharu-voyage\src\app\ArrivalCard.tsx, the two mounts)

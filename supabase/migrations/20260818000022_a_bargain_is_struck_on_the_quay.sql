-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0022 — A BARGAIN IS STRUCK ON THE QUAY
--        Haggling: a finite, deterministic, server-rolled negotiation that moves the PORT'S CUT
--        and never the world's price. The HAGGLING skill 0016 seeded finally has a rule.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ─────────────────────────────────────────────────────────────────────────
--   "yes add haggling mechanic"
--
-- ── WHERE IT ATTACHES, AND WHY THERE AND NOWHERE ELSE ───────────────────────────────────────────
-- DESIGN G.1 decomposes a price into a WORLD half and a PORT half:
--
--     ask = mid x (1 + tax + spread/2)          bid = mid x (1 - spread/2) x (1 - tax)
--
-- `mid` is what the thing is WORTH — affinity, stock, elasticity, drift (world.mid_price, 0005:315).
-- No negotiation may touch it: a haggle that moved the mid would mean two houses standing on the
-- same quay disagree about what a tun of pepper IS, and world.market()'s %NBR index, the price
-- history (0013) and world.trade_routes (0019) would each be reporting a different world.
--
-- `spread` is the PORT'S CUT. That is what a factor has the authority to shave, and it is already
-- the lever 0017 gave the PURSER (0017:66-77, "PURSER: world.quote(), NOT world.spread()"). So
-- haggling pulls the same lever, and this file does NOT add a second one.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
--   0016:41   "HAGGLING → spread   NOT READ YET. Attaches in world.quote (0005)."
--   0016:296  the seeded blurb: "Not yet read by any rule."
--   0016:259  world.skills() `v_read := array['ENDURANCE']`, and it serves `takes_effect` false
--             for HAGGLING to every client.
-- All three become false in this file, and all three are corrected here rather than left to rot —
-- a description that lies is how `fleet_ship_max` went unread for twenty migrations (0021).
--
-- ── THE ONE AUTHORITY THIS FILE CREATES, AND THE INLINE COPY IT RETIRES ─────────────────────────
-- 0017 computed "what spread does THIS house execute at" inline inside world.quote:
--
--     v_spread := world.spread(p_port) * (1 - v_purser);            -- 0017:376
--
-- Adding a haggle term beside it would have made that line the second thing to edit whenever a
-- rule changed. It becomes a named function instead:
--
--     world.spread_effective(port, good, fleet)   THE spread a trade executes at: the port's
--                                                 published spread, the purser, the open bargain,
--                                                 and the floor that stops them stacking past a
--                                                 half. world.quote() is now a CALLER.
--     world.spread(port)                          UNTOUCHED. Still the port's PUBLISHED spread,
--                                                 still takes no player, still what world.market()
--                                                 prints on the port card. Two different questions,
--                                                 two names, one answer each.
--
--   public.haggle_concession(player, port, good)  THE one reading of "what bargain is open here".
--   public.haggle_odds(player, port, good)        THE one reading of "what are the odds". Read by
--                                                 cmd.haggle AND by world.haggle_state, so the
--                                                 number shown and the number rolled against
--                                                 cannot differ.
--
-- ── WHAT THIS FILE SUPERSEDES, AND WHY IT MOVES THEM TOGETHER ──────────────────────────────────
-- It RE-CUTS five functions an earlier migration created. Naming them is not bookkeeping — README
-- §1 allows a deployed rule to change only in a NEW file that says what it replaces, and
-- `tests/duplication.spec.ts` fails a chain whose header does not:
--
--   world.quote           (0005, re-cut 0017)  — the spread it executes at now comes from
--                                                world.spread_effective(), so a bargain reaches it.
--   cmd.do_buy            (0007, re-cut 0017)  — spends the bargain it just used.
--   cmd.do_sell           (0007, re-cut 0017)  — the same, on the other side.
--   world.skills          (0016)               — HAGGLING stops reporting itself unread.
--   public.client_rpc_entry_points (0018)      — cmd.haggle and world.haggle_state are entry
--                                                points, and 0018's grant loop reads THIS list.
--
-- THEY MOVE IN ONE FILE ON PURPOSE. 0017:50-55 is the reason the rule exists: `do_buy` once
-- checked room with one function and placed cargo with another function's private copy of the same
-- arithmetic, and the day those drifted a player would have paid for tuns that never landed. A
-- bargain that `world.quote` honours but `do_buy` never spends is the identical defect — the
-- player would be quoted a discount and charged it for ever after, or never.
--
-- IT IS A NO-OP WITHOUT THE NEW INPUT. With no bargain held and no purser posted,
-- world.spread_effective(port, good, fleet) returns world.spread(port) exactly, and the assert
-- below proves it on 120 real quotes captured through the OLD code path before the replacement.
--
-- ── THE SEVEN DECISIONS, EACH WITH ITS REASON ───────────────────────────────────────────────────
--
-- 1. THE ROLL IS THE EXISTING RNG, COMPOSED — NOT A NEW ONE. `voyage.rng(subject, day, stream)`
--    (0006:127) is STABLE, wraps the IMMUTABLE `voyage.rng_raw` and supplies the world secret so
--    it never leaves the server. The draw is keyed
--        subject = player_id, day = world.game_day(), stream = 'haggle:<port>:<good>:<attempt>'
--    so it is a pure function of (player, port, good, game-day, attempt index, secret) and of
--    nothing else — in particular not of now(). No new RNG exists; forking one would have been a
--    second source of randomness in a chain whose whole offline-equivalence proof rests on there
--    being one.
--
-- 2. SAVE-SCUMMING IS STRUCTURALLY IMPOSSIBLE, NOT DISCOURAGED. `cmd.haggle` writes the attempt
--    row and increments `attempts` BEFORE it computes the outcome, and the attempt INDEX is what
--    the stream is keyed on. So a retry is a genuinely different draw that has already cost a
--    chance; there is no sequence of calls that re-rolls one draw. Asserted below by predicting
--    attempt k's outcome from voyage.rng independently and requiring the recorded outcome to
--    match, for every attempt in a day.
--
-- 3. FAILURE HARDENS THE ODDS, NOT THE PRICE. The reference game hardens the factor, and the
--    choice must be real or three attempts are just three free rolls. But hardening the PRICE
--    would mean the ask a player was shown by world.market() is not the ask he is charged — this
--    chain's oldest rule (0005:14, "the same function the committed trade walks") — because
--    market() is served without knowing who has haggled. So a failure multiplies the NEXT
--    attempt's odds by (1 - haggle_hardening_per_fail): 0.75 after one refusal, 0.50 after two.
--    The published price never moves, and the read tells the player his odds before he spends one.
--
-- 4. THE SKILL RAISES THE ODDS AND NOTHING ELSE. `public.player_skill_bonus(player,'SPREAD')`
--    (0016:97) is read ONCE, added to the base chance. It deliberately does NOT also raise the
--    concession step or the cap: 0016's own comment on `skills.effect` says "The ONE thing this
--    skill changes. Exactly one … a skill that moved several numbers would need several rules to
--    read it." Three terms from one skill would be three balancing stories and no way to tell
--    which one was wrong.
--
-- 5. THE PURSER AND THE BARGAIN COMPOSE MULTIPLICATIVELY, SO THEY CANNOT DOUBLE-COUNT.
--        executed = published x (1 - purser) x (1 - concession)
--    A 25% purser and a 30% bargain give 47.5% off, not 55%. Each is read through its existing
--    single authority — `public.fleet_officer_bonus` (0015:108) and this file's
--    `public.haggle_concession` — and nothing in this file sums a bonus itself.
--
-- 6. THE FLOOR IS 55% OF THE PUBLISHED SPREAD. Whatever stacks, the executed spread is never
--    below `haggle_spread_floor_frac` x published. Why 55: the quay must always keep MORE THAN
--    HALF its living. A port whose margin could be negotiated away entirely is not a port.
--
--    WHERE IT BITES, MEASURED RATHER THAN CLAIMED — and the two figures are not the same, so both
--    are stated:
--      * against the OFFICER CAP the knobs already permit (`officer_bonus_cap_pct` = 25) the
--        maximum stack is 0.75 x 0.70 = 0.525, which is BELOW 0.55. The floor fires.
--      * against TODAY'S SEEDED ROSTER it does not. 0015:354-358 authors exactly two PURSERs, at
--        6.00 and 4.00 per cent, so the most a fleet can actually carry is 10 per cent and the
--        reachable stack is 0.90 x 0.70 = 0.63, comfortably clear of the floor.
--    So this is a GUARDRAIL on the knob, not a limiter on the current game: it costs nobody
--    anything today and it is already in place the day a richer purser is authored or the
--    concession cap is raised. The self-assert proves it BITES by posting a purser at the cap the
--    schema already allows (`officers.bonus_pct <= 25`), inside the rolled-back probe — a
--    precondition it sets rather than one it borrows.
--
-- 7. A BARGAIN IS SPENT, NOT WORN. The concession is consumed by the next trade of that good at
--    that port and expires with the game-day in any case (the row is keyed on game_day, so a new
--    day IS a fresh row). The alternative — a day-long buff bounded by the existing daily volume
--    cap — was considered and rejected: a thing you SPEND is legible in a way a buff is not, and
--    the player is told which it is, in the read and in the success sentence, so it is never a
--    hidden trap.
--
-- ── WHAT IT IS ACTUALLY WORTH, MEASURED RATHER THAN REASONED ───────────────────────────────────
-- Balance is measured or it is a story. Measured on this chain 2026-08-22 (PGlite 0.5.5 /
-- PostgreSQL 18.3). The world's published spreads run 0.0240 to 0.0460, averaging 0.0384; a house
-- pays half the spread on each leg, so a bargain is worth `concession x spread` over a round trip:
--
--     port   published spread   one win (15%)      bargained to the cap (30%), round trip
--     LIS    0.0260             0.195% of the ask  0.78% of the stake
--     TUN    0.0360             0.270%             1.08%
--     ANT    0.0420             0.315%             1.26%
--
-- Against a median first voyage of about 12 per cent of the stake (proof 5), bargaining both legs
-- to the cap is worth roughly one extra voyage in twelve. That is deliberately a MARGIN and not a
-- strategy: choosing the right cargo and the right leg is worth 12 points and haggling is worth
-- one, so a good bargainer trading a bad route still loses to a bad bargainer trading a good one.
-- If the owner wants it to bite harder, `haggle_concession_step` and `haggle_concession_max` are
-- the two knobs and neither needs a code change.
--
-- ── THE UNHAGGLED ECONOMY IS UNCHANGED, AND THAT IS PROVEN BY PRE-IMAGE ────────────────────────
-- With no bargain open, `haggle_concession` returns 0 and `spread_effective` reduces to exactly
-- 0017:376's expression. The self-assert captures the ask, bid, units and total that world.quote()
-- returns for a spread of real (port, good, qty, side) combinations BEFORE the replacement, and
-- requires them BYTE-IDENTICAL afterwards, in the same transaction and therefore at the same
-- clock. That is the only honest form of this claim: proofs 04 and 05 DISCOVER their itinerary
-- against a world priced on now(), so their headline percentages differ between any two runs of an
-- unchanged chain (measured 2026-08-22 and written up in 0021's header). A before/after comparison
-- of those two files would prove nothing in either direction. This one proves it exactly.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   * It does not touch `world.mid_price`, `world.price`, `world.spread` or `world.tax_rate`. The
--     mid is the world's and the published spread is the port's; a negotiation is neither.
--   * It does not change `world.quote`'s ARITY. 0017 had to DROP and re-create because it appended
--     a parameter, and a dropped function takes its ACL with it (0017:83-87). Everything this file
--     needs is derivable from the fleet it already receives, so `create or replace` is enough and
--     no grant on it moves.
--   * It does not add haggling to `world.market()`. That read serves all 70 goods of a port and a
--     per-good bargain lookup on every one of them, for a state that is empty for almost every
--     good almost always, is a cost paid on every market open to show nothing.
--     `world.haggle_state(fleet, good)` is the read, shaped like `world.buy_capacity` (0009:236).
--   * It does not let ACCOUNTING or NAVIGATION out of their box. Two of 0016's four skills are
--     still unread and world.skills() still says so, for exactly the reasons 0016:33-40 gives.
--
-- ── GRANTS: THIS FILE GRANTS, SO IT NEEDS THE MANAGEMENT API PATH ──────────────────────────────
-- Two new client entry points (`cmd.haggle`, `world.haggle_state`) take `grant execute … to
-- authenticated`, and the new table takes `grant select`. `supabase db push` connects as
-- `postgres.<ref>` through the pooler and cannot do this on these schemas; 0018 failed there and
-- applied cleanly through the Management API as `postgres`. Deploy this one the same way.
--
-- Depends ONLY on: 0004 (players/fleets/credit/emit_event/current_player_id), 0005 (spread, tax,
--                  mid_price, quote, game_day, trade_daily), 0006 (voyage.rng), 0015
--                  (fleet_officer_bonus), 0016 (player_skill_bonus, skills, world.skills),
--                  0017 (world.quote's purser cut, do_buy, do_sell), 0018/0019
--                  (client_rpc_entry_points).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGE. Real quotes, on real (port, good) pairs, taken through the CURRENT world.quote()
-- before a line of it moves — so "the unhaggled economy did not change" is a comparison and not a
-- sentence. Scaffolding for one assert; dropped at the foot of this file.
create temporary table quote_before_0022 as
  select pg.port_id, pg.good_id, s.side, s.qty,
         q.units, q.total, q.avg_price, q.end_stock,
         world.spread(pg.port_id) as published_spread
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 40) pg
   cross join (values ('buy'::text, 10::numeric), ('buy', 130), ('sell', 25)) as s(side, qty)
   cross join lateral world.quote(pg.port_id, pg.good_id, s.qty, s.side) q;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('haggle_attempts_per_day', to_jsonb(3),
   'DESIGN G.1 (0022): how many times a house may open a bargain for one good at one port in one game-day. Finite, because an unlimited attempt is not a gamble.'),
  ('haggle_base_success', to_jsonb(0.45),
   'The chance an unskilled captain wins a bargain on a fresh attempt, before the HAGGLING skill and before any hardening from earlier refusals.'),
  ('haggle_success_max', to_jsonb(0.85),
   'The ceiling on the odds after skill. A negotiation that always works is a discount, not a negotiation.'),
  ('haggle_hardening_per_fail', to_jsonb(0.25),
   'Each refusal today multiplies the NEXT attempt''s odds by (1 - this). The factor hardens; the PUBLISHED price never moves, so what world.market() shows is still what a trade charges.'),
  ('haggle_concession_step', to_jsonb(0.15),
   'What one won bargain shaves off the port''s spread, as a fraction of it. The mid is never touched: haggling moves the port''s cut, not what a thing is worth.'),
  ('haggle_concession_max', to_jsonb(0.30),
   'The most an open bargain may be worth however many attempts won it — two wins reach it at the shipped step.'),
  ('haggle_spread_floor_frac', to_jsonb(0.55),
   'The executed spread may never fall below this fraction of the port''s published spread, whatever the purser and the bargain stack to. The quay always keeps more than half its living. A GUARDRAIL: against the officer cap the knobs permit (25 per cent) the stack reaches 0.525 and this fires, but today''s two seeded PURSERs only reach 10 per cent, so it costs the current game nothing.')
on conflict (key) do nothing;

-- ── 2. THE OPEN BARGAIN ────────────────────────────────────────────────────────────────────────
-- Keyed exactly like public.trade_daily (0005:79), and for the same reason: a per (player, port,
-- good, game-day) fact needs no expiry job, because a new day is a new key and the old row is
-- simply never read again.
create table if not exists public.haggle_daily (
  player_id  uuid not null references public.players(id) on delete cascade,
  port_id    uuid not null references public.ports(id)   on delete cascade,
  good_id    uuid not null references public.goods(id)   on delete cascade,
  game_day   int  not null,
  attempts   int  not null default 0 check (attempts >= 0),
  wins       int  not null default 0 check (wins >= 0 and wins <= attempts),
  concession numeric(6,4) not null default 0 check (concession >= 0 and concession <= 1),
  last_side  text check (last_side in ('buy', 'sell')),
  updated_at timestamptz not null default now(),
  primary key (player_id, port_id, good_id, game_day)
);

comment on table public.haggle_daily is
  'One open bargain per (house, port, good, game-day). `attempts` is written BEFORE the outcome is '
  'known and is what the RNG stream is keyed on, which is what makes save-scumming structurally '
  'impossible rather than merely discouraged: a retry is a different draw that has already cost a '
  'chance. `concession` is a FRACTION OF THE PORT''S SPREAD, never of the price.';
comment on column public.haggle_daily.last_side is
  'Which side the last attempt was opened on. Recorded for the ledger''s prose and for the read; '
  'it does not scope the concession, because the spread is ONE number and scoping it per side '
  'would be two authorities for what a house executes at.';

alter table public.haggle_daily enable row level security;
create policy haggle_daily_read_own on public.haggle_daily for select to authenticated
  using (player_id = public.current_player_id());
grant select on public.haggle_daily to authenticated;

-- ── 3. THE TWO READINGS NOTHING ELSE MAY RE-DERIVE ─────────────────────────────────────────────
create or replace function public.haggle_concession(p_player uuid, p_port uuid, p_good uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Zero when there is no row, which is the overwhelmingly common case and the reason
  -- world.spread_effective reduces to 0017's arithmetic exactly for an unhaggled house.
  select coalesce((select h.concession from public.haggle_daily h
                    where h.player_id = p_player and h.port_id = p_port
                      and h.good_id = p_good and h.game_day = world.game_day()), 0)
$$;

comment on function public.haggle_concession(uuid, uuid, uuid) is
  'THE one reading of "what bargain does this house hold for this good at this port today", as a '
  'fraction of the port''s published spread. world.spread_effective composes onto it; nothing '
  'reads public.haggle_daily.concession directly.';

create or replace function public.haggle_odds(p_player uuid, p_port uuid, p_good uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_fails int;
  v_odds  numeric;
begin
  select greatest(0, h.attempts - h.wins) into v_fails
    from public.haggle_daily h
   where h.player_id = p_player and h.port_id = p_port
     and h.good_id = p_good and h.game_day = world.game_day();
  v_fails := coalesce(v_fails, 0);

  -- Base, plus the HAGGLING skill read through its ONE authority (0016:97), then hardened by
  -- every refusal already taken today, then clamped. Decision 4: the skill moves this and only
  -- this.
  v_odds := (public.wc_num('haggle_base_success')
             + public.player_skill_bonus(p_player, 'SPREAD'))
            * greatest(0, 1 - public.wc_num('haggle_hardening_per_fail') * v_fails);

  return round(least(public.wc_num('haggle_success_max'), greatest(0, v_odds)), 4);
end $$;

comment on function public.haggle_odds(uuid, uuid, uuid) is
  'THE one reading of "what are the odds of the next bargain here". Called by cmd.haggle to roll '
  'against AND by world.haggle_state to show the player, so the number displayed and the number '
  'rolled against are the same number by construction.';

-- ── 4. THE SPREAD A TRADE EXECUTES AT — SUPERSEDES THE INLINE AT 0017:376 ──────────────────────
create or replace function world.spread_effective(p_port uuid, p_good uuid, p_fleet uuid default null)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_pub    numeric := world.spread(p_port);
  v_player uuid;
  v_purser numeric := 0;
  v_hag    numeric := 0;
begin
  -- With no fleet named this is world.spread() exactly, which is what every caller that predates
  -- the purser still passes (0005's own asserts, 0007's capacity walk, 0019's scan).
  if p_fleet is not null then
    select f.player_id into v_player from public.fleets f where f.id = p_fleet;
    v_purser := public.fleet_officer_bonus(p_fleet, 'PURSER');
    if v_player is not null then
      v_hag := public.haggle_concession(v_player, p_port, p_good);
    end if;
  end if;

  -- Decision 5: MULTIPLICATIVE, so two shaves cannot add up to more than either could win.
  -- Decision 6: and the floor, which the port keeps whatever stacks.
  return greatest(v_pub * public.wc_num('haggle_spread_floor_frac'),
                  v_pub * (1 - v_purser) * (1 - v_hag));
end $$;

comment on function world.spread_effective(uuid, uuid, uuid) is
  'THE spread a given house executes a given trade at: the port''s published spread (world.spread, '
  'untouched), less the purser''s shave (0015/0017) and less any open bargain (0022), composed '
  'multiplicatively and floored at haggle_spread_floor_frac of the published figure. Supersedes '
  'the expression 0017 inlined in world.quote:184 — that line is now a call, so a rule that '
  'changes what a house executes at has one place to change.';

-- Not a client entry point: world.haggle_state serves every figure a panel needs, and world.quote
-- reaches this as its own definer. A read nothing calls should not hold a grant (0018).
revoke all on function world.spread_effective(uuid, uuid, uuid) from public, anon, authenticated;

-- ── 5. THE ONLY PRICE THE MONEY MOVES AT — SUPERSEDES 0017:340 ────────────────────────────────
-- Same arity, same six parameters, same body, with ONE line changed: the spread it walks now comes
-- from world.spread_effective instead of being computed here. `create or replace` therefore keeps
-- the ACL 0017 set, which the self-assert re-reads rather than assumes.
create or replace function world.quote(
  p_port uuid, p_good uuid, p_qty numeric, p_side text,
  p_limit numeric default null, p_fleet uuid default null
)
returns table (units numeric, total bigint, avg_price numeric, end_stock numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_stock  numeric;
  v_spread numeric;
  v_tax    numeric;
  v_left   numeric := p_qty;
  v_n      numeric;
  v_mid    numeric;
  v_unit   numeric;
  v_units  numeric := 0;
  v_total  numeric := 0;
begin
  if p_side not in ('buy', 'sell') then
    raise exception 'world.quote: side must be buy or sell, got %', p_side using errcode = '22023';
  end if;

  select pg.stock into v_stock from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good;
  if v_stock is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  -- 0022: the ONE reading of what this house executes at — the port's published spread, her
  -- purser, and any bargain struck on this quay today. With no fleet named, or no purser posted,
  -- or no bargain open, this is world.spread(p_port) to the digit and the arithmetic below is
  -- 0005's and 0017's unchanged.
  v_spread := world.spread_effective(p_port, p_good, p_fleet);
  v_tax    := world.tax_rate(p_port);

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
  -- average." The loop IS the price impact; there is no separate impact formula to drift from it.
  while v_left > 0 loop
    v_n := least(v_step, v_left);
    if p_side = 'buy' then
      if v_stock < v_n then v_n := v_stock; end if;
      exit when v_n <= 0;
      v_mid  := world.mid_price(p_port, p_good, v_stock);
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
      -- §F.2: a limit order PARTIALLY FILLS to the largest quantity that stays under the limit.
      exit when p_limit is not null and v_unit > p_limit;
      v_total := v_total + v_unit * v_n;
      v_stock := v_stock - v_n;
    else
      v_mid  := world.mid_price(p_port, p_good, v_stock);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);
      exit when p_limit is not null and v_unit < p_limit;
      v_total := v_total + v_unit * v_n;
      v_stock := v_stock + v_n;
    end if;
    v_units := v_units + v_n;
    v_left  := v_left - v_n;
  end loop;

  units     := v_units;
  total     := round(v_total)::bigint;
  avg_price := case when v_units > 0 then round(v_total / v_units, 2) else null end;
  end_stock := v_stock;
  return next;
end $$;

comment on function world.quote(uuid, uuid, numeric, text, numeric, uuid) is
  'THE stepped execution price, and the only price the money moves at. Supersedes the 0017 '
  'definition in ONE line: the spread it walks is world.spread_effective(port, good, fleet), which '
  'folds the purser and any open bargain and floors the pair. Identical to 0017 for a house with '
  'no purser and no bargain, which 0022 proves against a captured pre-image rather than claiming.';

-- ── 6. STRIKING THE BARGAIN ────────────────────────────────────────────────────────────────────
create or replace function cmd.haggle(p_fleet uuid, p_good uuid, p_side text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player  uuid := public.current_player_id();
  v_side    text := lower(btrim(coalesce(p_side, '')));
  f         public.fleets%rowtype;
  g         public.goods%rowtype;
  v_port    record;
  v_day     int  := world.game_day();
  v_max     int  := public.wc_int('haggle_attempts_per_day');
  v_used    int;
  v_attempt int;
  v_odds    numeric;
  v_roll    numeric;
  v_won     boolean;
  v_before  numeric;
  v_after   numeric;
  v_step    numeric := public.wc_num('haggle_concession_step');
  v_cap     numeric := public.wc_num('haggle_concession_max');
  v_stock   numeric;
  v_have    numeric;
  v_culture text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in, so there is no captain to bargain.',
      'fixes', jsonb_build_array('(sign in first)'));
  end if;
  if v_side not in ('buy', 'sell') then
    return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
      'error_message', 'A bargain is struck to buy or to sell; name which.',
      'fixes', jsonb_build_array('(haggle to buy)', '(haggle to sell)'));
  end if;

  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id is distinct from v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
      'error_message', 'That fleet is not yours.',
      'fixes', jsonb_build_array('(name one of your own fleets)'));
  end if;
  if f.status <> 'DOCKED' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_DOCKED',
      'error_message', format('%s is %s. A bargain is struck face to face, on the quay.', f.name, f.status),
      'fixes', jsonb_build_array('(wait until she is docked)'));
  end if;

  select * into g from public.goods where id = p_good;
  if g.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_GOOD',
      'error_message', 'Nothing is traded under that name.',
      'fixes', jsonb_build_array('(name a good the port trades)'));
  end if;

  select p.code, p.name, p.culture into v_port from public.ports p where p.id = f.port_id;
  if v_port.culture = any(g.culture_mask) then
    return jsonb_build_object('ok', false, 'error_code', 'E_UNAVAILABLE',
      'error_message', format('%s is not traded in %s, so there is nothing to bargain over.', g.name, v_port.name),
      'fixes', jsonb_build_array('(pick a good this port trades)'));
  end if;

  -- THE SIDE GATES. This is what makes p_side load-bearing rather than decoration: you cannot open
  -- a bargain over a cargo the quay has none of, nor over one you are not carrying.
  if v_side = 'buy' then
    select stock into v_stock from public.port_goods where port_id = f.port_id and good_id = g.id;
    if coalesce(v_stock, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_STOCK',
        'error_message', format('There is no %s for sale in %s to bargain over.', g.name, v_port.name),
        'fixes', jsonb_build_array('(haggle to sell instead)', '(pick a good the port holds)'));
    end if;
  else
    v_have := public.fleet_cargo_qty(p_fleet, g.code);
    if coalesce(v_have, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_CARGO',
        'error_message', format('%s carries no %s, so there is nothing to bargain over.', f.name, g.name),
        'fixes', jsonb_build_array('(haggle to buy instead)', '(sell something she carries)'));
    end if;
  end if;

  select h.attempts into v_used from public.haggle_daily h
   where h.player_id = v_player and h.port_id = f.port_id
     and h.good_id = g.id and h.game_day = v_day;
  v_used := coalesce(v_used, 0);
  if v_used >= v_max then
    return jsonb_build_object('ok', false, 'error_code', 'E_HAGGLE_SPENT',
      'error_message', format('The factor will hear no more about %s in %s today. You have had %s of %s.',
                              g.name, v_port.name, v_used, v_max),
      'fixes', jsonb_build_array('(trade at the price offered)', '(come back tomorrow)',
                                 '(bargain over a different good)'));
  end if;

  -- THE ODDS ARE READ BEFORE THE ATTEMPT IS SPENT, because they depend on the refusals already
  -- taken and not on this one.
  v_odds   := public.haggle_odds(v_player, f.port_id, g.id);
  v_before := public.haggle_concession(v_player, f.port_id, g.id);

  -- ── DECISION 2: THE ATTEMPT IS SPENT FIRST. `attempts` is incremented here, before the roll is
  --    taken, and the attempt INDEX is what the stream is keyed on. There is no ordering of calls
  --    that re-rolls a draw: attempt k is a pure function of (player, port, good, day, k, secret),
  --    and calling again gives k+1.
  insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession, last_side)
  values (v_player, f.port_id, g.id, v_day, 1, 0, 0, v_side)
  on conflict (player_id, port_id, good_id, game_day) do update
    set attempts = public.haggle_daily.attempts + 1,
        last_side = excluded.last_side,
        updated_at = now();

  v_attempt := v_used;   -- zero-based index of THIS attempt
  v_roll := voyage.rng(v_player, v_day, format('haggle:%s:%s:%s', f.port_id, g.id, v_attempt));
  v_won  := v_roll < v_odds;

  if v_won then
    v_after := least(v_cap, v_before + v_step);
    update public.haggle_daily
       set wins = wins + 1, concession = v_after, updated_at = now()
     where player_id = v_player and port_id = f.port_id and good_id = g.id and game_day = v_day;
  else
    v_after := v_before;
  end if;

  perform public.emit_event(v_player, 'HAGGLED', jsonb_build_object(
    'fleet', f.name, 'port', v_port.code, 'good', g.name, 'side', v_side,
    'won', v_won, 'attempt', v_attempt + 1, 'of', v_max,
    'odds', v_odds, 'concession', v_after));

  return jsonb_build_object(
    'ok', true,
    'won', v_won,
    'good', g.code, 'good_name', g.name, 'port', v_port.code, 'side', v_side,
    'odds', v_odds,
    'attempt', v_attempt + 1, 'attempts_max', v_max, 'attempts_left', v_max - (v_attempt + 1),
    'concession', v_after,
    'concession_pct', round(v_after * 100, 1),
    'concession_max_pct', round(v_cap * 100, 1),
    'next_odds', public.haggle_odds(v_player, f.port_id, g.id),
    'spread_published', round(world.spread(f.port_id), 6),
    'spread_effective', round(world.spread_effective(f.port_id, g.id, p_fleet), 6),
    'message', case
        when v_won and v_after >= v_cap then
          format('The factor spits, laughs, and takes %s per cent off his cut on %s. He will go no further today.',
                 round(v_after * 100, 1), g.name)
        when v_won then
          format('Hands are shaken. He comes down to %s per cent off his cut on %s — spend it on your next trade of it here, or lose it at the day''s end.',
                 round(v_after * 100, 1), g.name)
        else
          format('He folds his arms and names the same figure. %s of %s tries gone, and he is harder for it.',
                 v_attempt + 1, v_max)
      end);
end $$;

comment on function cmd.haggle(uuid, uuid, text) is
  'ONE attempt at a bargain. Writes the attempt BEFORE it rolls, and keys the roll on the attempt '
  'index, so a retry is a different draw that has already cost a chance — save-scumming is not '
  'discouraged here, it is impossible. Wins a fraction off the PORT''S SPREAD, never off the mid.';

revoke all on function cmd.haggle(uuid, uuid, text) from public, anon;
grant execute on function cmd.haggle(uuid, uuid, text) to authenticated;

-- ── 7. THE READ THE PANEL NEEDS ────────────────────────────────────────────────────────────────
-- Shaped like world.buy_capacity (0009:236): it checks the fleet is yours and then composes onto
-- the internal readings, so the panel and the verb cannot disagree about the odds or the cap.
create or replace function world.haggle_state(p_fleet uuid, p_good uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  f        public.fleets%rowtype;
  v_day    int := world.game_day();
  v_max    int := public.wc_int('haggle_attempts_per_day');
  v_used   int;
  v_wins   int;
  v_conc   numeric;
  v_pub    numeric;
  v_eff    numeric;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no house signed in' using errcode = 'P0001';
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id is distinct from v_player then
    raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
  end if;
  if f.port_id is null then
    return jsonb_build_object('docked', false, 'attempts_max', v_max,
      'why', 'She is at sea. A bargain is struck on the quay.');
  end if;

  select h.attempts, h.wins into v_used, v_wins from public.haggle_daily h
   where h.player_id = v_player and h.port_id = f.port_id
     and h.good_id = p_good and h.game_day = v_day;
  v_used := coalesce(v_used, 0);
  v_wins := coalesce(v_wins, 0);

  v_conc := public.haggle_concession(v_player, f.port_id, p_good);
  v_pub  := world.spread(f.port_id);
  v_eff  := world.spread_effective(f.port_id, p_good, p_fleet);

  return jsonb_build_object(
    'docked', true,
    'port', (select code from public.ports where id = f.port_id),
    'good', (select code from public.goods where id = p_good),
    'game_day', v_day,
    -- how much negotiation can be done
    'attempts_used', v_used,
    'attempts_left', greatest(0, v_max - v_used),
    'attempts_max',  v_max,
    'wins', v_wins,
    -- what is currently held, and what it could ever be
    'concession',        v_conc,
    'concession_pct',    round(v_conc * 100, 1),
    'concession_max',     public.wc_num('haggle_concession_max'),
    'concession_max_pct', round(public.wc_num('haggle_concession_max') * 100, 1),
    'step_pct',          round(public.wc_num('haggle_concession_step') * 100, 1),
    -- the odds of the NEXT attempt, from the same authority cmd.haggle rolls against
    'next_odds',     public.haggle_odds(v_player, f.port_id, p_good),
    'next_odds_pct', round(public.haggle_odds(v_player, f.port_id, p_good) * 100, 1),
    -- and what it is worth, in the only terms that matter: the spread this house executes at
    'spread_published', round(v_pub, 6),
    'spread_effective', round(v_eff, 6),
    'spread_floor',     round(v_pub * public.wc_num('haggle_spread_floor_frac'), 6),
    'at_floor',         (v_eff <= v_pub * public.wc_num('haggle_spread_floor_frac') + 1e-9),
    'spent_on', 'the next trade of this good at this port, or the day''s end');
end $$;

comment on function world.haggle_state(uuid, uuid) is
  'What the COMMAND/PORT panel needs to answer "how much negotiation can be done here": attempts '
  'left today, the bargain currently held, the cap it can reach, the odds of the next attempt and '
  'the spread this house would actually execute at. Every figure comes from the same authority '
  'cmd.haggle uses, so the panel cannot promise what the verb will not do.';

revoke all on function world.haggle_state(uuid, uuid) from public, anon;
grant execute on function world.haggle_state(uuid, uuid) to authenticated;

-- ── 8. AND THE BARGAIN IS SPENT — SUPERSEDES 0017:496 AND 0017:577 ────────────────────────────
-- The win and the SPENDING of it land in one file, for the reason 0017:50-55 records: a rule wired
-- into the check and not the placement makes a player pay for something that never happens. Both
-- verbs are 0017's body with ONE statement appended after the trade has actually moved goods.
create or replace function cmd.do_buy(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  g       public.goods%rowtype;
  v_qty   numeric;
  v_cap   numeric;
  v_free  numeric;
  v_stock numeric;
  v_purse bigint;
  q       record;
  v_culture text;
  v_loaded  numeric;
  v_conc    numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to trade', f.name, f.status using errcode = 'P0001';
  end if;
  select * into g from public.goods where id = (p_args->>'good')::uuid;
  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;

  select culture into v_culture from public.ports where id = f.port_id;
  if v_culture = any(g.culture_mask) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  select stock into v_stock from public.port_goods where port_id = f.port_id and good_id = g.id;
  if v_stock is null then raise exception 'E_NO_SUCH_GOOD: no market for % here', g.name using errcode = 'P0001'; end if;

  v_qty  := cmd.resolve_qty(p_fleet, g.code, 'buy', p_args);
  v_free := floor(public.fleet_free_hold(p_fleet) / g.bulk);
  if v_qty <= 0 then
    raise exception 'E_HOLD_FULL: there is no room aboard for %', g.name using errcode = 'P0001';
  end if;
  if v_qty > v_free then
    raise exception 'E_HOLD_FULL: the fleet has room for % tuns of % and you asked for %',
      v_free, g.name, v_qty using errcode = 'P0001';
  end if;
  if v_stock <= 0 then
    raise exception 'E_NO_STOCK: there is none for sale here' using errcode = 'P0001';
  end if;
  v_cap := world.daily_cap_remaining(f.player_id, f.port_id, g.id);
  if v_qty > v_cap then
    raise exception 'E_DAILY_CAP: you may take % more tuns of % here today', floor(v_cap), g.name using errcode = 'P0001';
  end if;

  -- 0017: priced through this fleet's own purser. 0022: and through any bargain struck today —
  -- the same call world.spread_effective serves the preview and the quay's own shortlist, so what
  -- was quoted is what is charged.
  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
  select * into q from world.quote(f.port_id, g.id, v_qty, 'buy',
                                   nullif((p_args->>'limit'), '')::numeric, p_fleet);
  if q.units <= 0 then
    if p_args ? 'limit' and p_args->>'limit' is not null then
      raise exception 'E_PRICE_LIMIT: % opened above your limit of % and nothing was bought',
        g.name, (p_args->>'limit') using errcode = 'P0001';
    end if;
    raise exception 'E_NO_STOCK: nothing could be bought' using errcode = 'P0001';
  end if;

  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < q.total then
    raise exception 'E_INSUFFICIENT_FUNDS: % tuns of % cost % d. and you hold %',
      q.units, g.name, q.total, v_purse using errcode = 'P0001';
  end if;

  v_loaded := public.fleet_load(p_fleet, g.code, q.units);
  update public.port_goods set stock = q.end_stock, updated_at = now()
   where port_id = f.port_id and good_id = g.id;
  insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
  values (f.player_id, f.port_id, g.id, world.game_day(), q.units)
  on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty;

  -- 0022, DECISION 7: a bargain is SPENT. The goods have moved and the money is about to; the
  -- concession goes with them. The attempt counter is deliberately NOT reset — the day's three
  -- tries are the day's three tries, whether or not you spent what they won.
  if v_conc > 0 then
    update public.haggle_daily set concession = 0, updated_at = now()
     where player_id = f.player_id and port_id = f.port_id
       and good_id = g.id and game_day = world.game_day();
  end if;

  perform public.credit(f.player_id, 'BUY', -q.total,
    public.emit_event(f.player_id, 'BOUGHT', jsonb_build_object(
      'fleet', f.name, 'good', g.name, 'qty', q.units, 'avg_price', q.avg_price, 'total', q.total,
      'haggled', v_conc > 0, 'concession', v_conc)));

  return jsonb_build_object('good', g.code, 'qty', v_loaded, 'total', q.total,
                            'avg_price', q.avg_price, 'concession_spent', v_conc);
end $$;

create or replace function cmd.do_sell(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  g       public.goods%rowtype;
  v_qty   numeric;
  v_have  numeric;
  v_cap   numeric;
  q       record;
  v_culture text;
  v_conc    numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and must be docked to trade', f.name, f.status using errcode = 'P0001';
  end if;
  select * into g from public.goods where id = (p_args->>'good')::uuid;
  if g.id is null then raise exception 'E_NO_SUCH_GOOD: unknown good' using errcode = 'P0001'; end if;

  select culture into v_culture from public.ports where id = f.port_id;
  if v_culture = any(g.culture_mask) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  v_have := public.fleet_cargo_qty(p_fleet, g.code);
  v_qty  := least(cmd.resolve_qty(p_fleet, g.code, 'sell', p_args), v_have);
  if v_have <= 0 or v_qty <= 0 then
    raise exception 'E_NO_CARGO: % carries no %', f.name, g.name using errcode = 'P0001';
  end if;
  v_cap := world.daily_cap_remaining(f.player_id, f.port_id, g.id);
  if v_qty > v_cap then
    raise exception 'E_DAILY_CAP: you may move % more tuns of % here today', floor(v_cap), g.name using errcode = 'P0001';
  end if;

  -- 0017: the purser lifts the bid as much as he shaves the ask. 0022: and so does a bargain —
  -- the spread is one number and shaving it pays on whichever side she is trading.
  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
  select * into q from world.quote(f.port_id, g.id, v_qty, 'sell',
                                   nullif((p_args->>'limit'), '')::numeric, p_fleet);
  if q.units <= 0 then
    raise exception 'E_PRICE_LIMIT: % is bid below your limit of % and nothing was sold',
      g.name, (p_args->>'limit') using errcode = 'P0001';
  end if;

  perform public.fleet_unload(p_fleet, g.code, q.units);
  update public.port_goods set stock = q.end_stock, updated_at = now()
   where port_id = f.port_id and good_id = g.id;
  insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
  values (f.player_id, f.port_id, g.id, world.game_day(), q.units)
  on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty;

  if v_conc > 0 then
    update public.haggle_daily set concession = 0, updated_at = now()
     where player_id = f.player_id and port_id = f.port_id
       and good_id = g.id and game_day = world.game_day();
  end if;

  perform public.credit(f.player_id, 'SELL', q.total,
    public.emit_event(f.player_id, 'SOLD', jsonb_build_object(
      'fleet', f.name, 'good', g.name, 'qty', q.units, 'avg_price', q.avg_price, 'total', q.total,
      'haggled', v_conc > 0, 'concession', v_conc)));

  return jsonb_build_object('good', g.code, 'qty', q.units, 'total', q.total,
                            'avg_price', q.avg_price, 'concession_spent', v_conc);
end $$;

revoke all on function cmd.do_buy(uuid, jsonb)  from public, anon, authenticated;
revoke all on function cmd.do_sell(uuid, jsonb) from public, anon, authenticated;

-- ── 9. THE SKILL IS READ NOW, AND THE READ MUST SAY SO — SUPERSEDES 0016:252 AND ITS SEED ─────
update public.skills
   set blurb = 'The difference between what a thing is worth and what you pay for it. Every level '
               'improves the odds that a factor comes down off his cut when you bargain (0022).'
 where code = 'HAGGLING';

create or replace function world.skills()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  -- 0022: SPREAD joins ENDURANCE. Two of the four are read; ACCOUNTING and NAVIGATION are still
  -- not, and this list is the one place that says which — a `takes_effect` that lies is worse than
  -- no flag at all, because a player spends tuition on it.
  v_read   constant text[] := array['ENDURANCE', 'SPREAD'];
begin
  return jsonb_build_object(
    'max_level', public.wc_int('skill_max_level'),
    'base_cost', public.wc_int('skill_study_base_cost'),
    'effects_read', to_jsonb(v_read),
    'skills', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name, 'effect', s.effect,
               'pct_per_level', s.pct_per_level, 'blurb', s.blurb,
               'level', coalesce(ps.level, 0),
               'next_cost', case when coalesce(ps.level, 0) >= public.wc_int('skill_max_level')
                                 then null
                                 else public.wc_int('skill_study_base_cost') * (coalesce(ps.level, 0) + 1) end,
               'takes_effect', (s.effect = any(v_read))
             ) order by s.code), '[]'::jsonb)
        from public.skills s
        left join public.player_skills ps on ps.skill_id = s.id and ps.player_id = v_player));
end $$;

comment on function world.skills() is
  'What can be learned, and how far this house has learned it. Supersedes the 0016 definition in '
  'its `effects_read` list only: SPREAD is read by public.haggle_odds since 0022, so HAGGLING now '
  'reports takes_effect true. ACCOUNTING and NAVIGATION still report false, truthfully.';

-- ── 10. THE CLIENT ENTRY POINTS — SUPERSEDES 0019:871 ─────────────────────────────────────────
-- Two rows added. 0018's rule stands: this list and src/lib/rpc/catalog.ts are one statement of
-- what a browser may call, and client_executable_writers() subtracts it, so granted and sanctioned
-- cannot drift.
create or replace function public.client_rpc_entry_points()
returns table (schema_name text, function_name text, arg_types text, fn regprocedure)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.s, t.f, t.a,
         to_regprocedure(format('%I.%I(%s)', t.s, t.f, t.a))
    from (values
      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),
      ('world',       'market',              'uuid'),
      ('world',       'fleets',              ''),
      ('world',       'ledger',              'timestamptz, int'),
      ('world',       'buy_capacity',        'uuid, uuid'),
      ('world',       'price_history',       'uuid, int'),
      ('world',       'player',              ''),
      ('world',       'officers',            ''),
      ('world',       'skills',              ''),
      ('world',       'trade_routes',        'uuid, uuid, int, int, uuid'),
      -- 0022: what the negotiation panel needs. src/lib/rpc/catalog.ts names it `worldHaggleState`.
      ('world',       'haggle_state',        'uuid, uuid'),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int'),
      ('cmd',         'preview',             'uuid, text'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text'),
      -- 0022: striking the bargain. src/lib/rpc/catalog.ts names it `cmdHaggle`.
      ('cmd',         'haggle',              'uuid, uuid, text')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe   constant uuid := '00000000-0022-4000-8000-000000000022';
  v_player  uuid;
  v_fleet   uuid;
  v_port    uuid;
  v_good    uuid;
  v_day     int;
  v_pub     numeric;
  v_eff     numeric;
  v_eff_win numeric;   -- (e)'s measurement, kept separate: (g) and (h) reassign v_eff, and an
                       -- error message that prints a variable which has moved on since the check
                       -- is a diagnosis that sends the reader to the wrong place.
  v_conc    numeric;
  v_ask0    numeric;  v_ask1 numeric;
  v_mid0    numeric;  v_mid1 numeric;
  v_bid0    numeric;  v_bid1 numeric;
  v_res     jsonb;
  v_state   jsonb;
  v_odds    numeric;
  v_odds0   numeric;
  v_roll    numeric;
  v_wins    int;
  v_tries   int;
  v_i       int;
  v_pre_rows int;
  v_drift   int;
  v_stack_cap  numeric;   -- what the KNOBS allow to stack
  v_stack_real numeric;   -- what the probe's fleet actually stacked
  v_floor   numeric;
  v_officer uuid;
  v_skill   uuid;
  v_left    int;
  v_purse0  bigint;  v_purse1 bigint;
  v_total0  bigint;  v_total1 bigint;
  -- findings, recorded inside the throwaway subtransaction and read after it is gone
  f_noop      boolean := false;
  f_reachable boolean := false;
  f_predicted boolean := false;
  f_finite    boolean := false;
  f_moves     boolean := false;
  f_mid_still boolean := false;
  f_spent     boolean := false;
  f_floor     boolean := false;
  f_compose   boolean := false;
  f_reads     boolean := false;
  f_harden    boolean := false;
  f_grant     boolean := false;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) THE UNHAGGLED ECONOMY DID NOT MOVE. Real quotes, taken through the OLD world.quote before
  --     this file replaced it and re-taken through the new one, in the same transaction and
  --     therefore against the same clock and the same drift. Every column must be identical, and
  --     the pre-image must be non-empty or the comparison proves nothing.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select count(*) into v_pre_rows from quote_before_0022;
  if v_pre_rows < 60 then
    raise exception '0022 self-assert FAIL: the quote pre-image holds only % row(s); the no-op comparison below would be nearly vacuous', v_pre_rows;
  end if;
  select count(*) into v_drift
    from quote_before_0022 b
    cross join lateral world.quote(b.port_id, b.good_id, b.qty, b.side) a
   where (a.units, a.total, a.avg_price, a.end_stock)
         is distinct from (b.units, b.total, b.avg_price, b.end_stock);
  if v_drift = 0 then f_noop := true; end if;

  -- DECISION 6, HALF ONE: the floor is REACHABLE under the knobs as shipped. This is the abstract
  -- claim; (g) below proves it fires on a real fleet.
  v_stack_cap := (1 - public.wc_num('officer_bonus_cap_pct') / 100.0)
                 * (1 - public.wc_num('haggle_concession_max'));
  if v_stack_cap < public.wc_num('haggle_spread_floor_frac') then f_reachable := true; end if;

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────
    v_player := public.new_house(c_probe, 'Casa Regateio', 'PRT');
    select f.id, f.port_id into v_fleet, v_port from public.fleets f where f.player_id = v_player;
    perform cmd.assume_identity(c_probe);
    v_day := world.game_day();

    -- FIND THE SUBJECT, never pick one by lottery: a good this port actually holds and trades.
    -- `order by` is what makes it deterministic across heap orders (0014:248-258).
    select pg.good_id into v_good
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports p on p.id = pg.port_id
     where pg.port_id = v_port and pg.stock > 50 and not (p.culture = any(g.culture_mask))
     order by g.code limit 1;
    if v_good is null then
      raise exception '0022 self-assert FAIL: the starting port holds no tradeable good with stock, so every probe below would be vacuous';
    end if;

    v_pub := world.spread(v_port);

    -- (b) THE ROLL IS PREDICTABLE FROM ITS KEY, AND A RETRY IS A DIFFERENT DRAW. Predict every
    --     attempt of the day from voyage.rng independently, BEFORE playing it, then play it and
    --     require the recorded outcome and the attempt index to match. This is what makes
    --     save-scumming impossible rather than merely unlikely: there is no call that re-rolls
    --     attempt k, because k is written before the draw is taken and is part of the key.
    f_predicted := true;
    for v_i in 0 .. public.wc_int('haggle_attempts_per_day') - 1 loop
      v_odds := public.haggle_odds(v_player, v_port, v_good);
      v_roll := voyage.rng(v_player, v_day, format('haggle:%s:%s:%s', v_port, v_good, v_i));
      v_res  := cmd.haggle(v_fleet, v_good, 'buy');
      if (v_res->>'ok')::boolean is not true
         or (v_res->>'won')::boolean is distinct from (v_roll < v_odds)
         or (v_res->>'attempt')::int <> v_i + 1 then
        f_predicted := false;
      end if;
    end loop;

    -- (c) AND THEY RUN OUT. The next attempt is refused, by code, and the refusal carries fixes.
    v_res := cmd.haggle(v_fleet, v_good, 'buy');
    if (v_res->>'ok')::boolean is false
       and v_res->>'error_code' = 'E_HAGGLE_SPENT'
       and jsonb_array_length(v_res->'fixes') >= 2 then
      f_finite := true;
    end if;

    -- (d) THE COUNTER ADVANCED ON REFUSALS TOO, AND A REFUSAL HARDENED THE NEXT ODDS. Asserted
    --     against whichever case the deterministic draws actually produced — a probe may not
    --     require luck it does not control.
    select h.attempts, h.wins into v_tries, v_wins from public.haggle_daily h
     where h.player_id = v_player and h.port_id = v_port and h.good_id = v_good and h.game_day = v_day;
    if v_tries = public.wc_int('haggle_attempts_per_day') then
      if v_wins < v_tries then
        f_harden := public.haggle_odds(v_player, v_port, v_good)
                    = round(least(public.wc_num('haggle_success_max'),
                            (public.wc_num('haggle_base_success') + public.player_skill_bonus(v_player, 'SPREAD'))
                            * greatest(0, 1 - public.wc_num('haggle_hardening_per_fail') * (v_tries - v_wins))), 4)
                    and public.haggle_odds(v_player, v_port, v_good)
                        < public.wc_num('haggle_base_success');
      else
        f_harden := true;   -- nothing was refused, so there is nothing for hardening to do
      end if;
    end if;

    -- (e) A WON BARGAIN MOVES THE EXECUTED PRICE BY THE STATED AMOUNT, AND MOVES THE MID BY
    --     NOTHING. The precondition is SET, not borrowed: the odds go to certainty for this block,
    --     so the measurement is about the SIZE of the effect and not about luck.
    delete from public.haggle_daily where player_id = v_player;
    update public.world_config set value = to_jsonb(1.0) where key = 'haggle_base_success';
    update public.world_config set value = to_jsonb(1.0) where key = 'haggle_success_max';

    select mid, ask, bid into v_mid0, v_ask0, v_bid0 from world.price(v_port, v_good);
    select total into v_total0 from world.quote(v_port, v_good, 20, 'buy', null, v_fleet);

    v_res  := cmd.haggle(v_fleet, v_good, 'buy');
    v_conc := (v_res->>'concession')::numeric;

    select mid, ask, bid into v_mid1, v_ask1, v_bid1 from world.price(v_port, v_good);
    select total into v_total1 from world.quote(v_port, v_good, 20, 'buy', null, v_fleet);
    v_eff_win := world.spread_effective(v_port, v_good, v_fleet);

    -- Exactly one step won, the executed spread exactly the published one less that fraction, and
    -- the quote strictly cheaper for it. Every figure RECOMPUTED here, none pinned.
    if (v_res->>'won')::boolean
       and v_conc = public.wc_num('haggle_concession_step')
       and v_eff_win = v_pub * (1 - v_conc)
       and v_total1 < v_total0 then
      f_moves := true;
    end if;

    -- world.price() takes no fleet, so the PUBLISHED price is untouched — and so is the mid, which
    -- is the half of DESIGN G.1 a negotiation may never reach.
    if v_mid1 = v_mid0 and v_ask1 = v_ask0 and v_bid1 = v_bid0 then f_mid_still := true; end if;

    -- (f) AND IT IS SPENT BY THE TRADE. Through cmd.do_buy, the real verb at the real price: the
    --     bargain must be gone afterwards while the day's attempt count still stands.
    select ducats into v_purse0 from public.players where id = v_player;
    perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_good::text, 'qty', 10));
    select ducats into v_purse1 from public.players where id = v_player;
    if public.haggle_concession(v_player, v_port, v_good) = 0
       and v_purse1 < v_purse0
       and (select attempts from public.haggle_daily
             where player_id = v_player and port_id = v_port
               and good_id = v_good and game_day = v_day) > 0 then
      f_spent := true;
    end if;

    -- (g) THE FLOOR FIRES ON A REAL FLEET. Today's seeded roster only reaches a 10 per cent
    --     purser (0015:354-358), which is NOT enough to drive the stack under the floor — so the
    --     probe sets its own precondition and authors a purser at the cap the schema already
    --     permits (officers.bonus_pct <= 25). Everything is then stacked to its maximum and the
    --     executed spread must land exactly ON the floor and STRICTLY ABOVE the naive product,
    --     which is what proves the floor did the work rather than the arithmetic.
    delete from public.haggle_daily where player_id = v_player;
    insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession)
    values (v_player, v_port, v_good, v_day, 1, 1, public.wc_num('haggle_concession_max'));

    insert into public.officers (code, name, specialty, bonus_pct, wage_ducats, blurb)
    values ('PROBE0022', 'A purser at the cap', 'PURSER',
            public.wc_num('officer_bonus_cap_pct'), 1,
            'Exists for the length of one rolled-back probe, to drive the stack onto the floor.')
    returning id into v_officer;
    insert into public.player_officers (player_id, officer_id, fleet_id)
    values (v_player, v_officer, v_fleet);

    v_floor      := v_pub * public.wc_num('haggle_spread_floor_frac');
    v_eff        := world.spread_effective(v_port, v_good, v_fleet);
    v_stack_real := v_pub * (1 - public.fleet_officer_bonus(v_fleet, 'PURSER'))
                          * (1 - public.wc_num('haggle_concession_max'));
    if v_eff = v_floor and v_eff > v_stack_real then f_floor := true; end if;

    -- (h) THE PURSER AND THE BARGAIN COMPOSE AND DO NOT DOUBLE-COUNT. With the floor lifted out of
    --     the way — again a precondition this block sets — the executed spread must be the PRODUCT
    --     of the two factors, which is strictly MORE than subtracting their sum would have given.
    update public.world_config set value = to_jsonb(0.0) where key = 'haggle_spread_floor_frac';
    v_eff := world.spread_effective(v_port, v_good, v_fleet);
    if v_eff = v_stack_real
       and v_eff > v_pub * (1 - public.fleet_officer_bonus(v_fleet, 'PURSER')
                              - public.wc_num('haggle_concession_max')) then
      f_compose := true;
    end if;

    -- (i) THE SKILL IS READ, BY EXACTLY WHAT ITS OWN AUTHORITY SAYS IT IS WORTH — not merely
    --     "the odds went up".
    delete from public.haggle_daily where player_id = v_player;
    update public.world_config set value = to_jsonb(0.45) where key = 'haggle_base_success';
    update public.world_config set value = to_jsonb(0.85) where key = 'haggle_success_max';
    v_odds0 := public.haggle_odds(v_player, v_port, v_good);
    select id into v_skill from public.skills where code = 'HAGGLING';
    insert into public.player_skills (player_id, skill_id, level) values (v_player, v_skill, 3)
    on conflict (player_id, skill_id) do update set level = 3;
    if public.haggle_odds(v_player, v_port, v_good)
         = round(v_odds0 + public.player_skill_bonus(v_player, 'SPREAD'), 4)
       and public.player_skill_bonus(v_player, 'SPREAD') > 0
       and (world.skills()->'effects_read') ? 'SPREAD' then
      f_reads := true;
    end if;

    -- (j) AND THE PANEL CANNOT PROMISE WHAT THE VERB WILL NOT DO: every figure world.haggle_state
    --     serves must come from the authority cmd.haggle rolls against.
    v_state := world.haggle_state(v_fleet, v_good);
    if (v_state->>'next_odds')::numeric is distinct from public.haggle_odds(v_player, v_port, v_good)
       or (v_state->>'attempts_max')::int is distinct from public.wc_int('haggle_attempts_per_day')
       or (v_state->>'attempts_left')::int is distinct from public.wc_int('haggle_attempts_per_day')
       or (v_state->>'concession')::numeric is distinct from public.haggle_concession(v_player, v_port, v_good)
       or (v_state->>'spread_published')::numeric is distinct from round(world.spread(v_port), 6) then
      f_reads := false;
    end if;

    raise exception '__PROBE_ROLLBACK_0022__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0022__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survived it, because plpgsql variables are not
  --    transactional. Assert on them now. ────────────────────────────────────────────────────────

  if not f_noop then
    raise exception '0022 self-assert FAIL: % of % pre-image quote(s) changed for a house with no bargain and no purser. Haggling is OPT-IN and this file was not allowed to move the economy of anyone who never uses it', v_drift, v_pre_rows;
  end if;
  if not f_reachable then
    raise exception '0022 self-assert FAIL: the knobs put the maximum stack at % and the floor at %, so the floor can never fire and is decoration', v_stack_cap, public.wc_num('haggle_spread_floor_frac');
  end if;
  if not f_predicted then
    raise exception '0022 self-assert FAIL: an outcome did not match the draw voyage.rng predicts for its key, or the attempt index did not advance — the roll is not the deterministic function claimed and a retry could re-roll it';
  end if;
  if not f_finite then
    raise exception '0022 self-assert FAIL: the % + 1 th attempt in one day was not refused with E_HAGGLE_SPENT and at least two fixes', public.wc_int('haggle_attempts_per_day');
  end if;
  if not f_harden then
    raise exception '0022 self-assert FAIL: the counter did not reach % across wins and refusals alike, or a refusal did not harden the next odds by exactly haggle_hardening_per_fail', public.wc_int('haggle_attempts_per_day');
  end if;
  if not f_moves then
    raise exception '0022 self-assert FAIL: a won bargain did not shave the executed spread by exactly one step — concession %, published spread %, executed %, 20 tun quote % -> %', v_conc, v_pub, v_eff_win, v_total0, v_total1;
  end if;
  if not f_mid_still then
    raise exception '0022 self-assert FAIL: haggling moved the PUBLISHED price — mid % -> %, ask % -> %, bid % -> %. The mid is the world''s and a negotiation may never reach it', v_mid0, v_mid1, v_ask0, v_ask1, v_bid0, v_bid1;
  end if;
  if not f_spent then
    raise exception '0022 self-assert FAIL: the bargain survived the trade that was supposed to spend it, or that trade moved no money';
  end if;
  if not f_floor then
    raise exception '0022 self-assert FAIL: with a purser at the cap and a bargain at the cap the executed spread read % against a floor of % and a naive product of %; the floor did not fire', v_eff, v_floor, v_stack_real;
  end if;
  if not f_compose then
    raise exception '0022 self-assert FAIL: the purser and the bargain do not compose multiplicatively; one of them is being summed and the two are double-counting';
  end if;
  if not f_reads then
    raise exception '0022 self-assert FAIL: studying HAGGLING did not move the odds by exactly what public.player_skill_bonus says it is worth, or world.skills() still reports SPREAD unread, or world.haggle_state disagrees with the authorities cmd.haggle rolls against';
  end if;

  -- The rollback really rolled back. NOT "the tables are empty" — this chain deploys onto a live
  -- world with real houses in it — but "this probe left nothing of its own behind", knobs and the
  -- officer it authored included.
  select count(*) into v_left from public.players where auth_uid = c_probe;
  if v_left <> 0 then
    raise exception '0022 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  select count(*) into v_left from public.haggle_daily;
  if v_left <> 0 then
    raise exception '0022 self-assert FAIL: % bargain row(s) were left committed by the probe', v_left;
  end if;
  select count(*) into v_left from public.officers where code = 'PROBE0022';
  if v_left <> 0 then
    raise exception '0022 self-assert FAIL: the probe left its synthetic purser in the world';
  end if;
  if public.wc_num('haggle_base_success') <> 0.45
     or public.wc_num('haggle_spread_floor_frac') <> 0.55
     or public.wc_num('haggle_success_max') <> 0.85 then
    raise exception '0022 self-assert FAIL: the probe left a knob moved — base %, floor %, max %',
      public.wc_num('haggle_base_success'), public.wc_num('haggle_spread_floor_frac'), public.wc_num('haggle_success_max');
  end if;

  -- POSTURE. Exactly two new client entry points were granted and nothing else was: the internal
  -- readings must be unreachable, every catalogued entry point must resolve, and both halves of
  -- the lockdown must still read zero.
  if has_function_privilege('authenticated', 'cmd.haggle(uuid,uuid,text)', 'execute')
     and has_function_privilege('authenticated', 'world.haggle_state(uuid,uuid)', 'execute')
     and not has_function_privilege('anon', 'cmd.haggle(uuid,uuid,text)', 'execute')
     and not has_function_privilege('anon', 'world.haggle_state(uuid,uuid)', 'execute')
     and not has_function_privilege('anon', 'public.haggle_odds(uuid,uuid,uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public.haggle_odds(uuid,uuid,uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public.haggle_concession(uuid,uuid,uuid)', 'execute')
     and not has_function_privilege('authenticated', 'world.spread_effective(uuid,uuid,uuid)', 'execute')
     -- world.quote is NOT a client entry point and has not been one since 0018's sweep revoked
     -- EXECUTE from every SECURITY DEFINER function and handed it back only to the catalogued
     -- list — 0017:410's grant of it was superseded that same day. Measured here rather than
     -- assumed: this file's `create or replace` must not have quietly restored it either.
     and not has_function_privilege('authenticated', 'world.quote(uuid,uuid,numeric,text,numeric,uuid)', 'execute')
     and not has_function_privilege('anon', 'world.quote(uuid,uuid,numeric,text,numeric,uuid)', 'execute')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0022 self-assert FAIL: the two new entry points are not exactly granted to authenticated and denied to anon, or an internal reading leaked to a client, or a catalogued entry point does not resolve, or a client write/execute grant appeared';
  end if;

  raise notice '0022 self-assert ok: haggling moves the PORT''S CUT and never the world''s price — with a bargain open, the mid, ask and bid world.price() publishes were UNCHANGED (% / % / %) while the executed spread fell from % to % (exactly one step of %) and a 20 tun quote fell from % to % d.; the unhaggled economy is BYTE-IDENTICAL, proven against a pre-image of % real quotes taken through the old world.quote before it was replaced, of which % drifted; the roll is a pure function of (player, port, good, game-day, attempt, secret) — every attempt of the day was PREDICTED from voyage.rng before it was played and every one matched, attempt % + 1 was refused E_HAGGLE_SPENT, and because the attempt is written BEFORE the draw a retry costs a chance and re-rolls nothing; a refusal hardens the next odds by % and never the price; the bargain was SPENT by the trade that used it while the day''s attempts stood; the purser and the bargain COMPOSE multiplicatively rather than summing; the floor of % of the published spread FIRED on a fleet carrying a purser at the % per cent cap with a bargain at the cap, holding it at % where the naive product would have given % (today''s two seeded PURSERs only reach 10 per cent, so this is a guardrail on the knob and costs the current game nothing); studying HAGGLING moved the odds by exactly public.player_skill_bonus and world.skills() now reports SPREAD read; the probe left 0 houses, 0 bargains, 0 synthetic officers and 0 moved knobs; and the 2 new entry points are granted to authenticated, denied to anon, with world.spread_effective, world.quote and both internal readings unreachable by any client, 0 client write grants and 0 client-executable writers',
    v_mid0, v_ask0, v_bid0,
    v_pub, v_pub * (1 - public.wc_num('haggle_concession_step')), public.wc_num('haggle_concession_step'),
    v_total0, v_total1,
    v_pre_rows, v_drift,
    public.wc_int('haggle_attempts_per_day'),
    public.wc_num('haggle_hardening_per_fail'),
    public.wc_num('haggle_spread_floor_frac'),
    public.wc_num('officer_bonus_cap_pct'),
    v_floor, v_stack_real;
end $$;

drop table quote_before_0022;

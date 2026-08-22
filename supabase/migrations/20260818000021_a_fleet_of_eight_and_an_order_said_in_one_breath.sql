-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0021 — A FLEET OF EIGHT, AND AN ORDER SAID IN ONE BREATH
--        `ship_max` becomes 8 so the design's own fleet can be crewed — and the cap that was
--        supposed to hold it, `fleet_ship_max`, stops being a knob nothing reads.
--        Plus: every `help` string on the COMMAND cards becomes a single line a captain would say.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ─────────────────────────────────────────────────────────────────────────
--   "MAKE An order - Command. too much unncessary info. So is Sail, Sell, Hire etc. Too long
--    explanation. this is a game, make it so. … This game fleet will be comprised with 8 ships."
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PART 1 — A FLEET OF EIGHT
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
--   0001:164  ('ship_max', 4)        "DESIGN K.1: V0 allows 4 ships in total."
--   0001:165  ('fleet_ship_max', 8)  "DESIGN C.4: a fleet is 1-8 ships with exactly one flagship."
--   docs/DESIGN.md:317               "A fleet is 1-8 ships with exactly one flagship."
--   docs/DESIGN.md:1291  (§K.1 V0)   "2 fleets, 4 ships max."
--
-- The design already wanted eight. What stopped it was the house-wide four. The owner has now
-- said eight out loud, so §K.1's V0 line is superseded by his word and §C.4's per-fleet 1-8 is
-- what the game actually enforces. §C.4's Company-Level table is NOT in force: rank and titles are
-- listed under "Not in V0" (docs/DESIGN.md:1295), so nothing gates the cap by level yet.
--
-- ── AND THE DEFECT THAT RAISING IT EXPOSED: A RULE WITH NO AUTHOR ───────────────────────────────
-- Measured on this chain, 2026-08-22: `fleet_ship_max` is read by NOTHING. Not a function, not a
-- trigger, not a constraint, not `world.snapshot()`'s config allow-list (0019:655-668), not the
-- client. It has been a sentence in a description column since 0001. `ship_max` is barely better:
-- it is SERVED (0019:659) and PRINTED as a hard cap the player is asked to plan around —
--
--     src/features/rank/RankScreen.tsx:155-161   max={config.ship_max} … "every berth taken"
--     src/features/fleets/FleetsScreen.tsx:130   {counts.ships}/{config.ship_max} ships
--
-- — while no server rule holds it. A cap the player is shown and the server does not keep is not a
-- rule, it is a caption. `fleet_max` (0001:163) is in exactly the same position.
--
-- Three knobs, three captions, nought enforcers. That is not "a gap"; it is the same defect three
-- times, which docs/NO_SPAGHETTI.md §1 says to fold in the turn it is found rather than file. So
-- this migration gives the whole class ONE author:
--
--     public.assert_house_caps(player, fleet)   THE one reading of "may this house hold another
--                                               hull, or another fleet?" — all three knobs, one
--                                               function, one message per breach.
--     public.tg_house_caps()                    the trigger body, on `ships` and on `fleets`.
--
-- It is enforced on the TABLE rather than in a verb, deliberately and for the reason 0004 gives
-- for the flagship index (0004:33): "a partial UNIQUE index, not a check in application code."
-- There is no verb that adds a hull today. When `BUILD` or a shipyard arrives it must not be free
-- to re-derive the cap, and on the table it cannot: whatever writes `ships` inherits the rule.
--
-- ── WHAT THE REST OF THE CHAIN DOES AT EIGHT HULLS ──────────────────────────────────────────────
-- Every per-fleet fold is an aggregate over `where fleet_id = p_fleet`, so eight is arithmetic, not
-- a new case. Measured here, on eight Barcas at rest (rated 5.00 kn, hold 60, crew 8):
--
--   voyage.fleet_speed  (0015:138)  min(ship_speed) x M_formation x (1 + navigator)
--                                   4.9125 -> x0.95 -> 4.6669.  DESIGN B.3's 7+ BAND, WHICH HAS
--                                   NEVER BEEN REACHABLE BEFORE TODAY, because four was the cap
--                                   and the band opens at seven. It is exercised below at 3, 6
--                                   and 8 hulls, and the three answers must differ.
--   voyage.endurance_days (0016:122) min over hulls — 15.000 days at one hull and 15.000 at eight.
--                                   Stores are pooled per hull, so range does NOT grow with the
--                                   fleet. Asserted as EQUAL, and asserted NOT to be eight times.
--   public.fleet_free_hold (0017:183) sum over hulls — 55.800 -> 446.400, exactly 8x.
--   crew / berths (0007:632 do_hire) sum of (crew_max - crew) over hulls; 8 x 8 = 64 aboard.
--   public.fleet_buy_capacity (0017:422) reads fleet_free_hold, so the ceiling the quay offers
--                                   grows with the fleet and is still bounded by stock, the daily
--                                   cap and the purse. Nothing here counts hulls.
--
-- ── THE BALANCE PROOFS DO NOT MOVE — AND THE MEASUREMENT SAYS SO HONESTLY ───────────────────────
-- `new_house` (0004:275) opens with ONE Barca, and this file does not touch it. scripts/db/proofs/
-- 04_first_session.sql and 05_first_voyage_balance.sql therefore sail the same single hull they
-- always did. Nothing here touches a price, a good, a leg or a hull.
--
-- Their headline figures DO differ between any two runs, and a report that read one run before and
-- one run after would have called that a balance change. It is not. Measured on this machine
-- 2026-08-22 (PGlite 0.5.5 / PostgreSQL 18.3), four consecutive runs of the UNCHANGED proof suite:
--
--     with 0021     FIRST_SESSION_HOME_RICHER  2.36% · 17.73%     median  11.9% · 13.2%
--     without 0021  FIRST_SESSION_HOME_RICHER 14.25% ·  4.57%     median   8.9% · 10.0%
--
-- The spread WITHOUT this file is as wide as the spread WITH it, because the world is priced
-- against `now()` (world.game_day, 0005:283) and both proofs DISCOVER their itinerary rather than
-- naming one — which is the whole point of docs/HISTORY.md:193-196. The figure those markers print
-- is a sample, not a pin. The only balance number either file actually PINS is
-- BALANCE_MEDIAN_IN_BAND's band of 4.0-16.0 per cent, and it held on all four runs. 33/33 markers
-- on all four. No balance figure moved.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PART 2 — AN ORDER SAID IN ONE BREATH
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── SUPERSEDES 0020 — AND ONLY ITS PROSE, AGAIN ─────────────────────────────────────────────────
-- 0020 took the schema words out of `cmd.verb_schema()`'s help. It did not make it SHORT. Measured
-- on the live chain today, in characters: SAIL 153 · BUY 227 · SELL 242 · PROVISION 158 ·
-- HIRE 113 · REPAIR 147 · CANCEL 87 · CLEAR 85. src/features/command/OrderComposer.tsx:146 prints
-- that onto a button, under `line-clamp-2` — so on BUY and SELL the player is shown a paragraph
-- with its last two thirds cut off. The owner is right: it is a game, and a verb card is a label.
--
-- Every `help` is re-cut to ONE imperative line of 30-60 characters, and the length band is
-- asserted, not aimed at.
--
-- ── WHERE THE FINE PRINT WENT: A SECOND SERVED FIELD, `note` ────────────────────────────────────
-- Two of those sentences carry mechanics a trader must eventually know and cannot find anywhere
-- else in the game: that a large order walks a stepped book ten tuns at a time, and that ALL/HALF
-- are counted when the order RUNS rather than when it is made. Deleting them would make the copy
-- short by making the game unlearnable, so they are not deleted — they MOVE, to a `note` key on
-- the same verb, served by the same one authority. The Command tab can put it behind an info dot;
-- until it does, the fact is still in the world and still in one place. Nothing else gained a
-- second author: `help` and `note` are two halves of one string, not two answers to one question.
--
-- **FOR src/**: `VerbSpec` (src/lib/rpc/types.ts:129-133) gains an optional `note?: string`, and
-- OrderComposer's verb card is the surface for it. Nothing breaks without that edit — an extra
-- jsonb key is inert to a TypeScript interface at runtime, and the card keeps printing `help`.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   * It does not add `fleet_ship_max` to `world.snapshot()`'s config allow-list. No client
--     surface can add a hull, so a cap displayed there would be a control for a feature that does
--     not exist. It goes in with the verb that needs it.
--   * It does not touch `voyage.fleet_speed`, `voyage.endurance_days`, `public.fleet_free_hold` or
--     `public.fleet_buy_capacity`. They already fold N hulls correctly; this file MEASURES them at
--     eight and would fail if they did not. Re-cutting a function to prove a claim about it is how
--     a slice stops being one thing.
--   * It does not touch `cmd.fixes()` or any refusal sentence, for the reason 0020 gives.
--   * It issues no GRANT and no REVOKE. Since 0018:177 retuned the default privileges, a function
--     created here is executable by nobody; that is READ BACK below rather than assumed.
--
-- Depends ONLY on: 0001 (world_config, wc_int, client_write_grants), 0004 (players/fleets/ships,
--                  new_house), 0006/0015/0016/0017 (the folds this file measures), 0008/0020
--                  (cmd.verb_schema), 0018 (the EXECUTE lockdown).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGES, captured before anything is replaced, so both no-ops can be PROVEN rather than
-- claimed. Scaffolding for the asserts at the foot of this file; both are dropped there.
create temporary table verb_schema_before_0021 as
  select cmd.verb_schema() as js;

create temporary table caps_before_0021 as
  select key, value from public.world_config
   where key in ('ship_max', 'fleet_max', 'fleet_ship_max');

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PART 1 — THE KNOB, AND THE AUTHORITY THAT FINALLY READS IT
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config
   set value       = to_jsonb(8),
       description = 'DESIGN C.4 + the owner, 2026-08-22: a house may hold 8 ships, which is what '
                     'it takes to crew ONE fleet to the 1-8 the design has always specified. '
                     'Supersedes 0001:164 and DESIGN K.1''s "4 ships max". ENFORCED by '
                     'public.assert_house_caps (0021), not merely displayed.',
       updated_at  = now()
 where key = 'ship_max';

-- The other two descriptions are corrected in the same breath, because until today all three said
-- what the game did NOT do. A description that lies is how `fleet_ship_max` went unread for
-- twenty migrations without anybody noticing.
update public.world_config
   set description = 'DESIGN C.4: a fleet is 1-8 ships with exactly one flagship. ENFORCED by '
                     'public.assert_house_caps (0021); before that it was read by nothing at all.',
       updated_at  = now()
 where key = 'fleet_ship_max';

update public.world_config
   set description = 'DESIGN K.1: V0 allows 2 fleets. ENFORCED by public.assert_house_caps (0021).',
       updated_at  = now()
 where key = 'fleet_max';

-- ── THE ONE READING OF "MAY THIS HOUSE HOLD ANOTHER HULL, OR ANOTHER FLEET?" ────────────────────
create or replace function public.assert_house_caps(p_player uuid, p_fleet uuid default null)
returns void
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_ships    int;
  v_fleets   int;
  v_in_fleet int;
begin
  if p_player is null then
    return;   -- nothing to count; the FK would have refused the row before this ran
  end if;

  -- The HOUSE-WIDE hull cap. Checked first, because it is the one the player is shown
  -- (RankScreen "every berth taken") and therefore the one whose refusal he can already read.
  select count(*) into v_ships from public.ships where player_id = p_player;
  if v_ships > public.wc_int('ship_max') then
    raise exception 'E_SHIP_MAX: the house may hold % ship(s) and this would make %',
      public.wc_int('ship_max'), v_ships using errcode = 'P0001';
  end if;

  select count(*) into v_fleets from public.fleets where player_id = p_player;
  if v_fleets > public.wc_int('fleet_max') then
    raise exception 'E_FLEET_MAX: the house may keep % fleet(s) and this would make %',
      public.wc_int('fleet_max'), v_fleets using errcode = 'P0001';
  end if;

  -- The PER-FLEET cap — DESIGN C.4's 1-8, which until this file nothing anywhere read.
  if p_fleet is not null then
    select count(*) into v_in_fleet from public.ships where fleet_id = p_fleet;
    if v_in_fleet > public.wc_int('fleet_ship_max') then
      raise exception 'E_FLEET_SHIP_MAX: a fleet sails % ship(s) at most and this would make %',
        public.wc_int('fleet_ship_max'), v_in_fleet using errcode = 'P0001';
    end if;
  end if;
end $$;

comment on function public.assert_house_caps(uuid, uuid) is
  'THE ONE statement of the structural caps: ship_max, fleet_max and fleet_ship_max, read from '
  'world_config through public.wc_int and never re-derived. Attached to public.ships and '
  'public.fleets by public.tg_house_caps, so any future writer — a shipyard, a SPLIT, a MERGE — '
  'inherits the rule instead of copying it. Raises P0001 with an E_* code the command layer '
  'already knows how to surface.';

create or replace function public.tg_house_caps()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- One body, two tables. `fleet_id` exists on ships and not on fleets, so the fleet argument is
  -- taken from the row where there is one and from the row's own id where the row IS the fleet.
  if tg_table_name = 'ships' then
    perform public.assert_house_caps(new.player_id, new.fleet_id);
  else
    perform public.assert_house_caps(new.player_id, null);
  end if;
  return null;
end $$;

comment on function public.tg_house_caps() is
  'The trigger body for public.assert_house_caps. AFTER INSERT (and after a ship changes hands or '
  'fleets), so the count it takes is the committed one. It decides nothing itself.';

create or replace trigger ships_respect_house_caps
  after insert or update of fleet_id, player_id on public.ships
  for each row execute function public.tg_house_caps();

create or replace trigger fleets_respect_house_caps
  after insert or update of player_id on public.fleets
  for each row execute function public.tg_house_caps();

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PART 2 — THE VERBS, IN ONE BREATH EACH
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function cmd.verb_schema()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Served to the tap-builder so the pad and any other surface share ONE grammar (DESIGN F.4).
  -- Tapping through these arguments assembles exactly the string cmd.parse reads.
  --
  -- 0021: `help` is the LABEL on the verb card — one imperative line, 30-60 characters, the thing
  -- a master would say. `note` is the fine print the same card can reveal, and it is where every
  -- mechanic 0020's longer help carried has gone. Neither ever names a table, a column, a
  -- migration or a section of the design document, and neither describes typing, because there
  -- is none.
  select '[
    {"verb":"SAIL","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"dest","type":"port","required":true,"keyword":"TO"},
       {"name":"via","type":"port","required":false,"repeat":true,"keyword":"VIA"}],
     "help":"Put to sea and make for another port.",
     "note":"She follows the sea road, which runs longer than the line on the map. Name ports to call at on the way and she puts in at each in turn."},
    {"verb":"BUY","args":[
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"qty","required":true},
       {"name":"limit","type":"price","required":false,"keyword":"AT","op":"<="}],
     "help":"Take cargo aboard at the price on the quay.",
     "note":"A large order walks the book ten tuns at a time, and each ten costs a little more than the last, so the figure shown is the price of the first ten. Name a top price and she takes only what she can get under it."},
    {"verb":"SELL","args":[
       {"name":"good","type":"good","required":true},
       {"name":"qty","type":"qty","required":true},
       {"name":"limit","type":"price","required":false,"keyword":"AT","op":">="}],
     "help":"Sell out of the hold at the price offered.",
     "note":"The book steps the other way: each ten tuns fetches a little less than the last. ALL and HALF are counted when she reaches the quay, so whatever is aboard on arrival is what goes ashore. Name a floor price and she sells only above it."},
    {"verb":"PROVISION","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"mode","type":"enum","values":["FULL","DAYS"],"required":false,"default":"FULL"},
       {"name":"days","type":"number","required":false}],
     "help":"Take on water and food for the days ahead.",
     "note":"FULL fills her stores to the brim. Ask for a number of days instead and she carries only that, leaving the rest of the hold for cargo."},
    {"verb":"HIRE","args":[
       {"name":"count","type":"number","required":true},
       {"name":"fleet","type":"fleet","required":false}],
     "help":"Sign on hands from the idle men in port.",
     "note":"A port holds only so many idle men. Once they are taken, the rest want two and a half times the wage."},
    {"verb":"REPAIR","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"to_pct","type":"number","required":false,"keyword":"TO","default":100}],
     "help":"Put her in the yard and mend the hull.",
     "note":"It takes days at anchor and she cannot sail until the work is done. Ask for less than sound and she is out sooner and cheaper."},
    {"verb":"CANCEL","args":[
       {"name":"index","type":"number","required":false}],
     "help":"Strike one order out of the queue.",
     "note":"Say which order, or leave it and the next one due to run is the one struck."},
    {"verb":"CLEAR","args":[
       {"name":"all","type":"flag","required":false}],
     "help":"Strike every order still waiting.",
     "note":"CLEAR ALL also turns a fleet already at sea for home."}
  ]'::jsonb
$$;

comment on function cmd.verb_schema() is
  'THE grammar, served to the tap-builder. Supersedes 0020 in its PROSE only — the verbs, '
  'arguments, types, keywords and defaults are byte-identical, which 0021 proves by comparing the '
  'pre-image with `help` and `note` stripped from both. `help` is the one-line label the Command '
  'tab prints on a verb card (30-60 characters); `note` is the fine print that card can reveal, '
  'and it holds every mechanic 0020''s longer help used to carry.';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  -- Part 1
  c_probe_auth constant uuid := '00000000-0021-4000-8000-000000000021';
  v_old_ship_max int;
  v_new_ship_max int := public.wc_int('ship_max');
  v_fleet_cap    int := public.wc_int('fleet_ship_max');
  v_player       uuid;
  v_fleet_a      uuid;
  v_fleet_b      uuid;
  v_class        public.ship_classes%rowtype;
  i              int;
  v_hulls        int;
  v_min_kn       numeric;
  v_kn_8         numeric;
  v_kn_6         numeric;
  v_kn_3         numeric;
  v_end_1        numeric;
  v_end_8        numeric;
  v_hold_1       numeric;
  v_hold_8       numeric;
  v_crew_8       int;
  v_err          text;
  v_left         int;
  -- findings, recorded inside the throwaway subtransaction and read after it is gone
  f_old_cap_bit  boolean := false;
  f_eight_ok     boolean := false;
  f_speed_bands  boolean := false;
  f_folds        boolean := false;
  f_house_cap    boolean := false;
  f_fleet_cap    boolean := false;
  f_fleet_max    boolean := false;
  f_not_blanket  boolean := false;
  -- Part 2
  v_before   jsonb;
  v_after    jsonb := cmd.verb_schema();
  v_g_before jsonb;
  v_g_after  jsonb;
  v_n        int;
  v_bad      text;
  v_changed  int;
  v_short    int;
  v_long     int;
  v_jargon   constant text[] := array[
    'leg graph', 'authored', 'jsonb', 'uuid', 'schema', 'migration', 'rpc',
    'port_goods', 'null', 'boolean', 'enum ', 'typed', 'type it', 'keyboard'];
  w          text;
  f_grammar  boolean := false;
  f_len      boolean := false;
  f_prose    boolean := false;
  f_kept     boolean := false;
  f_grant    boolean := false;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- PART 1 — the knob moved, and something now READS it
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select (value)::text::int into v_old_ship_max from caps_before_0021 where key = 'ship_max';
  if v_old_ship_max is null then
    raise exception '0021 self-assert FAIL: the pre-image of ship_max was not captured, so "it was raised" would be comparing nothing with nothing';
  end if;

  select * into v_class from public.ship_classes where code = 'barca';
  if v_class.id is null then
    raise exception '0021 self-assert FAIL: no barca class to probe with; every measurement below would be over an empty fleet';
  end if;

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────
    v_player := public.new_house(c_probe_auth, 'Casa Oitava 0021', 'PRT');
    select id into v_fleet_a from public.fleets where player_id = v_player;

    -- (1) POSITIVE CONTROL ON THE KNOB ITSELF. Put ship_max back where 0001 left it — read from
    --     the pre-image, not written as a literal — and the FIFTH hull must be refused. If this
    --     does not bite, the cap is not being read and everything below is decoration.
    update public.world_config set value = to_jsonb(v_old_ship_max) where key = 'ship_max';
    for i in 2 .. v_old_ship_max loop
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_a, v_class.id, 'Probe ' || i, v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
    end loop;
    begin
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_a, v_class.id, 'Probe over', v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
    exception when others then
      if position('E_SHIP_MAX' in sqlerrm) > 0 then f_old_cap_bit := true; end if;
    end;

    -- (2) AND AT EIGHT IT LETS HER THROUGH. This is the change the owner asked for.
    update public.world_config set value = to_jsonb(v_new_ship_max) where key = 'ship_max';
    for i in (v_old_ship_max + 1) .. 8 loop
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_a, v_class.id, 'Probe ' || i, v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
    end loop;
    select count(*) into v_hulls from public.ships where fleet_id = v_fleet_a;
    if v_hulls = 8 then f_eight_ok := true; end if;

    -- (3) DESIGN B.3's FORMATION BANDS, INCLUDING THE 7+ ONE THAT FOUR SHIPS COULD NEVER REACH.
    --     The expected figure is recomputed from the slowest hull and the band, never pinned.
    select min(voyage.ship_speed(s.id)) into v_min_kn
      from public.ships s where s.fleet_id = v_fleet_a;
    v_kn_8   := voyage.fleet_speed(v_fleet_a);
    v_end_8  := voyage.endurance_days(v_fleet_a);
    v_hold_8 := public.fleet_free_hold(v_fleet_a);
    select sum(crew) into v_crew_8 from public.ships where fleet_id = v_fleet_a;

    delete from public.ships where id in
      (select id from public.ships where fleet_id = v_fleet_a and not is_flagship
        order by name desc limit 2);
    v_kn_6 := voyage.fleet_speed(v_fleet_a);

    delete from public.ships where id in
      (select id from public.ships where fleet_id = v_fleet_a and not is_flagship
        order by name desc limit 3);
    v_kn_3   := voyage.fleet_speed(v_fleet_a);

    delete from public.ships where fleet_id = v_fleet_a and not is_flagship;
    v_end_1  := voyage.endurance_days(v_fleet_a);
    v_hold_1 := public.fleet_free_hold(v_fleet_a);

    if v_kn_8 = round(v_min_kn * 0.95, 4)
       and v_kn_6 = round(v_min_kn * 0.98, 4)
       and v_kn_3 = round(v_min_kn * 1.00, 4)
       and v_kn_8 < v_kn_6 and v_kn_6 < v_kn_3 then
      f_speed_bands := true;
    end if;

    -- (4) THE FOLDS. Hold is a SUM and must be exactly eight times one hull; endurance is a MIN
    --     and must NOT move at all — stores are pooled per hull (DESIGN C.5), and a fleet that
    --     sailed eight times as far for adding hulls would be a different game.
    if v_hold_8 = v_hold_1 * 8
       and v_end_8 = v_end_1
       and v_end_8 <> v_end_1 * 8
       and v_crew_8 = v_class.crew_required * 8 then
      f_folds := true;
    end if;

    -- (5) THE HOUSE CAP, ISOLATED. Refill fleet A to eight, open the second fleet the world
    --     allows, and put the NINTH hull there: the fleet cap cannot be what refuses it.
    for i in 2 .. 8 loop
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_a, v_class.id, 'Probe ' || i, v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
    end loop;
    insert into public.fleets (player_id, name, status, port_id)
    select v_player, 'Segunda 0021', 'DOCKED', f.port_id
      from public.fleets f where f.id = v_fleet_a
    returning id into v_fleet_b;

    begin
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_b, v_class.id, 'Probe nine', v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
    exception when others then
      v_err := sqlerrm;
      if position('E_SHIP_MAX' in v_err) > 0 then f_house_cap := true; end if;
    end;

    -- (6) THE FLEET CAP, ISOLATED. Lift the house cap clear out of the way — the proof sets its
    --     own precondition rather than borrowing one — and the ninth hull in ONE fleet must still
    --     be refused, this time by DESIGN C.4. This is the assert that turns fleet_ship_max from
    --     a sentence in a description column into a rule.
    update public.world_config set value = to_jsonb(v_fleet_cap * 10) where key = 'ship_max';
    begin
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_a, v_class.id, 'Probe nine', v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
    exception when others then
      v_err := sqlerrm;
      if position('E_FLEET_SHIP_MAX' in v_err) > 0 then f_fleet_cap := true; end if;
    end;

    -- ANTI-PROOF: with the house cap out of the way that same hull IS accepted into the second
    -- fleet. Without this, (6) could be passing on any refusal at all.
    begin
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                                water_t, food_t, store_ratio, is_flagship)
      values (v_player, v_fleet_b, v_class.id, 'Probe nine', v_class.durability,
              v_class.crew_required, 2.400, 1.800, public.wc_num('store_ratio_default'), false);
      f_not_blanket := true;
    exception when others then
      f_not_blanket := false;
    end;

    -- (7) AND THE THIRD FLEET, which the same authority refuses on the same reading.
    begin
      insert into public.fleets (player_id, name, status, port_id)
      select v_player, 'Terceira 0021', 'DOCKED', f.port_id
        from public.fleets f where f.id = v_fleet_a;
    exception when others then
      v_err := sqlerrm;
      if position('E_FLEET_MAX' in v_err) > 0 then f_fleet_max := true; end if;
    end;

    raise exception '__PROBE_ROLLBACK_0021__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0021__' then raise; end if;
  end;
  -- ── the subtransaction is gone; plpgsql variables are not transactional, so the findings
  --    survived it. Assert on them now. ────────────────────────────────────────────────────────

  if v_new_ship_max <> 8 then
    raise exception '0021 self-assert FAIL: ship_max reads % and the owner asked for 8', v_new_ship_max;
  end if;
  if v_old_ship_max = v_new_ship_max then
    raise exception '0021 self-assert FAIL: ship_max was already %, so this migration changed nothing and the controls below prove nothing', v_new_ship_max;
  end if;
  if not f_old_cap_bit then
    raise exception '0021 self-assert FAIL: with ship_max put back to % the % + 1 th hull was ACCEPTED — the knob is not being read, so raising it means nothing', v_old_ship_max, v_old_ship_max;
  end if;
  if not f_eight_ok then
    raise exception '0021 self-assert FAIL: eight hulls could not be gathered into one fleet (got %)', v_hulls;
  end if;
  if not f_speed_bands then
    raise exception '0021 self-assert FAIL: the formation bands do not hold — slowest hull % kn, fleet reads % at 8 (want %), % at 6 (want %), % at 3 (want %)',
      v_min_kn, v_kn_8, round(v_min_kn * 0.95, 4), v_kn_6, round(v_min_kn * 0.98, 4), v_kn_3, round(v_min_kn * 1.00, 4);
  end if;
  if not f_folds then
    raise exception '0021 self-assert FAIL: the per-fleet folds do not behave at 8 hulls — hold %/% (want 8x), endurance %/% (want equal), crew % (want %)',
      v_hold_8, v_hold_1, round(v_end_8, 3), round(v_end_1, 3), v_crew_8, v_class.crew_required * 8;
  end if;
  if not f_house_cap then
    raise exception '0021 self-assert FAIL: a ninth hull was accepted into a second fleet; ship_max is still only a caption';
  end if;
  if not f_fleet_cap then
    raise exception '0021 self-assert FAIL: with the house cap lifted, a ninth hull was accepted into ONE fleet; fleet_ship_max is still read by nothing';
  end if;
  if not f_not_blanket then
    raise exception '0021 self-assert FAIL: with the house cap lifted the trigger refused a legal hull as well, so the refusals above are a blanket and not a cap';
  end if;
  if not f_fleet_max then
    raise exception '0021 self-assert FAIL: a third fleet was accepted; fleet_max is still only a caption';
  end if;

  -- The rollback really rolled back. NOT "the tables are empty" — this chain deploys onto a live
  -- world with real houses in it — but "this probe left nothing of its own behind".
  select count(*) into v_left from public.players where auth_uid = c_probe_auth;
  if v_left <> 0 then
    raise exception '0021 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  if public.wc_int('ship_max') <> 8 then
    raise exception '0021 self-assert FAIL: the probe left ship_max at %, not 8', public.wc_int('ship_max');
  end if;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- PART 2 — the prose moved and the grammar did not
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select js into v_before from verb_schema_before_0021;
  if v_before is null then
    raise exception '0021 self-assert FAIL: the pre-image of cmd.verb_schema() was not captured, so the no-op below would be comparing nothing with nothing';
  end if;

  -- (a) THE GRAMMAR DID NOT MOVE. Strip BOTH prose keys from each side and require the rest to be
  --     EQUAL. This is the whole safety of the file: cmd.parse, the tap-builder and every queued
  --     order read these argument names, and a typo here breaks the only way into the game.
  select jsonb_agg((e - 'help') - 'note' order by ord) into v_g_before
    from jsonb_array_elements(v_before) with ordinality t(e, ord);
  select jsonb_agg((e - 'help') - 'note' order by ord) into v_g_after
    from jsonb_array_elements(v_after) with ordinality t(e, ord);
  if v_g_before = v_g_after then f_grammar := true; end if;

  -- (b) EIGHT VERBS, EACH WITH A LABEL INSIDE THE BAND AND A NOTE BEHIND IT. The band is the
  --     owner's complaint made checkable: 60 characters is about what fits on the card.
  select count(*) into v_n from jsonb_array_elements(v_after) e
   where e ? 'help' and e ? 'note'
     and length(e->>'help') between 30 and 60
     and length(e->>'note') >= 40;
  if v_n = jsonb_array_length(v_after) and v_n = 8 then f_len := true; end if;

  -- (c) EVERY LABEL ACTUALLY CHANGED, AND NOTHING IN EITHER FIELD TALKS TO A DEVELOPER. Both
  --     halves matter: a file that renamed nothing would pass the jargon sweep vacuously.
  select count(*) into v_changed
    from jsonb_array_elements(v_before) with ordinality b(eb, ord)
    join jsonb_array_elements(v_after)  with ordinality a(ea, ord2) on ord2 = ord
   where eb->>'help' is distinct from ea->>'help';
  v_bad := null;
  foreach w in array v_jargon loop
    select string_agg(format('%s: "%s"', e->>'verb', w), '; ') into v_bad
      from jsonb_array_elements(v_after) e
     where position(w in lower(coalesce(e->>'help', '') || ' ' || coalesce(e->>'note', ''))) > 0;
    exit when v_bad is not null;
  end loop;
  if v_changed = 8 and v_bad is null then f_prose := true; end if;

  -- (d) THE FINE PRINT WAS MOVED, NOT DELETED. Five mechanics that lived in 0020's help must now
  --     live in 0021's note — and each is required to have been in the PRE-IMAGE first, so this
  --     is a check that text migrated rather than a check that I typed some words just now.
  select count(*) into v_n
    from (values ('BUY', 'ten tuns'), ('SELL', 'ten tuns'), ('SELL', 'what goes ashore'),
                 ('PROVISION', 'FULL'), ('HIRE', 'two and a half'), ('CLEAR', 'CLEAR ALL')
         ) as m(verb, phrase)
   where position(m.phrase in
           (select e->>'help' from jsonb_array_elements(v_before) e where e->>'verb' = m.verb)) > 0
     and position(m.phrase in
           (select e->>'note' from jsonb_array_elements(v_after) e where e->>'verb' = m.verb)) > 0;
  if v_n = 6 then f_kept := true; end if;

  -- (e) `create or replace` keeps a function's ACL, and 0018 retuned the default privileges so a
  --     function created by THIS file is executable by nobody. Both are read back, never assumed.
  if has_function_privilege('authenticated', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('anon', 'cmd.verb_schema()', 'execute')
     and not has_function_privilege('anon', 'public.assert_house_caps(uuid,uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public.assert_house_caps(uuid,uuid)', 'execute')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0 then
    f_grant := true;
  end if;

  if not f_grammar then raise exception '0021 self-assert FAIL: the grammar changed. Before: % / After: %', v_g_before, v_g_after; end if;
  if not f_len     then raise exception '0021 self-assert FAIL: % of % verb(s) carry a help label of 30-60 characters AND a note; there must be 8 of 8', v_n, jsonb_array_length(v_after); end if;
  if not f_prose   then raise exception '0021 self-assert FAIL: % of 8 help string(s) changed and the jargon sweep found %', v_changed, coalesce(v_bad, 'nothing (so it proved nothing)'); end if;
  if not f_kept    then raise exception '0021 self-assert FAIL: only % of 6 mechanic(s) that 0020 stated in `help` can be found in 0021''s `note`; the copy got short by deleting the game', v_n; end if;
  if not f_grant   then raise exception '0021 self-assert FAIL: the re-cut moved cmd.verb_schema()''s grants, or the new cap authority is callable by a client, or a client write/execute grant appeared'; end if;

  select min(length(e->>'help')), max(length(e->>'help')) into v_short, v_long
    from jsonb_array_elements(v_after) e;

  raise notice '0021 self-assert ok: ship_max % -> %, and it is now READ — with the knob put back to % the % + 1 th hull was REFUSED (E_SHIP_MAX), and at % eight hulls gathered into one fleet; DESIGN C.4''s fleet_ship_max, which nothing in twenty migrations had ever read, REFUSED a ninth hull in one fleet with the house cap deliberately lifted out of the way, while that same hull was ACCEPTED into a second fleet, so it is a cap and not a blanket; fleet_max REFUSED a third fleet; DESIGN B.3''s 7+ formation band is exercised for the first time — slowest hull % kn gives % at 8 hulls, % at 6 and % at 3; the folds behave — free hold % tuns at eight against % at one (exactly 8x), endurance % days at eight and % at one (a MIN, so unmoved), % hands aboard; the probe house left 0 rows behind. And cmd.verb_schema() still serves the same 8 verbs whose arguments, types, keywords, defaults and order are BYTE-IDENTICAL to the pre-image with both prose keys stripped; all 8 help labels were rewritten to one line (% to % characters, was 85 to 242) and all 8 carry a note; 6 mechanics were proven to have MOVED from help into note rather than been deleted; a sweep of % developer word(s) found none in either field; and the re-cut kept its grants, with 0 client write grants and 0 client-executable writers',
    v_old_ship_max, v_new_ship_max, v_old_ship_max, v_old_ship_max, v_new_ship_max,
    v_min_kn, v_kn_8, v_kn_6, v_kn_3,
    v_hold_8, v_hold_1, round(v_end_8, 3), round(v_end_1, 3), v_crew_8,
    v_short, v_long, array_length(v_jargon, 1);
end $$;

drop table verb_schema_before_0021;
drop table caps_before_0021;

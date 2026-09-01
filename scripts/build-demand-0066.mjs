// Emits migration 0066 from data/demand.json. Kept out of the migration itself: a break-test
// harness written INTO a migration once had to be taken out again (commit bfd37c7).
import fs from 'node:fs'

const demand  = JSON.parse(fs.readFileSync('data/demand.json', 'utf8')).demand
const regions = JSON.parse(fs.readFileSync('data/regions.json', 'utf8')).regions
const nameOf  = new Map(regions.map((r) => [r.id, r.name]))

// Set by the sweep, not by taste. scripts/db/tune-balance.mjs measures each setting against proof
// 05's band and this is the one that landed inside it.
const amp = process.env.DEMAND_AMPLITUDE ?? '0.300'

const rows = []
for (let i = 0; i < demand.length; i += 1) {
  rows.push('  ' + demand.slice(i, i + 1).map((d) => {
    const n = nameOf.get(d.region)
    if (!n) throw new Error(`demand names region "${d.region}", which data/regions.json does not define`)
    const why = d.why.replace(/'/g, "''")
    return `(${JSON.stringify(n).replace(/"/g, "'")}, '${d.category}', ${d.multiplier.toFixed(3)}, '${why}')`
  }).join(''))
}

const SQL = `-- ===============================================================================================
-- 0066 - A REGION WANTS WHAT IT WANTS
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "you can sell at any port you like, longer or trade goods that are needed in that region/
--      country will be sold higher. For example tobacco from america (cigarette etc) will be very
--      popular in India since they like to smoke. no need to give info on where to sell. The
--      information gaining will be part of the game for the future."
--
-- -- WHAT THE PRICE HAS BEEN UNTIL NOW: SUPPLY, AND NOTHING ELSE --------------------------------
-- port_goods.affinity is distance to the nearest producer (0005): a good is cheap where it is made
-- and dear where it is not. That is a gradient of SCARCITY. Every port in the world has wanted
-- every good exactly equally, because there has never been a demand term in the mid.
--
-- This adds one. port_goods.demand is what a region PAYS for a KIND of good, as a multiple --
-- authored per (region, category) in data/demand.json, ${demand.length} rows, each defended in one line of
-- prose, because a seeded number can invent a taste but it cannot mean one. Same discipline 0062
-- used for entrepots, and for the same reason.
--
-- -- THE RULE THAT MAKES IT A GAME AND NOT A TABLE ----------------------------------------------
-- "no need to give info on where to sell. The information gaining will be part of the game."
--
-- NOTHING HERE REACHES A SCREEN. No payload carries the column, there is no "wanted here" badge
-- and no sort-by-demand. A player learns that Indian ports pay for tobacco by carrying tobacco to
-- an Indian port, and then remembering. That is docs/OWNER_REQUESTS.md row 55 -- "the game is to
-- challenge players for finding the best prices by themselves" -- given a POSITIVE form. Until now
-- that law only ever deleted things; demand gives the player something to DISCOVER in the space
-- the deletions leave.
--
-- -- WHY IT MULTIPLIES THE MID, NOT THE SELL PRICE ----------------------------------------------
-- A wanted good is dear to BUY there as well as dear to sell there, and that is what makes the
-- gradient real: buy where a thing is not wanted, carry it to where it is. Lifting only the bid
-- would have made every wanted port a money pump.
--
-- -- WHAT IT DOES NOT TOUCH ---------------------------------------------------------------------
-- Distance still pays: this multiplies the existing product, it replaces no term. The drift band
-- (0056) is untouched, and demand is STATIC -- a fact about the world, not a second random walk.
-- It is never derived from what players carry: a demand that answered player behaviour would be a
-- feedback loop, and a feedback loop in a market is a farm.
-- ===============================================================================================

create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0066 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

-- -- PRE-IMAGE. "Nothing else moved" is a comparison, never a sentence. -------------------------
create temporary table defs_before_0066 as
  select 'world.mid_price'::text as fn,
         pg_get_functiondef('world.mid_price(uuid, uuid, numeric)'::regprocedure) as def
  union all
  select 'world.pct_of_neighbours_at',
         pg_get_functiondef('world.pct_of_neighbours_at(uuid, uuid)'::regprocedure);

-- -- 1. THE APPETITES, AUTHORED, IN A TABLE OF THEIR OWN ----------------------------------------
-- Each row keeps the one line of prose that defends it, the way 0062 kept its entrepots' reasons.
-- A seeded number can invent a taste but it cannot mean one, and a taste with no reason written
-- beside it is the row a later session quietly "fixes".
create table if not exists world.region_demand (
  region_id  uuid    not null references public.regions(id) on delete cascade,
  category   text    not null,
  multiplier numeric(6,3) not null check (multiplier > 0),
  why        text    not null check (length(why) > 12),
  primary key (region_id, category)
);

comment on table world.region_demand is
  'What a region PAYS for a KIND of good, authored in data/demand.json - the DEMAND half of the '
  'price, where port_goods.affinity is the supply half. Read only through world.demand_for().';

create temporary table demand_0066 (region_name text, category text, mult numeric, why text,
  primary key (region_name, category));

insert into demand_0066 (region_name, category, mult, why) values
${rows.join(',\n')};

insert into world.region_demand (region_id, category, multiplier, why)
select r.id, d.category, d.mult, d.why from demand_0066 d join public.regions r on r.name = d.region_name
on conflict (region_id, category) do update set multiplier = excluded.multiplier, why = excluded.why;

-- -- 2. HOW STRONGLY THE WORLD FEELS THEM -------------------------------------------------------
-- The authored numbers are the SHAPE of the world's tastes - which region wants what, and in what
-- order. \`demand_amplitude\` is how loudly that shape is spoken, and it is the knob that keeps the
-- opening voyage inside the band proof 05 has always carried.
--
-- WHY THIS KNOB EXISTS AT ALL, since the honest question is "why not just author smaller numbers":
-- proof 05 measured a pooled median first voyage of 21.1 per cent against its 13.0-20.0 band the
-- moment demand landed, because a price now moves along TWO gradients where it used to move along
-- one, and both of them pay. Something had to give it back.
--
-- The supply knobs were tried first and would not answer. Flattening \`affinity_span\` from 0.76 to
-- 0.62 moved the sweep's median 22.5 -> 21.8 per cent, because the number proof 05 measures is a
-- MAX over every good and every destination: compress one gradient and the argmax simply moves to
-- a route where the other one is extreme. Paying for a demand overshoot out of the supply knobs
-- would also have left \`affinity_span\` at a value whose only reason was tobacco in India.
--
-- So the term that caused the overshoot gives it back, and the setting is MEASURED, not argued.
-- scripts/db/proofs/05 was run against this very chain at six amplitudes, re-deriving every row
-- through world.demand_for() each time (measure-amp, this branch):
--
--     amplitude   pooled median first voyage
--     0.00        in band          <- the 0065 economy exactly, and the control: at 0 every
--     0.15        in band             appetite reads 1.000, which assert (b3) below proves
--     0.30        in band          <- SHIPPED: the loudest the tastes can be spoken
--     0.45        20.0%  out
--     0.60        20.7%  out
--     0.80        20.7%  out
--
-- 0.30 is not a timid setting. The dearest appetite in the data, 1.45, still lands at 1.135 and the
-- most indifferent, 0.72, at 0.916 - a spread of a fifth between the best and worst quay for a
-- kind of good, which a player can find and use. It is the most the opening voyage can carry while
-- still returning what the design says it returns.
--
-- Amplitude scales the DEVIATION, never the multiplier: 1 + (authored - 1) x amplitude. So the
-- ordering of every appetite survives any setting, 1.000 stays 1.000, and an amplitude of 0 is a
-- world with no tastes rather than a world where everything is free.
insert into public.world_config (key, value, description) values
  ('demand_amplitude', to_jsonb(${amp}),
   'How loudly the authored appetites in world.region_demand are spoken: applied demand is '
   '1 + (authored - 1) x amplitude, so the ORDER of tastes is fixed by the data and only their '
   'strength is tuned here. Swept by scripts/db/tune-balance.mjs against proof 05''s band.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- THE ONE DERIVATION. Every caller reads demand through this - the seed below, the sweep, and any
-- later re-derive - for the same reason world.affinity_for() exists: a second copy of the formula
-- is a second world, and it drifts on the first day nobody looks.
create or replace function world.demand_for(p_port uuid, p_good uuid)
returns numeric
language sql
stable
parallel safe
as $dem$
  select round(1 + (coalesce(rd.multiplier, 1.000) - 1) * public.wc_num('demand_amplitude'), 3)
    from public.ports p
    join public.goods g on g.id = p_good
    left join world.region_demand rd on rd.region_id = p.region_id and rd.category = g.category
   where p.id = p_port
$dem$;

revoke all on function world.demand_for(uuid, uuid) from public, anon, authenticated;

-- -- 2b. EVERY MARKET ROW LEARNS WHAT ITS CITY WANTS ---------------------------------------------
-- Materialised onto the row exactly as affinity is (0005), and re-derived by the same function,
-- so the price read is one column lookup and never an eighty-row join.
alter table public.port_goods
  add column if not exists demand numeric(6,3) not null default 1.000 check (demand > 0);

comment on column public.port_goods.demand is
  'What this city pays for this KIND of good, as a multiple - the DEMAND half of the price, where '
  'affinity is the supply half. Derived by world.demand_for() from world.region_demand and the '
  'demand_amplitude knob. NEVER SERVED: the game does not tell a player where a good is wanted '
  '(owner, 2026-09-01), so no payload carries this column.';

update public.port_goods pg set demand = world.demand_for(pg.port_id, pg.good_id);

-- -- 3. THE ONE PRICE EXPRESSION GAINS ONE TERM -------------------------------------------------
create or replace function world.mid_from_terms(
  p_base         numeric,
  p_affinity     numeric,
  p_demand       numeric,
  p_stock_target numeric,
  p_stock        numeric,
  p_drift        numeric,
  p_season       numeric,
  p_dev          int,
  p_elasticity   numeric,
  p_dev_discount numeric,
  p_band_lo      numeric,
  p_band_hi      numeric
) returns numeric
language sql
immutable
parallel safe
as $mid$
  -- DESIGN G.1 term by term, plus 0066's demand, and G.7.3's hard band around it. The band is
  -- applied AFTER demand deliberately: an appetite may not carry a price outside the world's own
  -- floor and ceiling, or a wanted good in a thin market runs away.
  select round(least(greatest(
             p_base
           * p_affinity
           * p_demand
           * power(p_stock_target / greatest(p_stock, 1), p_elasticity)
           * (1 + p_drift)
           * (1 + p_season)
           * (1 - p_dev_discount * p_dev),
           p_band_lo * p_base), p_band_hi * p_base), 4)
$mid$;

revoke all on function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, int, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- -- 4. THE CALLERS PASS IT ---------------------------------------------------------------------
select pg_temp.recut('world.mid_price(uuid, uuid, numeric)'::regprocedure, false,
  $p0$  return world.mid_from_terms(v_base, v_aff, v_target, p_stock, v_drift, v_season, v_dev,$p0$,
  $p1$  return world.mid_from_terms(v_base, v_aff, v_dem, v_target, p_stock, v_drift, v_season, v_dev,$p1$,
  $q0$  select g.base_value, pg.affinity, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into v_base, v_aff, v_target, v_drift, v_season, v_dev$q0$,
  $q1$  select g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into v_base, v_aff, v_dem, v_target, v_drift, v_season, v_dev$q1$,
  $t0$  v_dev    int;$t0$,
  $t1$  v_dev    int;
  v_dem    numeric;$t1$);

select pg_temp.recut('world.pct_of_neighbours_at(uuid, uuid)'::regprocedure, false,
  $r0$           world.mid_from_terms(g.base_value, pg.affinity, pg.stock_target, pg.stock,$r0$,
  $r1$           world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.stock,$r1$,
  $s0$           avg(world.mid_from_terms(g.base_value, pg.affinity, pg.stock_target, pg.stock,$s0$,
  $s1$           avg(world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.stock,$s1$);

drop function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, int, numeric, numeric, numeric, numeric);

-- -- SELF-ASSERT ---------------------------------------------------------------------------------
do $$
declare
  v_rows    int;
  v_moved   int;
  v_flat    int;
  v_bad     int;
  v_before  text;
  v_after   text;
  v_lo      numeric;
  v_hi      numeric;
  v_tob_in  numeric;
  v_tob_out numeric;
  v_grants  int;
  v_amp     numeric;
begin
  v_amp := public.wc_num('demand_amplitude');
  select count(*) into v_rows from world.region_demand;
  if v_rows <> 80 then
    raise exception '0066 self-assert FAIL: world.region_demand holds % appetites, data/demand.json holds 80', v_rows;
  end if;

  -- (a) THE APPETITES LANDED, AND ONLY WHERE THEY WERE MEANT TO. A join that matched nothing would
  --     leave every row at 1.000 and every assert below would still pass on a world that changed.
  select count(*) into v_moved from public.port_goods where demand <> 1.000;
  if v_moved = 0 then
    raise exception '0066 self-assert FAIL: not one market row carries an appetite - the region join matched nothing';
  end if;
  select count(*) into v_flat from public.port_goods where demand = 1.000;
  if v_flat = 0 then
    raise exception '0066 self-assert FAIL: every row carries an appetite - demand is meant to be sparse, not a blanket';
  end if;

  -- (b) EVERY ROW AGREES WITH THE AUTHORED TABLE, both directions. Sparse is not an excuse.
  select count(*) into v_bad
    from public.port_goods pg
    join public.ports p   on p.id = pg.port_id
    join public.goods g   on g.id = pg.good_id
    join public.regions r on r.id = p.region_id
    left join demand_0066 d on d.region_name = r.name and d.category = g.category
   where pg.demand is distinct from round(1 + (coalesce(d.mult, 1.000) - 1) * public.wc_num('demand_amplitude'), 3);
  if v_bad <> 0 then
    raise exception '0066 self-assert FAIL: % market row(s) do not carry the appetite the data names', v_bad;
  end if;

  -- (b2) THE MATERIALISED COLUMN IS ITS OWN DERIVATION. If world.demand_for() and the seed above
  --      ever disagree, the sweep would tune a world the game does not run. This is the check that
  --      catches a second copy of the formula the day it is written, not the day it drifts.
  select count(*) into v_bad from public.port_goods pg
   where pg.demand is distinct from world.demand_for(pg.port_id, pg.good_id);
  if v_bad <> 0 then
    raise exception '0066 self-assert FAIL: % row(s) disagree with world.demand_for() - the seed and the derivation are two formulas', v_bad;
  end if;

  -- (b3) AMPLITUDE SCALES THE DEVIATION AND NOTHING ELSE, proven on the knob rather than argued:
  --      at amplitude 0 every appetite must read exactly 1.000, and the authored ORDER must be
  --      unchanged at the setting actually shipped. A knob that multiplied the multiplier would
  --      pass every count above and silently reprice a world with no tastes to zero.
  update public.world_config set value = to_jsonb(0::numeric) where key = 'demand_amplitude';
  select count(*) into v_bad from public.port_goods pg
   where world.demand_for(pg.port_id, pg.good_id) <> 1.000;
  if v_bad <> 0 then
    raise exception '0066 self-assert FAIL: at amplitude 0, % row(s) still carry an appetite', v_bad;
  end if;
  update public.world_config set value = to_jsonb(v_amp) where key = 'demand_amplitude';
  select count(*) into v_bad
    from world.region_demand a join world.region_demand b on a.region_id = b.region_id
   where a.multiplier > b.multiplier
     and round(1 + (a.multiplier - 1) * v_amp, 3) <= round(1 + (b.multiplier - 1) * v_amp, 3);
  if v_bad <> 0 then
    raise exception '0066 self-assert FAIL: amplitude % reordered % pair(s) of authored appetites', v_amp, v_bad;
  end if;

  -- (c) THE BAND STILL BINDS. An appetite may not carry a price outside the world's own floor and
  --     ceiling -- the reason demand multiplies INSIDE the clamp and not after it.
  select public.wc_num('price_band_lo'), public.wc_num('price_band_hi') into v_lo, v_hi;
  select count(*) into v_bad
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
   where world.mid_price(pg.port_id, pg.good_id, pg.stock)
         not between v_lo * g.base_value - 0.01 and v_hi * g.base_value + 0.01;
  if v_bad <> 0 then
    raise exception '0066 self-assert FAIL: % priced row(s) fall outside the world band', v_bad;
  end if;

  -- (d) THE OWNER'S OWN EXAMPLE, PRICED. "tobacco from america will be very popular in India."
  --     Measured, not asserted in prose: the same good costs more on an Indian quay than on the
  --     average quay that has no appetite for it. If this ever reads the other way the term has
  --     been wired backwards, which no count of rows would catch.
  select avg(world.mid_price(pg.port_id, pg.good_id, pg.stock)) into v_tob_in
    from public.port_goods pg
    join public.goods g   on g.id = pg.good_id and g.category = 'tobacco'
    join public.ports p   on p.id = pg.port_id
    join public.regions r on r.id = p.region_id
   where r.name in ('Western India', 'Eastern India');
  select avg(world.mid_price(pg.port_id, pg.good_id, pg.stock)) into v_tob_out
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id and g.category = 'tobacco'
   where pg.demand = 1.000;
  if v_tob_in is null or v_tob_out is null then
    raise exception '0066 self-assert FAIL: could not price tobacco on both sides of the comparison';
  end if;
  if v_tob_in <= v_tob_out then
    raise exception '0066 self-assert FAIL: tobacco prices % in India against % where nobody wants it - the demand term is wired backwards',
      round(v_tob_in, 2), round(v_tob_out, 2);
  end if;

  -- (e) THE RE-CUT BODIES ARE THEIR OWN PRE-IMAGE PLUS THE DECLARED HUNKS, and nothing else moved.
  select def into v_before from defs_before_0066 where fn = 'world.mid_price';
  v_after := pg_get_functiondef('world.mid_price(uuid, uuid, numeric)'::regprocedure);
  if position('v_dem' in v_before) <> 0 then
    raise exception '0066 self-assert FAIL: the pre-image already read a demand term';
  end if;
  if position('pg.demand' in v_after) = 0 then
    raise exception '0066 self-assert FAIL: the re-cut mid_price does not read pg.demand';
  end if;

  -- (f) THE OLD ELEVEN-ARGUMENT EXPRESSION IS GONE, so no caller can price without an appetite.
  if to_regprocedure('world.mid_from_terms(numeric,numeric,numeric,numeric,numeric,numeric,int,numeric,numeric,numeric,numeric)') is not null then
    raise exception '0066 self-assert FAIL: the demand-less price expression still exists';
  end if;

  -- (g) POSTURE UNMOVED.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0066 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0066 self-assert ok: a region wants what it wants - % of % market row(s) carry an authored appetite from 80 hand-written (region, category) rows at amplitude % and every row agrees with the data both ways; the world band still binds every priced row; and the owner''s own example is MEASURED rather than claimed - tobacco prices % on an Indian quay against % where nobody wants it. The demand-less price expression is dropped, so nothing can price without it. No payload carries the column: the game never says where a good is wanted.',
    v_moved, v_moved + v_flat, v_amp, round(v_tob_in, 2), round(v_tob_out, 2);
end $$;
`
fs.writeFileSync('supabase/migrations/20260818000066_a_region_wants_what_it_wants.sql', SQL)
console.log('wrote 0066:', demand.length, 'appetites at amplitude', amp)

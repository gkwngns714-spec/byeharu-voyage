-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0271 — THE PRESS LIVES IN REAL TIME, AND A LOT MOVES A TENTH   (E6, the owner's fix of 2026-10-28)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-28) ──────────────────────────────────────────────────────────────────────
--   "prices feel still" for merchants, yet his own buys move prices too much; "it should be the same".
--
-- ── WHAT WAS MEASURED ON PROD (read-only, 2026-10-29 06:20 UTC; the numbers this file is built on) ─
--   138,990 port_goods rows; 14,211 carry any press; avg |glut| 0.0087; max +0.0851; min -0.0478;
--   5 rows over 5 %; NONE at the 0.30 cap; 13,021 positive (sold into) vs 1,190 negative (bought out).
--   cmd.do_buy and cmd.do_sell are the ONLY writers of the press (public.press_after); their only live
--   caller is cmd.execute_order, which cmd.advance calls for a player's order AND a merchant's route
--   order — one rule already. So the fault is the constants and the decay, not a second rule.
--   Live knobs: glut_per_depth 0.30, glut_max 0.30, glut_decay 0.5, time_compression 960 (a game day is
--   ~90 real seconds, so today's half-life of one game day is ~90 seconds).
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
--   1. public.port_goods.glut_at timestamptz NOT NULL DEFAULT now(): THE ONE clock of a row's press —
--      the instant it last moved. Added with a fast default (no rewrite of the table). Every live row is
--      anchored at this migration's now().
--   2. cmd.do_buy and cmd.do_sell (one hunk each): the press and its clock move together — glut_at =
--      now(), the same transaction instant the row's updated_at already carries.
--   3. public.tick_market_drift's restock update (two hunks): the press fades by REAL time since
--      glut_at — glut × glut_decay ^ (real hours since glut_at / glut_half_life_hours), rounded to 4
--      places as 0194. The half-life is read once a harbour in 0247's materialised CTE, as glut_decay
--      already is.
--   4. knobs: glut_per_depth 0.30 → 0.10 (a whole lot of max stock moves a tenth; the 0.30 cap kept);
--      NEW glut_half_life_hours = 3; glut_max stays 0.30 and glut_decay stays 0.5 (its meaning is now
--      "the fraction left after one half-life"). Their notes are updated so the registry reads true.
--   NOTHING ELSE MOVES: public.press_after, world.quote_priced, the cap, the press writers' set, the
--   client entry points, ACLs, volatility and definer flags. The outlook (public.price_path) still
--   fades a press by game-days (1 - glut_decay): it is a forecast, not the market, and this slice does
--   not touch it (stated in the knob's note).
--
-- ── SUPERSEDE (what this file re-cuts, and why) ────────────────────────────────────────────────
--   This file SUPERSEDES three deployed bodies, each by hunks sliced from its live text (every hunk
--   asserted to occur exactly once and to reverse to its pre-image):
--     cmd.do_buy(uuid,jsonb)                     — 0254's press write; here it also writes glut_at
--     cmd.do_sell(uuid,jsonb)                    — the same, on 0254/0255/0263's live text
--     public.tick_market_drift(timestamptz,uuid) — 0194/0247/0252/0263's restock fade; here real-time
--   WHY: the owner's 2026-10-28 decision — "prices feel still" for merchants while his own buys move
--   them too much, "it should be the same". The press gets its own clock and a decay measured in real
--   hours; the step falls to a tenth of a full lot. The rule (public.press_after), the cap, the
--   writers and the quotes are NOT superseded: they do not move.
--   NO-OP WHEN THE NEW INPUT IS ABSENT: there is no optional input. This file CREATES its two new
--   inputs — public.port_goods.glut_at and the knob glut_half_life_hours — BEFORE it installs the new
--   bodies, and its guard raises rather than run without the world it needs (E6 missing, or the column
--   or the knob already present). So a replay is either the complete change or a refusal: no branch
--   reads either input as optional, and with no press on a row the decay writes 0 and still advances
--   the clock (the probe proves exactly that).
--
-- ── DECIDED BY DEFAULT (stated; the owner may reverse) ──────────────────────────────────────────
--   * Every live row is anchored at this migration's now(): a press that was fading under the old
--     per-game-day rule gets a fresh 3-hour half-life at deploy. (The alternative — reconstructing each
--     row's last press instant, which was never recorded — does not exist.)
--   * glut_at is written by every trade, even with price_impact dark: the design's "when they write
--     glut, they also write glut_at". (Live, the flag is lit, so the press always moves with the clock.)
--   * The formula is exactly the owner's: no clamp on a negative elapsed. A trade that commits between
--     the drift job's clock and its visit to that harbour can make the elapsed up to ~6 s negative, which
--     grows the press by < 0.05 % once; the next tick corrects it (recorded in the dev-log).
--
-- ── WHAT IT SELF-ASSERTS (its own probe rows only; every probe a rolled-back sub-transaction) ───
--   (a) 4 hunks, each occurs once and reverses to its pre-image; ACL / volatility / definer / config
--       unmoved; the functions the three bodies decide with unmoved (md5); the press writers the same
--       set; the client entry points and the three walls unmoved; every other knob and flag unmoved; the
--       glut CHECK unmoved.
--   (b) the column: NOT NULL, default now(), added as a missing value (a fast default, no rewrite), one
--       clock for every row (the migration's now()).
--   (c) the rule at the new step: one full lot (units = target) moves the press by 0.10; three lots
--       reach 0.30 and a fourth stays there; a sale the same the other way.
--   (d) the decay on planted rows: 0.4 at 0 h stays 0.4; at 3 h it is 0.2, at 6 h 0.1, at 9 h 0.05; a
--       press of 0 stays 0 and its clock still advances.
--   (e) OLD vs NEW, same planted state, each rolled back: the restock update leaves every column but
--       glut_at identical when the press is 0; cmd.do_buy and cmd.do_sell answer and leave every row
--       the same but glut_at. Then LIT (rolled back): a real buy and sale write glut_at = the trade's
--       instant and exactly public.press_after's press at the new step.
--   (f) after: the knobs read back 0.10 / 3 / 0.30 / 0.5; the probe house is gone.
-- ROLLBACK (forward): restore the four OLD hunks verbatim (kept in this file), update glut_per_depth
-- back to 0.30 and its note, delete glut_half_life_hours, and (only after the presses have faded)
-- alter table public.port_goods drop column glut_at. The column itself is harmless to keep.
-- VERSION: 0271 (prod head 0270 is the clear's re-plan; it changes none of these three bodies).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.port_goods') is null
     or to_regprocedure('public.price_impact_lit()') is null
     or to_regprocedure('public.press_after(numeric,numeric,numeric,text,numeric,numeric)') is null
     or to_regprocedure('public.depth_stock(numeric,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.tick_market_drift(timestamp with time zone,uuid)') is null
     or to_regprocedure('cmd.do_buy(uuid,jsonb)') is null
     or to_regprocedure('cmd.do_sell(uuid,jsonb)') is null then
    raise exception '0271 refuses: the E6 chain (0254) is not in this world';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'port_goods' and column_name = 'glut_at') then
    raise exception '0271 refuses: public.port_goods.glut_at already exists — this has been applied once';
  end if;
  if exists (select 1 from public.world_config where key = 'glut_half_life_hours') then
    raise exception '0271 refuses: the knob glut_half_life_hours already exists — this has been applied once';
  end if;
  if (select count(*) from public.world_config where key in ('glut_max', 'glut_per_depth', 'glut_decay')) <> 3 then
    raise exception '0271 refuses: the three E6 knobs are not all here';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0271(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0271 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('cmd.do_buy(uuid,jsonb)'),
               ('cmd.do_sell(uuid,jsonb)'),
               ('public.tick_market_drift(timestamp with time zone,uuid)')) f(fn);

-- the functions the three bodies decide with: not one of them may move in this file
create temp table kept_0271 (fn text) on commit drop;
insert into kept_0271 (fn) values
  ('public.price_impact_lit()'),
  ('public.press_after(numeric,numeric,numeric,text,numeric,numeric)'),
  ('public.wc(text)'), ('public.wc_num(text)'), ('public.economy_closed()'),
  ('public.depth_stock(numeric,numeric,numeric,numeric,numeric,numeric)'),
  ('public.depth_target(numeric,numeric,numeric)'), ('public.depth_mult(uuid)'),
  ('public.restock_rate(uuid)'), ('public.works_factor(uuid,text,text)'),
  ('public.stock_after(numeric,numeric,numeric,numeric,numeric)'),
  ('world.quote(uuid,uuid,numeric,text,numeric,uuid)'),
  ('world.want_left(uuid,uuid)'), ('world.game_day(timestamp with time zone)'),
  ('public.want_period(timestamp with time zone)'), ('public.city_treasury_on()');

create temp table before_0271 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0271 k) as kept_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%public.press_after%') as press_writers,
       (select md5(string_agg(key || '=' || value::text, ',' order by key))
          from public.world_config where key not in ('glut_per_depth', 'glut_decay', 'glut_half_life_hours')) as knobs_md5,
       (select pg_get_constraintdef(c.oid)
          from pg_constraint c
         where c.conrelid = 'public.port_goods'::regclass and c.conname = 'port_goods_glut_check') as glut_check;

-- THE PROBE'S WORLD: Lisbon, and five goods it sells in stock (the first is the trade probe's)
create temp table probe_0271 on commit drop as
select (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis,
       (select array_agg(g.id order by g.code)
          from (select g.id, g.code
                  from public.goods g
                  join public.port_goods pg on pg.good_id = g.id
                  join public.ports p on p.id = pg.port_id
                 where p.code = 'LIS' and p.kind = 'HARBOUR' and g.bulk <= 1 and pg.stock >= 200
                   and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
                 order by g.code limit 5) g) as goods;

do $$
begin
  if (select p.lis from probe_0271 p) is null
     or coalesce(array_length((select p.goods from probe_0271 p), 1), 0) <> 5 then
    raise exception '0271 self-assert FAIL: no Lisbon, or not five goods it sells in stock';
  end if;
end $$;

-- ── 1. THE COLUMN AND THE KNOBS ────────────────────────────────────────────────────────────────
-- One authority for "when did this row's press last move". A fast default: existing rows read now()
-- without a rewrite of the table (asserted below through pg_attribute.atthasmissing).
alter table public.port_goods add column glut_at timestamptz not null default now();

comment on column public.port_goods.glut_at is
  '0271: THE ONE clock of this row''s press — the instant public.port_goods.glut last moved: written by '
  'cmd.do_buy and cmd.do_sell with the trade''s own now(), and by public.tick_market_drift''s restock update '
  'as it fades the press. Read only there. Runtime state.';

comment on column public.port_goods.glut is
  '0194, signed by 0254, real-time decay 0271: THE PRESS on this market''s price — the price is multiplied '
  'by (1 - glut). A sale raises it, a buy lowers it (cmd.do_sell / cmd.do_buy through public.press_after, '
  'clamped to ±glut_max); it fades in REAL time in public.tick_market_drift: × glut_decay per '
  'glut_half_life_hours (3 h) since port_goods.glut_at, rounded to 4 places. A term of '
  'world.mid_from_terms, read by world.mid_terms. Runtime state.';

insert into public.world_config (key, value, description) values
  ('glut_half_life_hours', to_jsonb(3),
   '0271 (the owner, 2026-10-28): the press''s half-life in REAL hours. public.tick_market_drift fades a '
   'row''s press by glut_decay (the share left) per this many hours since port_goods.glut_at: 3 = a press '
   'halves every 3 real hours. The old rule halved it every game day (~90 real seconds). OWNER ONLY.');

update public.world_config
   set value = to_jsonb(0.10),
       description = '0271 (the owner, 2026-10-28): how far ONE FULL LOT (units = the row''s max stock) moves '
                     'THE PRESS: a buy lowers it, a sale raises it, by glut_per_depth × units / stock_target, '
                     'clamped to ±glut_max. Was 0.30 (a whole lot moved the price its full 30 %); 0.10 from '
                     '0271, so a whole lot moves a tenth. Read through public.press_after. OWNER ONLY.',
       updated_at = now()
 where key = 'glut_per_depth';

update public.world_config
   set description = '0194, re-based by 0271: the share of THE PRESS left after ONE HALF-LIFE (0.5 = it halves). '
                     'Since 0271 the time it measures is REAL time — glut_half_life_hours since '
                     'port_goods.glut_at — not a game day. The outlook (public.price_path) still fades by game '
                     'days at (1 - glut_decay); it is a forecast, not the market.',
       updated_at = now()
 where key = 'glut_decay';

-- ── 2. THE HUNKS (sliced from the LIVE bodies; each occurs once; each body reverses) ────────────
create temp table hunks_0271 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0271 (fn, n, old, new) values
-- the restock update's reader: the half-life, once a harbour (0247's materialised CTE)
('public.tick_market_drift(timestamp with time zone,uuid)', 1,
$h$           public.wc_num('glut_decay') as glut_decay,   -- 0194
           public.depth_mult(po.id) as depth   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
$h$,
$h$           public.wc_num('glut_decay') as glut_decay,   -- 0194: the fraction left after one half-life (0271)
           public.wc_num('glut_half_life_hours') as half_life,   -- 0271: the press's half-life, in REAL hours
           public.depth_mult(po.id) as depth   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
$h$),
-- the fade itself: real hours since the press last moved, and the clock advances with it
('public.tick_market_drift(timestamp with time zone,uuid)', 2,
$h$         glut = round(pg.glut * power(1 - f.glut_decay, v_day - pg.last_regen_day), 4),   -- 0194: the glut fades
         last_regen_day = v_day,
$h$,
$h$         -- 0271 (the owner, 2026-10-28): THE PRESS FADES IN REAL TIME. f.glut_decay is what is left after ONE
         -- half-life (glut_half_life_hours, 3 real hours), not after one game-day; the time it measures is the
         -- real time since this row's press last moved (port_goods.glut_at — written by the trades and here).
         -- 4 places, as 0194.
         glut = round(pg.glut * power(f.glut_decay, extract(epoch from (p_now - pg.glut_at)) / 3600.0 / f.half_life), 4),
         glut_at = p_now,
         last_regen_day = v_day,
$h$),
-- the buy leaves its mark and its clock at one instant
('cmd.do_buy(uuid,jsonb)', 1,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now(),
         glut = case when public.price_impact_lit()   -- 0254 (E6), lit: a buy leaves its mark too (the press falls: price up)
$h$,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now(),
         glut_at = now(),   -- 0271: the press's clock is the trade's own instant (the real-time decay starts here)
         glut = case when public.price_impact_lit()   -- 0254 (E6), lit: a buy leaves its mark too (the press falls: price up)
$h$),
-- the sale likewise
('cmd.do_sell(uuid,jsonb)', 1,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now(),
         glut = case when public.price_impact_lit()   -- 0254 (E6), lit: the same mark through the one rule (floored at −glut_max)
$h$,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now(),
         glut_at = now(),   -- 0271: the press's clock is the trade's own instant (the real-time decay starts here)
         glut = case when public.price_impact_lit()   -- 0254 (E6), lit: the same mark through the one rule (floored at −glut_max)
$h$);

-- THE OLD BODIES, temp copies for the probes (renamed only)
do $$
declare
  d record;
  v text;
begin
  for d in select * from (values ('cmd.do_buy(uuid,jsonb)', 'cmd.do_buy(', 'pg_temp.do_buy_old_0271('),
                                 ('cmd.do_sell(uuid,jsonb)', 'cmd.do_sell(', 'pg_temp.do_sell_old_0271('),
                                 ('public.tick_market_drift(timestamp with time zone,uuid)',
                                  'public.tick_market_drift(', 'pg_temp.tick_market_drift_old_0271(')) x(fn, f, t) loop
    v := (select def from defs_before_0271 where fn = d.fn);
    if pg_temp.occurs_0271(v, 'FUNCTION ' || d.f) <> 1 then
      raise exception '0271 self-assert FAIL: the live % does not open as this file expects', d.fn;
    end if;
    execute replace(v, 'FUNCTION ' || d.f, 'FUNCTION ' || d.t);
  end loop;
end $$;

-- THE PROBES' EYES (each runs in its own rolled-back sub-transaction; it answers by raising ZY271)
-- the decay clock: five planted rows, the whole decay family at once
create or replace function pg_temp.decay_0271(p_new boolean)
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select p.lis from probe_0271 p);
  v_g    uuid[] := (select p.goods from probe_0271 p);
  v_now  timestamptz := now();
  v_day  int := world.game_day(now());
  v_slot bigint := floor(extract(epoch from now()) / public.wc_num('drift_slot_seconds'))::bigint;
  v_res  jsonb;
begin
  begin
    update public.port_goods pg
       set last_regen_day = v_day - 1,
           drift_slot     = v_slot,   -- the random drift step is already this slot: it writes nothing
           glut = case pg.good_id when v_g[1] then 0.4 when v_g[2] then 0.4 when v_g[3] then 0.4
                                  when v_g[4] then 0.4 else 0 end,
           glut_at = case pg.good_id when v_g[1] then v_now
                                      when v_g[2] then v_now - interval '3 hours'
                                      when v_g[3] then v_now - interval '6 hours'
                                      when v_g[4] then v_now - interval '9 hours'
                                      else v_now - interval '3 hours' end
     where pg.port_id = v_lis and pg.good_id = any(v_g);
    if p_new then
      perform public.tick_market_drift(v_now, v_lis);
    else
      perform pg_temp.tick_market_drift_old_0271(v_now, v_lis);
    end if;
    select jsonb_object_agg(array_position(v_g, pg.good_id)::text,
                            jsonb_build_object('glut', pg.glut, 'at', pg.glut_at))
      into v_res
      from public.port_goods pg
     where pg.port_id = v_lis and pg.good_id = any(v_g);
    raise exception using errcode = 'ZY271', message = v_res::text;
  exception when sqlstate 'ZY271' then
    return sqlerrm::jsonb;
  end;
end $$;

-- the restock update with every press 0: every column but glut_at must be the pre-image's
create or replace function pg_temp.regen_0271(p_new boolean)
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select p.lis from probe_0271 p);
  v_g    uuid[] := (select p.goods from probe_0271 p);
  v_now  timestamptz := now();
  v_day  int := world.game_day(now());
  v_slot bigint := floor(extract(epoch from now()) / public.wc_num('drift_slot_seconds'))::bigint;
  v_res  jsonb;
begin
  begin
    update public.port_goods pg
       set last_regen_day = v_day - 1,
           drift_slot     = v_slot,
           glut           = 0,
           glut_at        = v_now - interval '3 hours'
     where pg.port_id = v_lis and pg.good_id = any(v_g);
    if p_new then
      perform public.tick_market_drift(v_now, v_lis);
    else
      perform pg_temp.tick_market_drift_old_0271(v_now, v_lis);
    end if;
    select jsonb_build_object(
             'rows', md5(string_agg((to_jsonb(pg) - 'glut_at')::text, ',' order by pg.good_id)),
             'at_new', count(*) filter (where pg.glut_at = v_now))
      into v_res
      from public.port_goods pg
     where pg.port_id = v_lis and pg.good_id = any(v_g);
    raise exception using errcode = 'ZY271', message = v_res::text;
  exception when sqlstate 'ZY271' then
    return sqlerrm::jsonb;
  end;
end $$;

-- one house's buy 30 then sell 30 at the probe row, by the old body or the new, lit or dark
create or replace function pg_temp.trade_0271(p_body text, p_lit boolean)
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select p.lis from probe_0271 p);
  v_good uuid := (select (p.goods)[1] from probe_0271 p);
  v_code text := (select g.code from public.goods g where g.id = (select (p.goods)[1] from probe_0271 p));
  v_p    uuid;
  v_f    uuid;
  v_g0   numeric;
  v_t0   numeric;
  v_buy  jsonb;
  v_sell jsonb;
  v_row0 jsonb;
  v_row1 jsonb;
  v_at0  timestamptz;
  v_at1  timestamptz;
  v_res  jsonb;
begin
  begin
    update public.port_goods pg
       set stock = 1000, stock_target = 1000, base_target = null, glut = 0.05,
           glut_at = timestamptz '2020-01-01 00:00:00+00',
           drift = 0, season_mod = 0, want_period = null
     where pg.port_id = v_lis and pg.good_id = v_good;
    select pg.glut, pg.stock_target into v_g0, v_t0
      from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good;

    v_p := public.new_house(null, 'Casa do Relógio 0271', 'PRT', 'LIS');
    select f.id into v_f from public.fleets f where f.player_id = v_p;
    perform public.credit(v_p, 'PROBE_0271', 1000000);

    -- a known world: no wants, no city purse rule; the press lit or dark as asked
    update public.world_config set value = to_jsonb(p_lit) where key in ('price_impact', 'economy_closed');
    update public.world_config set value = 'false'::jsonb where key in ('city_wants', 'city_treasury_enabled');

    if p_body = 'old' then
      v_buy := pg_temp.do_buy_old_0271(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    else
      v_buy := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    end if;
    select to_jsonb(pg) - 'glut_at', pg.glut_at into v_row0, v_at0
      from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good;

    if p_body = 'old' then
      v_sell := pg_temp.do_sell_old_0271(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    else
      v_sell := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    end if;
    select to_jsonb(pg) - 'glut_at', pg.glut_at into v_row1, v_at1
      from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good;

    select jsonb_build_object(
             'before', jsonb_build_object('glut', v_g0, 'target', v_t0),
             'buy', v_buy, 'sell', v_sell,
             'row_buy', v_row0, 'row_sell', v_row1,
             'glut_at_buy', v_at0, 'glut_at_sell', v_at1,
             'purse', (select pl.ducats from public.players pl where pl.id = v_p),
             'cargo', public.fleet_cargo_qty(v_f, v_code),
             'events', (select jsonb_agg(jsonb_build_array(ev.kind, ev.payload) order by ev.kind, ev.created_at)
                          from public.events ev where ev.player_id = v_p and ev.kind in ('BOUGHT', 'SOLD')),
             'ledger', (select jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta) order by l.kind, l.ducats_delta)
                          from public.ledger l where l.player_id = v_p and l.kind in ('BUY', 'SELL')),
             'daily',  (select jsonb_agg(td.qty) from public.trade_daily td where td.player_id = v_p))
      into v_res;
    raise exception using errcode = 'ZY271', message = v_res::text;
  exception when sqlstate 'ZY271' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 3. THE RE-CUTS (each hunk occurs once, then the new body is installed) ──────────────────────
do $$
declare
  d     record;
  h     record;
  v_def text;
  v_n   int;
begin
  for d in select * from defs_before_0271 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0271 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0271(v_def, h.old);
      if v_n <> 1 then
        raise exception '0271 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
          h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  v_d record; v_h record; v_pp record; v_def text;
  v_now   timestamptz := now();
  v_per   numeric;
  v_max   numeric;
  v_half  numeric;
  v_g     numeric;
  v_old   jsonb;
  v_new   jsonb;
  v_lit   jsonb;
  v_decay jsonb;
  v_t0    numeric;
  n       int := 0;
begin
  select * into b from before_0271;

  -- (a) THE RE-CUTS reverse to the live pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0271 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0271 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0271(v_def, v_h.new) <> 1 then
        raise exception '0271 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0271 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
           coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0271 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
        from kept_0271 k) <> b.kept_md5 then
    raise exception '0271 self-assert FAIL: a function the three bodies decide with moved';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%public.press_after%')
     <> b.press_writers then
    raise exception '0271 self-assert FAIL: the set of press writers changed';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0271 self-assert FAIL: the client entry points changed';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0271 self-assert FAIL: a wall moved';
  end if;
  if (select md5(string_agg(key || '=' || value::text, ',' order by key))
        from public.world_config where key not in ('glut_per_depth', 'glut_decay', 'glut_half_life_hours'))
     <> b.knobs_md5 then
    raise exception '0271 self-assert FAIL: a knob or flag this file did not mean to change moved';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.port_goods'::regclass and c.conname = 'port_goods_glut_check')
     is distinct from b.glut_check then
    raise exception '0271 self-assert FAIL: the glut CHECK moved';
  end if;

  -- (b) THE COLUMN: NOT NULL, default now(), a fast default, and one clock for every row
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'port_goods' and column_name = 'glut_at'
                and (is_nullable <> 'NO' or column_default is distinct from 'now()')) then
    raise exception '0271 self-assert FAIL: glut_at is not NOT NULL DEFAULT now()';
  end if;
  if not (select a.atthasmissing from pg_attribute a
           where a.attrelid = 'public.port_goods'::regclass and a.attname = 'glut_at') then
    raise exception '0271 self-assert FAIL: glut_at was not added as a fast default (the table was rewritten?)';
  end if;
  if exists (select 1 from public.port_goods pg where pg.glut_at is distinct from v_now) then
    raise exception '0271 self-assert FAIL: an existing row is not anchored at this migration''s now()';
  end if;

  -- (c) THE RULE AT THE NEW STEP
  v_per  := public.wc_num('glut_per_depth');
  v_max  := public.wc_num('glut_max');
  v_half := public.wc_num('glut_half_life_hours');
  if v_per <> 0.10 or v_max <> 0.30 or v_half <> 3 or public.wc_num('glut_decay') <> 0.50 then
    raise exception '0271 self-assert FAIL: the knobs read % / % / % / %, not 0.10 / 0.30 / 3 / 0.5',
      v_per, v_max, v_half, public.wc_num('glut_decay');
  end if;
  -- one full lot (units = target) moves the press 0.10; three reach 0.30; a fourth stays
  v_g := public.press_after(0, 1000, 1000, 'buy', v_per, v_max);
  if v_g <> -0.10 then
    raise exception '0271 self-assert FAIL: one full lot moves the press by %, not -0.10', v_g;
  end if;
  v_g := public.press_after(v_g, 1000, 1000, 'buy', v_per, v_max);
  v_g := public.press_after(v_g, 1000, 1000, 'buy', v_per, v_max);
  if v_g <> -0.30 then
    raise exception '0271 self-assert FAIL: three full lots move the press to %, not -0.30', v_g;
  end if;
  if public.press_after(v_g, 1000, 1000, 'buy', v_per, v_max) <> -0.30 then
    raise exception '0271 self-assert FAIL: a fourth lot went past the cap';
  end if;
  v_g := public.press_after(0, 1000, 1000, 'sell', v_per, v_max);
  if v_g <> 0.10 then
    raise exception '0271 self-assert FAIL: one full lot sold moves the press by %, not +0.10', v_g;
  end if;
  v_g := public.press_after(v_g, 1000, 1000, 'sell', v_per, v_max);
  v_g := public.press_after(v_g, 1000, 1000, 'sell', v_per, v_max);
  if v_g <> 0.30 or public.press_after(v_g, 1000, 1000, 'sell', v_per, v_max) <> 0.30 then
    raise exception '0271 self-assert FAIL: three lots sold do not reach +0.30 and stay there (%)', v_g;
  end if;

  -- (d) THE DECAY ON PLANTED ROWS (rolled back): 0.4 at 0 / 3 / 6 / 9 real hours; 0 stays 0
  v_decay := pg_temp.decay_0271(true);
  if (v_decay->'1'->>'glut')::numeric <> 0.4
     or (v_decay->'2'->>'glut')::numeric <> 0.2
     or (v_decay->'3'->>'glut')::numeric <> 0.1
     or (v_decay->'4'->>'glut')::numeric <> 0.05
     or (v_decay->'5'->>'glut')::numeric <> 0 then
    raise exception '0271 self-assert FAIL: the real-time decay read 0 h %, 3 h %, 6 h %, 9 h %, 0 press %',
      v_decay->'1'->>'glut', v_decay->'2'->>'glut', v_decay->'3'->>'glut', v_decay->'4'->>'glut', v_decay->'5'->>'glut';
  end if;
  for n in 1..5 loop
    if ((v_decay->n::text)->>'at')::timestamptz is distinct from v_now then
      raise exception '0271 self-assert FAIL: planted row % did not advance its glut_at to the tick''s clock', n;
    end if;
  end loop;

  -- (e1) OLD vs NEW, the restock update with every press 0: every column but glut_at identical
  v_old := pg_temp.regen_0271(false);
  v_new := pg_temp.regen_0271(true);
  if v_old->>'rows' is distinct from v_new->>'rows' then
    raise exception '0271 self-assert FAIL: the restock update moved a column it should not have: old % / new %',
      v_old->>'rows', v_new->>'rows';
  end if;
  if (v_old->>'at_new')::int <> 0 or (v_new->>'at_new')::int <> 5 then
    raise exception '0271 self-assert FAIL: the old body advanced % clocks, the new % (want 0 and 5)',
      v_old->>'at_new', v_new->>'at_new';
  end if;

  -- (e2) OLD vs NEW, a house's buy 30 and sell 30 (dark): the same answers and rows; only glut_at moves
  v_old := pg_temp.trade_0271('old', false);
  v_new := pg_temp.trade_0271('new', false);
  if (v_old - array['glut_at_buy', 'glut_at_sell']) is distinct from (v_new - array['glut_at_buy', 'glut_at_sell']) then
    raise exception '0271 self-assert FAIL: old and new buy/sell differ beyond glut_at: old % / new %',
      left(v_old::text, 1200), left(v_new::text, 1200);
  end if;
  if (v_old->>'glut_at_buy')::timestamptz is distinct from timestamptz '2020-01-01 00:00:00+00'
     or (v_old->>'glut_at_sell')::timestamptz is distinct from timestamptz '2020-01-01 00:00:00+00' then
    raise exception '0271 self-assert FAIL: the old body moved glut_at (%)', v_old->>'glut_at_buy';
  end if;
  if (v_new->>'glut_at_buy')::timestamptz is distinct from v_now
     or (v_new->>'glut_at_sell')::timestamptz is distinct from v_now then
    raise exception '0271 self-assert FAIL: the new body did not write glut_at = the trade''s instant (% / %)',
      v_new->>'glut_at_buy', v_new->>'glut_at_sell';
  end if;
  if (v_new->'buy'->>'qty')::numeric <> 30 or (v_new->'sell'->>'qty')::numeric <> 30 then
    raise exception '0271 self-assert FAIL: the probe trade was not 30 bought and 30 sold (%)', v_new->>'buy';
  end if;

  -- (e3) LIT (rolled back): the press the trades wrote is press_after's, at the new step, and glut_at is the instant
  v_lit := pg_temp.trade_0271('new', true);
  v_t0  := (v_lit->'before'->>'target')::numeric;
  v_g   := public.press_after((v_lit->'before'->>'glut')::numeric, (v_lit->'buy'->>'qty')::numeric, v_t0,
                              'buy', v_per, v_max);
  if (v_lit->'row_buy'->>'glut')::numeric <> v_g then
    raise exception '0271 self-assert FAIL: the lit buy wrote press %, not press_after''s %',
      v_lit->'row_buy'->>'glut', v_g;
  end if;
  if (v_lit->'row_buy'->>'glut')::numeric = (v_lit->'before'->>'glut')::numeric then
    raise exception '0271 self-assert FAIL: the lit buy did not move the press';
  end if;
  v_g := public.press_after(v_g, (v_lit->'sell'->>'qty')::numeric, v_t0, 'sell', v_per, v_max);
  if (v_lit->'row_sell'->>'glut')::numeric <> v_g then
    raise exception '0271 self-assert FAIL: the lit sale wrote press %, not press_after''s %',
      v_lit->'row_sell'->>'glut', v_g;
  end if;
  if (v_lit->>'glut_at_buy')::timestamptz is distinct from v_now
     or (v_lit->>'glut_at_sell')::timestamptz is distinct from v_now then
    raise exception '0271 self-assert FAIL: the lit trades did not write glut_at = now() (% / %)',
      v_lit->>'glut_at_buy', v_lit->>'glut_at_sell';
  end if;

  -- (f) after: the probes rolled back; the knobs read as set; every other knob and flag still unmoved
  if exists (select 1 from public.players pl where pl.company_name = 'Casa do Relógio 0271') then
    raise exception '0271 self-assert FAIL: the probe house survived its rollback';
  end if;
  if (select md5(string_agg(key || '=' || value::text, ',' order by key))
        from public.world_config where key not in ('glut_per_depth', 'glut_decay', 'glut_half_life_hours'))
     <> b.knobs_md5 then
    raise exception '0271 self-assert FAIL: a probe left a flag changed';
  end if;
  if public.wc_num('glut_per_depth') <> 0.10 or public.wc_num('glut_half_life_hours') <> 3
     or public.wc_num('glut_max') <> 0.30 or public.wc_num('glut_decay') <> 0.50 then
    raise exception '0271 self-assert FAIL: the knobs do not read back as set';
  end if;

  raise notice '0271 self-assert ok: THE PRESS LIVES IN REAL TIME, AND A LOT MOVES A TENTH. do_buy (1 hunk), do_sell (1) and tick_market_drift (2) re-cut, each hunk once and each body reversing to its pre-image; ACL / volatility / definer / config unmoved, the 16 functions they decide with unmoved, the 4 press writers (do_buy, do_sell, press_after, quote_priced) the same set, entry points and walls unmoved, every other knob and flag unchanged, the glut CHECK unchanged. port_goods.glut_at: NOT NULL DEFAULT now(), a fast default (atthasmissing), every live row at this migration''s now(). THE RULE at per 0.10 / max 0.30: one full lot -0.10, three -0.30, a fourth stays; a sale +0.10 / +0.30. THE DECAY (rolled back): 0.4 at 0 h stays %, at 3 h %, 6 h %, 9 h %, a press of 0 stays 0 and its clock advances; OLD = NEW on the restock update with every press 0 (every column but glut_at) and on a house''s buy 30 / sell 30 dark (answers, purse, cargo, rows, events, ledger); LIT: the buy wrote press %, the sale %, both press_after''s, glut_at = the trade''s instant. Nothing left behind.',
    v_decay->'1'->>'glut', v_decay->'2'->>'glut', v_decay->'3'->>'glut',
    v_decay->'4'->>'glut', v_lit->'row_buy'->>'glut', v_lit->'row_sell'->>'glut';
end $$;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights bargain_total_enabled)
-- 0506 - TEN BARGAINS, FIVE PER CENT EACH  (dark: the owner's switch bargain_total_enabled, false. Slice T2 `bargain-ten`,
--   docs/design/owner-spec-plan-2026-11-25.md section 6, rows 50 to 53; the owner's answers of the same day)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "You can bargain 10 times for price reduction or increase when selling. The success rate will decrease
--   everytime you attempt. Each time you attempt will create 5% of total price reduction. This will also be enhanced by captains, and
--   skills(level) - I am thinking NEGOTIATION skill." Then: a failed bargain costs nothing; PASSIVE orders may bargain, "but with
--   higher levels in skills".
--
-- TODAY (read in the live bodies). cmd.haggle is the one authority: 3 attempts a (company, city, good, real day), the attempt spent
--   before a roll keyed on (company, day, city, good, attempt); the odds (public.haggle_odds) fall only after a failure; a win shaves a
--   share of the city's SPREAD (about 0.3-0.5 % of the price), read by world.spread_pair_from and spent by the next trade
--   (cmd.do_buy / cmd.do_sell). One row, public.haggle_daily.
--
-- LIT (bargain_total_enabled true), STILL ONE AUTHORITY (cmd.haggle, its row, its roll, its spend):
--   * TEN ATTEMPTS a (company, city, good, day) (public.haggle_attempts_max: bargain_attempts 10).
--   * THE CHANCE FALLS ON EVERY ATTEMPT, won or lost: attempt n succeeds with p1 x bargain_decay^(n-1) (0.5), where
--     p1 = bargain_p1_base (0.25) + her skills (public.player_skill_bonus 'SPREAD', as before) + her NEGOTIATION level (1 point a
--     level from 2: 19 at level 20) + her captains (the purser's share, world.spread_purser, and the language points, as before),
--     never above bargain_p1_max (0.50) (public.bargain_p1, public.bargain_odds; public.haggle_odds hands the call over).
--     Expected wins in ten: 0.50 for a new company, 1.00 at p1 0.50.
--   * A WIN IS 5 % OF HER TOTAL (bargain_step 0.05), added: buying, her total is x (1 - 0.05 w); selling, x (1 + 0.05 w). A failed
--     attempt moves nothing and costs nothing. It is applied in THE one quote (world.quote_priced, one hunk: public.bargain_factor), so
--     every face that quotes for her fleet shows the won price before the press and the door charges exactly it. Nobody else's price,
--     the published price and the mid do not move. The spread is no longer shaved by a bargain (world.spread_pair_from, one hunk).
--   * ONE BARGAIN, ONE TRADE: the next trade of that good there spends it (cmd.do_buy / cmd.do_sell, as before); a second gets none.
--   * THE SAME-DAY RESALE GUARD. A city's spread is 2 to 6 %, so two wins buying would put her price under what the same city pays
--     back. So: the day's row is ONE SIDE ONLY (cmd.haggle refuses the other side: E_BARGAIN_SIDE), and on the other side the city takes
--     back what it gave: where she won w buying today, that city pays her x (1 - 0.05 w) for that good that day; where she won w
--     selling, it charges her x (1 + 0.05 w). The quote's shelves are the same both ways (0211), so a good bought there sells there,
--     that day, for no more than was paid; and sold there, is bought back for no less.
--   * NEGOTIATION IS A LEVEL IN THE EXISTING LEVEL TABLES (public.level_skills row `negotiation`, 20 levels on the short curve; no
--     second skill system): earned by bargaining herself (public.level_activities `bargain` 5, `bargain_won` 15, the day's cap 300),
--     shown only while the switch is lit (level_skills.lit_by; public.level_skills_card, one hunk). Its steps are rows of
--     public.level_perks: `bargain_chance` (1 point a level, 2 to 20) and `job_bargain` (3 tries at level 8, 6 at 12, 10 at 16).
--   * PASSIVE JOBS BARGAIN, FROM NEGOTIATION 8, THROUGH THE SAME cmd.haggle. A fleet with a standing job (public.fleet_jobs) whose
--     setting `bargain` is not false (the default is on; cmd.set_fleet_job params {"bargain": false} turns it off) makes, at its own
--     BUY and SELL (cmd.do_buy / cmd.do_sell, one hunk each: public.job_bargain), the tries her level allows that the day's row has
--     not used yet: the same rolls, the same row, the same day limits a company, city and good. A hundred runs or ten fleets get the
--     same ten tries a day: no gain from automation. Below level 8 a job does not bargain. A job's tries earn no experience.
--   * A JOB'S QUOTE PRICES THE EXPECTED BARGAIN, NEVER THE BEST: while a bargaining job's tries are still unused today,
--     public.bargain_factor answers 1 -/+ 0.05 x p1 x (the sum of bargain_decay^k over the tries left). Every job figure reads the one
--     quote (public.fleet_run_quote, public.run_day (its first run only), public.sale_fit, world.best_sales' cards, the board), so all of them price it, in
--     one place. At the door the tries are made first, so the door always charges what was really won.
-- DARK (as deployed): every answer as before. Each hunk reads the switch (or a helper that answers the old knob) and falls through.
--   The self-assert runs one scene (a bargain won, the state, the quote, the buy that spends it, the fourth try refused) before the
--   hunks and after them, dark: equal.
-- THE COST TO THE CITIES' PURSES, BOUNDED (the closed economy: a bargain is paid by the city; nothing is minted):
--   * a trade: at most 10 wins = 50 % of ITS total (chance under 1 in 10^16); expected 2.5 % (new company) to 5.0 % (p1 0.50) of it;
--   * a day: ONE bargain a (company, city, good), spent by ONE trade, whose units the day's allowance, her hold, the stock and the
--     city's purse already bound; per 100,000 d. of her bargained turnover a city gives up 2,500 to 5,000 d. on average;
--   * a job: at level 8 (3 tries, p1 0.32) 0.56 wins = 2.8 %; at 12 (6 tries, p1 0.36) 0.71 = 3.5 %; at 16 (10 tries, p1 0.40)
--     0.80 = 4.0 %; at 20 (p1 0.44) 0.88 = 4.4 %: never more than an active trader of the same level, and once a day a city and good;
--   * a sale the city cannot pay is refused as before (E_CITY_BROKE: public.treasury_post), so no purse goes under nought.
-- ROWS. Dark: none. Lit: no table. An attempt is one UPDATE of the one haggle_daily row and one HAGGLED event, as today; at most 10 a
--   (company, city, good, day) where it was 3. A player's own attempt also books her experience: one level_book row and one level_xp
--   update, at most 60 a company a day (the level's day cap 300 / 5). A job's tries: at most 10 a (company, city, good, day), made
--   inside the trade that needed them; no tick, no cron, no beat step is added.
-- budget: none while dark; lit, at most 10 row updates and 10 events a (company, city, good, day) as above (no table, no cron job, no
--   index, no autovacuum setting is made). -- retention: none (no table is made; public.haggle_daily is 0022's, one row a company a
--   city a good a day, and its retention is not changed here: `haggle_daily` in after-0506.sql reads its size).
-- THE TICK'S COST: dark, one switch read more a quote that names a fleet. Lit: one haggle_daily key probe a quote that names a fleet;
--   for a fleet with a bargaining job also her job row, her level's step and her p1 (a handful of key reads a quote). A job's BUY or
--   SELL makes its tries once a day a city and good (each a row update and an event), then one key probe.
-- THE HUNKS (20; each once in the live body, each reverses): cmd.haggle x6, public.haggle_odds x1, world.spread_pair_from x1,
--   world.quote_priced x1, world.haggle_state x2, cmd.do_buy x1, cmd.do_sell x1, public.level_skills_card x1,
--   public.fleet_job_set_for x1, public.run_day x5 (a day of runs counts the bargain on its FIRST run only: public.bargain_first). And the check on level_skills.lit_by is dropped (a sea level may now wait for a switch).
-- NOT CHANGED: every knob of another file (haggle_attempts_per_day, haggle_base_success, ... are the owner's and stay); the roll; the
--   row's key; world.quote's shelves; any table's shape; the cron. The client: no screen (the Trade tab's press comes with
--   trade-tab-fleet-map); `src/lib/rpc/types.ts` and the one new refusal's word only.
-- LOCKS: CREATE OR REPLACE x10 by hunks, CREATE FUNCTION x15, six knobs, one constraint swapped on public.level_skills (13 rows),
--   rows in three level tables. TIME: about a second. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, bargain_total_enabled false: three attempts, the old odds and the spread share again; an open
--   bargain of the new kind is then read as a share of the spread (at most 0.5 of it, under the floor): nothing is owed.
--   FULL: scripts/ops/harness/bargain-ten/rollback-0506.sql (a draft).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; grants and settings of the hunked bodies unmoved; no other knob
--   moved; the new functions server only. THE PROBES (rolled back by raised sentinels; no role is changed; INDEPENDENT OF PROD'S MARKET,
--   DICE AND COMPANIES: a company founded inside the probe; the stock, the mark and the want of the three market rows it trades and Lisbon's purse written inside it; every roll
--   made certain by the odds' own knobs set to 1 or 0 inside it, so no outcome hangs on the world's secret; every price compared with
--   the same quote read without the bargain in the same instant). DARK IDENTITY. LIT: the curve (0.25, 0.125, 0.0625, ...; the level
--   and the 0.50 cap); a win moves her total 5 % and nobody else's; three wins 15 %; the trade charges the quote and spends it; a second
--   trade gets none; the other side is refused and takes back what was given (the resale pays no more than was paid; bought back
--   for no less than sold); attempt 11 refused; ten lost attempts move nothing; a selling bargain adds 5 % a win; a job below level
--   8 does not bargain, at 8 / 12 / 16 it has 3 / 6 / 10 tries, its quote is the EXPECTED factor (above the best), its buy makes the
--   tries through cmd.haggle once and a second buy makes none; the setting off: none; the level is hidden while dark.
--   Proof 208 plays it through the doors with a real job.
-- VERSION: 0506 (after 0505; the lead deploys in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['cmd.haggle(uuid,uuid,text)', 'public.haggle_odds(uuid,uuid,uuid,uuid)',
    'world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)',
    'world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 'world.haggle_state(uuid,uuid)',
    'cmd.do_buy(uuid,jsonb)', 'cmd.do_sell(uuid,jsonb)', 'public.level_skills_card(uuid,jsonb)',
    'public.fleet_job_set_for(uuid,uuid,text,jsonb)',
    'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)'];
  c_new    constant text[] := array['public.bargain_on()', 'public.haggle_attempts_max()', 'public.haggle_step()', 'public.haggle_cap()',
    'public.bargain_p1(uuid,uuid,uuid,uuid)', 'public.bargain_odds(uuid,uuid,uuid,uuid)', 'public.bargain_actor()',
    'public.bargain_side_refusal(uuid,uuid,uuid,text)', 'public.bargain_xp(uuid,boolean)', 'public.job_bargain_tries(uuid)',
    'public.job_bargain(uuid,uuid,text)', 'public.job_bargain_param(jsonb)', 'public.bargain_factor(uuid,uuid,uuid,text)',
    'public.bargain_state(uuid,uuid,uuid,uuid)', 'public.bargain_first(uuid,uuid,uuid,text,numeric,numeric)'];
  c_knobs  constant text[] := array['bargain_total_enabled', 'bargain_attempts', 'bargain_step', 'bargain_p1_base', 'bargain_p1_max', 'bargain_decay'];
  c_ua     constant uuid := '00000000-0506-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_b          jsonb;
  v_d          jsonb;
  v_l          jsonb;
  v_x          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs))
     or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null)
     or exists (select 1 from public.level_skills s where s.code = 'negotiation') then
    raise exception '0506 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.level_perk(uuid,text)', 'public.level_grant(uuid,text,numeric,text)',
                                                    'world.spread_purser(uuid,uuid)', 'public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)']) f
              where to_regprocedure(f) is null)
     or to_regclass('public.haggle_daily') is null or to_regclass('public.fleet_jobs') is null or to_regclass('public.level_perks') is null then
    raise exception '0506 refuses: the bargain (0022), the levels (0411, 0417) or the jobs (0481) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0506 (fn text primary key, def text) on commit drop;
  insert into pre_0506 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (a temp function; a company founded here, three market rows stocked here, every roll made certain here) ──
  --    p_mode: 'dark' (the deployed rule, its dice made certain by its own knobs) | 'lit'.
  execute $f$
create function pg_temp.job_0506(p_player uuid, p_fleet uuid, p_extra jsonb)
returns jsonb
language plpgsql
as $body$
-- the job door on a Best job (it names no harbour and no good), its answer's settings; a refusal is answered as its sentence
begin
  update public.world_config set value = 'true'::jsonb where key = 'fleet_jobs_enabled';
  return public.fleet_job_set_for(p_player, p_fleet, 'best', p_extra)->'params';
exception when others then
  return jsonb_build_object('refused', sqlerrm);
end
$body$
  $f$;
  execute $f$
create function pg_temp.scene_0506(p_uid uuid, p_mode text)
returns jsonb
language plpgsql
as $body$
declare
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl   uuid;
  v_fl   uuid;
  v_g    uuid[];
  v_out  jsonb := '{}'::jsonb;
  v_r    jsonb;
  v_q0   bigint;
  v_q1   bigint;
  v_s0   bigint;
  v_s1   bigint;
  v_any  bigint;
  v_paid bigint;
  v_arr  jsonb := '[]'::jsonb;
  i      int;
begin
  v_pl := public.new_house(p_uid, 'Casa da Prova 0506', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players set ducats = 50000000 where id = v_pl;
  -- three goods Lisbon offers, their rows stocked by the probe itself: no price here hangs on the live market
  select array_agg(q.id order by q.code) into v_g
    from (select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
           where pg.port_id = v_lis and public.port_offers(v_lis, g.id) and g.bulk > 0 and g.bulk <= 2
             and not public.culture_refuses((select h.culture from public.ports h where h.id = v_lis), g.culture_mask)
           order by coalesce((select t.total from world.quote(v_lis, g.id, 1, 'buy', null, null) t), 0) desc, g.code limit 3) q;
  if v_lis is null or v_fl is null or coalesce(array_length(v_g, 1), 0) < 3 then
    raise exception '0506 self-assert FAIL: no Lisbon, no fleet, or fewer than three goods on its quay';
  end if;
  update public.port_goods pg set stock_target = greatest(pg.stock_target, 1000), stock = greatest(pg.stock_target, 1000), glut = 0, want_period = null, updated_at = now(), glut_at = now()
   where pg.port_id = v_lis and pg.good_id = any (v_g);
  update public.port_treasury t set ducats = t.ducats + 50000000 where t.port_id = v_lis;   -- the city can pay what the probe sells, whatever its purse holds today
  if public.fleet_free_hold(v_fl) < 45 then
    raise exception '0506 self-assert FAIL: the probe''s ship has % t free, under 45', public.fleet_free_hold(v_fl);
  end if;
  perform cmd.assume_identity(p_uid);

  if p_mode = 'dark' then
    -- the deployed rule with certain dice: the base and the ceiling at 1 (the owner's knobs, inside this rolled-back block only)
    update public.world_config set value = to_jsonb(1) where key in ('haggle_base_success', 'haggle_success_max');
    v_r := cmd.haggle(v_fl, v_g[1], 'buy');
    v_out := v_out || jsonb_build_object('h1', v_r - 'message',
      'state', world.haggle_state(v_fl, v_g[1]) - 'day' - 'language_line',
      'quote', (select to_jsonb(q) from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q),
      'quote_any', (select to_jsonb(q) from world.quote(v_lis, v_g[1], 10, 'buy', null, null) q),
      'buy', cmd.do_buy(v_fl, jsonb_build_object('good', v_g[1], 'qty', 10)));
    v_out := v_out || jsonb_build_object('after', public.haggle_concession(v_pl, v_lis, v_g[1]));
    perform cmd.haggle(v_fl, v_g[1], 'buy');
    perform cmd.haggle(v_fl, v_g[1], 'sell');
    v_r := cmd.haggle(v_fl, v_g[1], 'buy');
    v_out := v_out || jsonb_build_object('h4', jsonb_build_array(v_r->'ok', v_r->'error_code'),
      'sell', cmd.do_sell(v_fl, jsonb_build_object('good', v_g[1], 'qty', 2)),
      'card', public.level_skills_card(v_pl, '{}'::jsonb),
      'job', pg_temp.job_0506(v_pl, v_fl, '{"bargain": false}'::jsonb));
    return v_out;
  end if;

  update public.world_config set value = 'true'::jsonb where key in ('bargain_total_enabled', 'level_perks_on');
  -- no experience is booked until the last step: the probe writes her level itself meanwhile, and the level book is a chain
  update public.world_config set value = 'false'::jsonb where key = 'level_skills_on';
  -- THE CURVE, read from the rule itself (no roll): the row written by the probe says how many attempts are spent
  for i in 0 .. 3 loop
    insert into public.haggle_daily (player_id, port_id, good_id, day, attempts, wins, concession, last_side)
    values (v_pl, v_lis, v_g[3], public.real_day(now()), i, 0, 0, 'buy')
    on conflict (player_id, port_id, good_id, day) do update set attempts = excluded.attempts;
    v_arr := v_arr || to_jsonb(public.haggle_odds(v_pl, v_lis, v_g[3], null));
  end loop;
  delete from public.haggle_daily where player_id = v_pl;
  v_out := v_out || jsonb_build_object('curve', v_arr, 'max', public.haggle_attempts_max(), 'p1', public.bargain_p1(v_pl, v_lis, v_g[3], null));
  -- NEGOTIATION level 20: 19 points more; and the ceiling at 0.50 whatever is added
  insert into public.level_xp (player_id, skill, xp) values (v_pl, 'negotiation', public.level_begins('negotiation', 20)::int)
  on conflict (player_id, skill) do update set xp = excluded.xp;
  v_out := v_out || jsonb_build_object('p1_l20', public.bargain_p1(v_pl, v_lis, v_g[3], null));
  update public.world_config set value = to_jsonb(0.45) where key = 'bargain_p1_base';
  v_out := v_out || jsonb_build_object('p1_cap', public.bargain_p1(v_pl, v_lis, v_g[3], null));
  update public.level_xp set xp = 0 where player_id = v_pl and skill = 'negotiation';

  -- A: TEN LOST ATTEMPTS MOVE NOTHING (the chance at nought), and the eleventh is refused
  update public.world_config set value = to_jsonb(0) where key in ('bargain_p1_base', 'bargain_p1_max');
  select q.total into v_q0 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  for i in 1 .. 10 loop
    v_r := cmd.haggle(v_fl, v_g[2], 'buy');
  end loop;
  select q.total into v_q1 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  v_r := cmd.haggle(v_fl, v_g[2], 'buy');
  v_out := v_out || jsonb_build_object('lost', jsonb_build_object('q0', v_q0, 'q1', v_q1, 'eleventh', v_r->'error_code',
    'row', (select jsonb_build_array(h.attempts, h.wins, h.concession) from public.haggle_daily h where h.player_id = v_pl and h.good_id = v_g[2])));

  -- B: WINS (the chance certain: p1 1, no decay). One win 5 %, three wins 15 %, of HER total; nobody else's price moves.
  update public.world_config set value = to_jsonb(1) where key in ('bargain_p1_base', 'bargain_p1_max', 'bargain_decay');
  select q.total into v_q0 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
  select q.total into v_any from world.quote(v_lis, v_g[1], 10, 'buy', null, null) q;
  v_r := cmd.haggle(v_fl, v_g[1], 'buy');
  select q.total into v_q1 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
  v_out := v_out || jsonb_build_object('win1', jsonb_build_object('q0', v_q0, 'q1', v_q1, 'won', v_r->'won', 'pct', v_r->'concession_pct',
    'state', world.haggle_state(v_fl, v_g[1])->'bargain'));
  perform cmd.haggle(v_fl, v_g[1], 'buy');
  perform cmd.haggle(v_fl, v_g[1], 'buy');
  select q.total into v_q1 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
  v_out := v_out || jsonb_build_object('win3', jsonb_build_object('q0', v_q0, 'q1', v_q1,
    'any_same', (select q.total from world.quote(v_lis, v_g[1], 10, 'buy', null, null) q) = v_any));
  -- the trade charges the quote and spends the bargain; a second trade gets none
  v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_g[1], 'qty', 10));
  v_paid := (v_r->>'total')::bigint;
  v_out := v_out || jsonb_build_object('spend', jsonb_build_object('paid', v_paid, 'quoted', v_q1,
    'left', public.haggle_concession(v_pl, v_lis, v_g[1]), 'factor_after', public.bargain_factor(v_fl, v_lis, v_g[1], 'buy')));
  -- THE OTHER SIDE, the same day (she now carries it): a bargain to sell is refused, and the city takes back the 15 % it gave
  v_r := cmd.haggle(v_fl, v_g[1], 'sell');
  select q.total into v_s0 from world.quote(v_lis, v_g[1], 10, 'sell', null, v_fl) q;
  v_out := v_out || jsonb_build_object('resale', jsonb_build_object('other_side', v_r->'error_code', 'paid', v_paid, 'quoted', v_s0,
    'factor', public.bargain_factor(v_fl, v_lis, v_g[1], 'sell'), 'got', (cmd.do_sell(v_fl, jsonb_build_object('good', v_g[1], 'qty', 10))->>'total')::bigint));

  -- C: SELLING. She buys the third good plainly, wins twice to sell: + 10 % of her total; then buying it back costs 10 % more
  delete from public.haggle_daily where player_id = v_pl and good_id = v_g[3];
  perform cmd.do_buy(v_fl, jsonb_build_object('good', v_g[3], 'qty', 10));
  select q.total into v_s0 from world.quote(v_lis, v_g[3], 10, 'sell', null, v_fl) q;
  perform cmd.haggle(v_fl, v_g[3], 'sell');
  perform cmd.haggle(v_fl, v_g[3], 'sell');
  select q.total into v_s1 from world.quote(v_lis, v_g[3], 10, 'sell', null, v_fl) q;
  v_r := cmd.do_sell(v_fl, jsonb_build_object('good', v_g[3], 'qty', 10));
  select q.total into v_q1 from world.quote(v_lis, v_g[3], 10, 'buy', null, v_fl) q;
  v_out := v_out || jsonb_build_object('sell', jsonb_build_object('s0', v_s0, 's1', v_s1, 'got', (v_r->>'total')::bigint,
    'back_factor', public.bargain_factor(v_fl, v_lis, v_g[3], 'buy'), 'back_hers', v_q1));

  -- D: A JOB. The level opens the tries; the quote prices the EXPECTED bargain; the buy makes the tries through cmd.haggle, once.
  delete from public.haggle_daily where player_id = v_pl;
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values (v_fl, v_pl, 'best', '{}'::jsonb, now(), now())
  on conflict (fleet_id) do update set params = excluded.params, paused_reason = null;
  v_arr := '[]'::jsonb;
  for i in 1 .. 5 loop
    insert into public.level_xp (player_id, skill, xp) values (v_pl, 'negotiation', public.level_begins('negotiation', (array[7, 8, 12, 16, 20])[i])::int)
    on conflict (player_id, skill) do update set xp = excluded.xp;
    v_arr := v_arr || to_jsonb(public.job_bargain_tries(v_fl));
  end loop;
  v_out := v_out || jsonb_build_object('tries', v_arr);
  update public.level_xp set xp = public.level_begins('negotiation', 8)::int where player_id = v_pl and skill = 'negotiation';
  -- the real curve for the expectation: p1 0.25 + 7 points = 0.32, three tries: 0.05 x 0.32 x (1 + 0.5 + 0.25) = 0.028
  update public.world_config set value = to_jsonb(0.25) where key = 'bargain_p1_base';
  update public.world_config set value = to_jsonb(0.5) where key in ('bargain_p1_max', 'bargain_decay');
  v_out := v_out || jsonb_build_object('expected', jsonb_build_array(public.bargain_factor(v_fl, v_lis, v_g[2], 'buy'), public.bargain_factor(v_fl, v_lis, v_g[2], 'sell'),
    public.bargain_p1(v_pl, v_lis, v_g[2], v_fl), public.bargain_p1(v_pl, v_lis, v_g[2], null)));
  -- a day of runs keeps it on the first run only: 4,860 = 5,000 x 0.972 for the day, 972 for the first run -> 5,000 - 28 = 4,972
  v_out := v_out || jsonb_build_object('day', jsonb_build_array(public.bargain_first(v_fl, v_lis, v_g[2], 'buy', 4860, 972),
    public.bargain_first(v_fl, v_lis, v_g[2], 'sell', 5140, 1028)));
  -- the setting off: no tries, no expectation
  update public.fleet_jobs set params = public.job_bargain_param('{"bargain": false}'::jsonb) where fleet_id = v_fl;
  v_out := v_out || jsonb_build_object('off', jsonb_build_array(public.job_bargain_tries(v_fl), public.bargain_factor(v_fl, v_lis, v_g[2], 'buy'),
    public.job_bargain_param('{"bargain": false}'::jsonb), public.job_bargain_param('{"bargain": true}'::jsonb), public.job_bargain_param('{}'::jsonb)));
  -- the buy, with certain dice: three tries made by the job through cmd.haggle, the trade charged 15 % less; a second buy: no try more
  update public.world_config set value = to_jsonb(1) where key in ('bargain_p1_base', 'bargain_p1_max', 'bargain_decay');
  select q.total into v_q0 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;   -- the setting still off: her plain price
  update public.fleet_jobs set params = '{}'::jsonb where fleet_id = v_fl;
  v_any := (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'HAGGLED');
  v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_g[2], 'qty', 10));
  v_out := v_out || jsonb_build_object('jobbuy', jsonb_build_object('plain', v_q0, 'paid', (v_r->>'total')::bigint,
    'row', (select jsonb_build_array(h.attempts, h.wins, h.concession, h.last_side) from public.haggle_daily h where h.player_id = v_pl and h.good_id = v_g[2]),
    'events', (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'HAGGLED') - v_any,
    'xp', (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'negotiation') - public.level_begins('negotiation', 8)::int));
  select q.total into v_q0 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_g[2], 'qty', 10));
  v_out := v_out || jsonb_build_object('jobbuy2', jsonb_build_object('plain', v_q0, 'paid', (v_r->>'total')::bigint,
    'attempts', (select h.attempts from public.haggle_daily h where h.player_id = v_pl and h.good_id = v_g[2])));
  -- her own attempt earns experience (a job's tries above earned none); the level is on her card only while lit
  update public.level_xp set xp = 0 where player_id = v_pl and skill = 'negotiation';
  update public.world_config set value = 'true'::jsonb where key = 'level_skills_on';
  v_any := 0;
  perform cmd.haggle(v_fl, v_g[3], 'buy');
  v_out := v_out || jsonb_build_object('xp_own', (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'negotiation') - v_any,
    'card_lit', position('Negotiation' in public.level_skills_card(v_pl, '{}'::jsonb)::text) > 0);
  update public.world_config set value = 'false'::jsonb where key = 'bargain_total_enabled';
  v_out := v_out || jsonb_build_object('card_dark', position('Negotiation' in public.level_skills_card(v_pl, '{}'::jsonb)::text) > 0,
    'job', pg_temp.job_0506(v_pl, v_fl, '{"bargain": false}'::jsonb));
  update public.world_config set value = 'true'::jsonb where key = 'bargain_total_enabled';
  v_out := v_out || jsonb_build_object('job_lit', pg_temp.job_0506(v_pl, v_fl, '{"bargain": false}'::jsonb));
  return v_out;
end
$body$
  $f$;

  begin
    raise exception using errcode = 'ZX506', message = pg_temp.scene_0506(c_ua, 'dark')::text;
  exception when sqlstate 'ZX506' then v_b := sqlerrm::jsonb;
  end;
  if (v_b #>> '{h1,won}')::boolean is not true or (v_b->>'after')::numeric <> 0 or v_b->'h4' <> '[false, "E_HAGGLE_SPENT"]'::jsonb
     or (v_b #>> '{state,attempts_max}')::int <> public.wc_int('haggle_attempts_per_day') then
    raise exception '0506 self-assert FAIL: before the hunks the scene did not win, spend and run out as the deployed rule does: %', left(v_b::text, 900);
  end if;

  -- ── 3. THE KNOBS (this file's own; the owner's switch dark) ──
  insert into public.world_config (key, value, description) values
    ('bargain_total_enabled', 'false'::jsonb,
     '0506: THE SWITCH (the owner''s). true: a bargain (cmd.haggle) is bargain_attempts tries a company, city, good and real day; try n succeeds with p1 x bargain_decay^(n-1), p1 from bargain_p1_base, her skills, her Negotiation level and her captains, never above bargain_p1_max; a win is bargain_step of HER TOTAL (added; public.bargain_factor in world.quote_priced), spent by her next trade of that good there; the day''s row is one side only and the other side takes it back; standing jobs bargain from Negotiation 8 (level_perks job_bargain). false: three tries, the old odds, a share of the spread, as before.'),
    ('bargain_attempts', to_jsonb(10), '0506: lit, the tries a company has for one good in one city in one real day (the owner: ten).'),
    ('bargain_step', to_jsonb(0.05), '0506: lit, what one won try moves her total by (the owner: 5 %), added: ten wins are 50 %.'),
    ('bargain_p1_base', to_jsonb(0.25), '0506: lit, the chance of the first try for a company with no skill, level or captain. THE knob to watch: the cities'' purses pay for it.'),
    ('bargain_p1_max', to_jsonb(0.50), '0506: lit, the most the first try''s chance may be, whatever her skills, level and captains add.'),
    ('bargain_decay', to_jsonb(0.5), '0506: lit, each try''s chance is the one before it times this, won or lost. 0.5: expected wins in ten tries = p1 x 1.998.');

  -- ── 4. NEGOTIATION, A LEVEL IN THE EXISTING LEVEL TABLES (hidden while the switch is dark) ──
  alter table public.level_skills drop constraint level_skills_lit_by_check;
  comment on column public.level_skills.lit_by is
    '0461: the world_config switch a land skill waits for besides land_enabled (public.land_skill_on). 0506: and the switch a SEA level waits for before it is shown (public.level_skills_card). null: none.';
  insert into public.level_skills (code, ord, word, kept, day_cap, side, curve, gift_every, lit_by)
  values ('negotiation', (select max(s.ord) + 1 from public.level_skills s), 'Negotiation', 'book', 300, 'sea', 'short', 1, 'bargain_total_enabled');
  insert into public.level_activities (code, skill, ord, word, unit, xp, per) values
    ('bargain', 'negotiation', 1, 'A bargain tried', 'each', 5, 1),
    ('bargain_won', 'negotiation', 2, 'A bargain won', 'each', 15, 1);
  insert into public.level_perks (perk, level, skill, unit, amount, word)
  select 'bargain_chance', l, 'negotiation', 'pct_more', 1, 'A better chance on the first bargain' from generate_series(2, 20) l;
  insert into public.level_perks (perk, level, skill, unit, amount, word) values
    ('job_bargain', 8, 'negotiation', 'count', 3, 'Standing jobs bargain: three tries a day'),
    ('job_bargain', 12, 'negotiation', 'count', 3, 'Standing jobs bargain: six tries a day'),
    ('job_bargain', 16, 'negotiation', 'count', 4, 'Standing jobs bargain: ten tries a day');

  -- ── 5. THE RULES ──
  execute $f$
create function public.bargain_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0506: THE SWITCH, read once: world_config bargain_total_enabled.
  select public.wc('bargain_total_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.haggle_attempts_max()
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0506: THE TRIES A COMPANY HAS for one good in one city in one real day: bargain_attempts (10) lit, haggle_attempts_per_day as before.
  select case when public.bargain_on() then public.wc_int('bargain_attempts') else public.wc_int('haggle_attempts_per_day') end
$body$
  $f$;

  execute $f$
create function public.haggle_step()
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0506: WHAT ONE WON TRY ADDS to the day's row: bargain_step (5 % of her total) lit, haggle_concession_step (a share of the spread) as before.
  select case when public.bargain_on() then public.wc_num('bargain_step') else public.wc_num('haggle_concession_step') end
$body$
  $f$;

  execute $f$
create function public.haggle_cap()
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0506: THE MOST THE DAY'S ROW MAY HOLD: every try won (bargain_attempts x bargain_step = 50 %) lit, haggle_concession_max as before.
  select case when public.bargain_on() then public.wc_int('bargain_attempts') * public.wc_num('bargain_step') else public.wc_num('haggle_concession_max') end
$body$
  $f$;

  execute $f$
create function public.bargain_p1(p_player uuid, p_port uuid, p_good uuid, p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: THE CHANCE OF HER FIRST TRY: bargain_p1_base, plus her skills (public.player_skill_bonus 'SPREAD', as 0022 added them), plus her
-- NEGOTIATION level (public.level_perk 'bargain_chance': 1 point a level), plus her captains when a fleet is named (the purser's share,
-- world.spread_purser, and 0161's language points), never above bargain_p1_max and never under nought.
begin
  return least(public.wc_num('bargain_p1_max'), greatest(0,
           public.wc_num('bargain_p1_base')
           + public.player_skill_bonus(p_player, 'SPREAD')
           + public.level_perk(p_player, 'bargain_chance') / 100.0
           + case when p_fleet is not null then coalesce(world.spread_purser(p_fleet, p_good), 0) else 0 end
           + case when p_fleet is not null and exists (select 1 from public.crew_speaker(p_fleet, p_port))
                  then public.wc_num('language_haggle_points') / 100.0 else 0 end));
end
$body$
  $f$;

  execute $f$
create function public.bargain_odds(p_player uuid, p_port uuid, p_good uuid, p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: THE CHANCE OF HER NEXT TRY (public.haggle_odds hands the call here while the switch is lit): p1 x bargain_decay ^ (the tries
-- already spent today on this good here). It falls on every try, won or lost.
declare
  v_used int;
begin
  select h.attempts into v_used from public.haggle_daily h
   where h.player_id = p_player and h.port_id = p_port and h.good_id = p_good and h.day = public.real_day(now());
  return round(public.bargain_p1(p_player, p_port, p_good, p_fleet) * power(public.wc_num('bargain_decay'), coalesce(v_used, 0)), 4);
end
$body$
  $f$;

  execute $f$
create function public.bargain_actor()
returns uuid
language sql
stable
as $body$
  -- 0506: THE COMPANY A STANDING JOB BARGAINS FOR: set by public.job_bargain for its own calls of cmd.haggle and put back (a setting of
  -- the transaction; no client can set it). Null: the signed-in company, as before.
  select nullif(current_setting('byeharu.bargain_actor', true), '')::uuid
$body$
  $f$;

  execute $f$
create function public.bargain_side_refusal(p_player uuid, p_port uuid, p_good uuid, p_side text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: THE DAY'S ROW IS ONE SIDE ONLY. Lit, a company that has tried to buy a good in a city today may not bargain to sell it there
-- today, nor the other way round (the resale guard: public.bargain_factor says what the other side then pays). The sentence, or null.
declare
  v_side text;
begin
  if not public.bargain_on() then
    return null;
  end if;
  select h.last_side into v_side from public.haggle_daily h
   where h.player_id = p_player and h.port_id = p_port and h.good_id = p_good and h.day = public.real_day(now()) and h.attempts > 0;
  if v_side is null or v_side = p_side then
    return null;
  end if;
  return format('You have already bargained to %s this here today. One bargain a good a city a day, on one side.', v_side);
end
$body$
  $f$;

  execute $f$
create function public.bargain_xp(p_player uuid, p_won boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0506: A BARGAIN SHE TRIED HERSELF is experience in Negotiation (public.level_grant: `bargain`, and `bargain_won` when it was won).
-- Dark: nothing. A standing job's tries (public.bargain_actor) earn none: the level is earned at the quay, not by a schedule.
begin
  if not public.bargain_on() or public.bargain_actor() is not null then
    return;
  end if;
  perform public.level_grant(p_player, 'bargain', 1, null);
  if p_won then
    perform public.level_grant(p_player, 'bargain_won', 1, null);
  end if;
end
$body$
  $f$;

  execute $f$
create function public.job_bargain_tries(p_fleet uuid)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: THE TRIES A STANDING JOB MAY MAKE for one good in one city in one day: 0 while dark, for a fleet with no job or a stopped one,
-- and where the job's setting `bargain` is false (the default is on); else her Negotiation level's step (public.level_perk
-- 'job_bargain': 3 from level 8, 6 from 12, 10 from 16; below 8 none), never above the day's tries of anyone.
declare
  v_player uuid;
begin
  if not public.bargain_on() then
    return 0;
  end if;
  select j.player_id into v_player from public.fleet_jobs j
   where j.fleet_id = p_fleet and j.paused_reason is null and coalesce(j.params->>'bargain', 'true') <> 'false';
  if v_player is null then
    return 0;
  end if;
  return least(public.haggle_attempts_max(), public.level_perk(v_player, 'job_bargain')::int);
end
$body$
  $f$;

  execute $f$
create function public.job_bargain_param(p_params jsonb)
returns jsonb
language sql
immutable
as $body$
  -- 0506: THE JOB SETTING `bargain`, as a job keeps it: {"bargain": false} only where the caller said false; else nothing (on is the default).
  select case when p_params->>'bargain' = 'false' then '{"bargain": false}'::jsonb else '{}'::jsonb end
$body$
  $f$;

  execute $f$
create function public.job_bargain(p_fleet uuid, p_good uuid, p_side text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0506: A STANDING JOB BARGAINS, at its own buy or sale (cmd.do_buy / cmd.do_sell call this before they quote). It makes, THROUGH
-- cmd.haggle (the one authority: the same row, the same roll, the same day's limits a company, city and good), the tries her level
-- allows (public.job_bargain_tries) that the day's row has not used yet. So a hundred runs or ten fleets get what one company gets.
-- Dark, no job, the setting off, below the level, the other side already bargained, or the tries used: nothing (one key probe).
-- A try that fails for any reason ends the tries; a trade is never refused because its bargain could not be made. Answers the tries made.
declare
  v_n      int := public.job_bargain_tries(p_fleet);
  v_player uuid;
  v_port   uuid;
  v_used   int;
  v_prev   text;
  v_r      jsonb;
  v_done   int := 0;
begin
  if v_n <= 0 then
    return 0;
  end if;
  select f.player_id, f.port_id into v_player, v_port from public.fleets f where f.id = p_fleet;
  select h.attempts into v_used from public.haggle_daily h
   where h.player_id = v_player and h.port_id = v_port and h.good_id = p_good and h.day = public.real_day(now());
  v_used := coalesce(v_used, 0);
  if v_used >= v_n or public.bargain_side_refusal(v_player, v_port, p_good, p_side) is not null then
    return 0;
  end if;
  v_prev := current_setting('byeharu.bargain_actor', true);
  perform set_config('byeharu.bargain_actor', v_player::text, true);
  begin
    while v_used < v_n loop
      v_r := cmd.haggle(p_fleet, p_good, p_side);
      exit when not coalesce((v_r->>'ok')::boolean, false);
      v_used := v_used + 1;
      v_done := v_done + 1;
    end loop;
  exception when others then
    null;   -- the tries of this block are undone with it; the trade goes on at the price it has
  end;
  perform set_config('byeharu.bargain_actor', coalesce(v_prev, ''), true);
  return v_done;
end
$body$
  $f$;

  execute $f$
create function public.bargain_factor(p_fleet uuid, p_port uuid, p_good uuid, p_side text)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: WHAT HER BARGAIN DOES TO HER TOTAL, in THE one quote (world.quote_priced multiplies its total by this for the fleet it names).
-- 1 while dark, with no fleet, and where she holds nothing here today. Lit, from the day's one row (company, city, good):
--   the side she bargained:  buying 1 - c, selling 1 + c, c = what she holds unspent (0.05 a win; an old-kind row of the day the
--                            switch was lit counts 0.05 a win too, never its share of the spread);
--   the OTHER side:          the city takes back what it gave: selling where she won w buying today 1 - 0.05 w, buying where she won
--                            w selling 1 + 0.05 w (the same-day resale guard);
--   A STANDING JOB whose tries are still unused today (public.job_bargain_tries): the EXPECTED gain of those tries is added,
--                            0.05 x p1 x the sum of bargain_decay^k over them: what a plan may count on, never the best. At the door the
--                            tries are made first (public.job_bargain), so nothing is left to expect and the door charges what was won.
declare
  v_player uuid;
  r        record;
  v_has    boolean;
  v_step   numeric;
  v_most   numeric;
  v_c      numeric := 0;
  v_n      int;
  v_used   int;
begin
  if p_fleet is null or not public.bargain_on() then
    return 1;
  end if;
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is null then
    return 1;
  end if;
  v_step := public.wc_num('bargain_step');
  v_most := public.wc_int('bargain_attempts') * v_step;
  select h.attempts, h.wins, h.concession, h.last_side into r from public.haggle_daily h
   where h.player_id = v_player and h.port_id = p_port and h.good_id = p_good and h.day = public.real_day(now());
  v_has := found;
  if v_has and r.attempts > 0 and r.last_side is distinct from p_side then
    v_c := least(v_most, r.wins * v_step);
    return case when p_side = 'sell' then 1 - v_c else 1 + v_c end;
  end if;
  if v_has then
    v_c := least(r.concession, r.wins * v_step);
  end if;
  v_used := case when v_has then r.attempts else 0 end;
  v_n := public.job_bargain_tries(p_fleet);
  if v_n > v_used then
    v_c := v_c + v_step * public.bargain_p1(v_player, p_port, p_good, p_fleet)
                 * (select coalesce(sum(power(public.wc_num('bargain_decay'), k)), 0) from generate_series(v_used, v_n - 1) k);
  end if;
  v_c := least(v_most, v_c);
  return case when p_side = 'buy' then 1 - v_c else 1 + v_c end;
end
$body$
  $f$;

  execute $f$
create function public.bargain_state(p_player uuid, p_fleet uuid, p_port uuid, p_good uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: WHAT world.haggle_state ADDS WHILE THE SWITCH IS LIT, under the one key `bargain` (dark: nothing, so its answer is as before):
-- the step and the most in per cent of her TOTAL, what she holds, the side the day's row is on, the chance of her first try, the
-- factor her buy and her sale are quoted at now, and the tries a standing job of this fleet may make.
declare
  r record;
begin
  if not public.bargain_on() then
    return '{}'::jsonb;
  end if;
  select h.wins, h.concession, h.last_side, h.attempts into r from public.haggle_daily h
   where h.player_id = p_player and h.port_id = p_port and h.good_id = p_good and h.day = public.real_day(now());
  return jsonb_build_object('bargain', jsonb_build_object(
    'of', 'total',
    'step_pct', round(public.wc_num('bargain_step') * 100, 1),
    'most_pct', round(public.haggle_cap() * 100, 1),
    'held_pct', round(coalesce(least(r.concession, r.wins * public.wc_num('bargain_step')), 0) * 100, 1),
    'side', case when coalesce(r.attempts, 0) > 0 then r.last_side end,
    'first_odds', public.bargain_p1(p_player, p_port, p_good, p_fleet),
    'buy_factor', public.bargain_factor(p_fleet, p_port, p_good, 'buy'),
    'sell_factor', public.bargain_factor(p_fleet, p_port, p_good, 'sell'),
    'job_tries', public.job_bargain_tries(p_fleet)));
end
$body$
  $f$;

  execute $f$
create function public.bargain_first(p_fleet uuid, p_port uuid, p_good uuid, p_side text, p_total numeric, p_first numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0506: ONE BARGAIN, ONE TRADE, in a day of runs (public.run_day). p_total is world.quote's total of all the runs' units, p_first the first
-- run's: both carry the bargain's factor. The day's bargain is spent by its first trade, so only p_first keeps it and the rest is the
-- plain price: p_total / factor + p_first x (1 - 1 / factor). The other side of a bargained row (the resale guard) holds all day: as it
-- is. Dark, or no bargain: p_total, untouched.
declare
  v_f numeric;
begin
  if p_total is null or p_first is null or not public.bargain_on() then
    return p_total;
  end if;
  v_f := public.bargain_factor(p_fleet, p_port, p_good, p_side);
  if v_f = 1 or v_f <= 0 or exists (select 1 from public.haggle_daily h join public.fleets f on f.player_id = h.player_id
       where f.id = p_fleet and h.port_id = p_port and h.good_id = p_good and h.day = public.real_day(now())
         and h.attempts > 0 and h.last_side is distinct from p_side) then
    return p_total;
  end if;
  return round(p_total / v_f + p_first * (1 - 1 / v_f));
end
$body$
  $f$;

  -- grants: all server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 6. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0506 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0506 values
  ('cmd.haggle(uuid,uuid,text)', 1,
$h$  v_player  uuid := public.current_player_id();
$h$,
$h$  v_player  uuid := coalesce(public.bargain_actor(), public.current_player_id());   -- 0506: a standing job bargains for its own company (public.job_bargain); else the signed-in one, as before
$h$),
  ('cmd.haggle(uuid,uuid,text)', 2,
$h$  v_max     int  := public.wc_int('haggle_attempts_per_day');
$h$,
$h$  v_max     int  := public.haggle_attempts_max();   -- 0506 (dark: bargain_total_enabled): 10 lit, haggle_attempts_per_day as before
$h$),
  ('cmd.haggle(uuid,uuid,text)', 3,
$h$  v_step    numeric := public.wc_num('haggle_concession_step');
$h$,
$h$  v_step    numeric := public.haggle_step();   -- 0506: lit, 5 % of her TOTAL a win (public.bargain_factor); dark, the share of the spread as before
$h$),
  ('cmd.haggle(uuid,uuid,text)', 4,
$h$  v_cap     numeric := public.wc_num('haggle_concession_max');
$h$,
$h$  v_cap     numeric := public.haggle_cap();   -- 0506: lit, every try won (50 %); dark, haggle_concession_max as before
$h$),
  ('cmd.haggle(uuid,uuid,text)', 5,
$h$  v_used := coalesce(v_used, 0);
  if v_used >= v_max then
$h$,
$h$  v_used := coalesce(v_used, 0);
  -- 0506 (dark: nothing): the day's row is one side only (the same-day resale guard)
  if public.bargain_side_refusal(v_player, f.port_id, g.id, v_side) is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_BARGAIN_SIDE',
      'error_message', public.bargain_side_refusal(v_player, f.port_id, g.id, v_side),
      'fixes', jsonb_build_array('(trade at the price offered)', '(come back tomorrow)', '(bargain over a different good)'));
  end if;
  if v_used >= v_max then
$h$),
  ('cmd.haggle(uuid,uuid,text)', 6,
$h$  perform public.emit_event(v_player, 'HAGGLED', jsonb_build_object(
$h$,
$h$  perform public.bargain_xp(v_player, v_won);   -- 0506 (dark: nothing): a bargain she tried herself is experience in Negotiation
  perform public.emit_event(v_player, 'HAGGLED', jsonb_build_object(
$h$),
  ('public.haggle_odds(uuid,uuid,uuid,uuid)', 1,
$h$begin
  select greatest(0, h.attempts - h.wins) into v_fails
$h$,
$h$begin
  -- 0506 (dark: bargain_total_enabled): lit, the chance falls on EVERY try, won or lost: p1 x bargain_decay^(tries spent) (public.bargain_odds)
  if public.bargain_on() then
    return public.bargain_odds(p_player, p_port, p_good, p_fleet);
  end if;
  select greatest(0, h.attempts - h.wins) into v_fails
$h$),
  ('world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)', 1,
$h$      v_hag := public.haggle_concession(v_player, p_port, p_good);
$h$,
$h$      -- 0506 (dark: bargain_total_enabled): lit, a bargain moves her TOTAL (public.bargain_factor in world.quote_priced), never the spread
      v_hag := case when public.bargain_on() then 0 else public.haggle_concession(v_player, p_port, p_good) end;
$h$),
  ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 1,
$h$  units     := v_units;
$h$,
$h$  -- 0506 (dark: bargain_total_enabled): lit, HER BARGAIN IS A SHARE OF HER TOTAL (public.bargain_factor: 5 % a win, the resale guard, a
  -- standing job's expected tries), applied here, in the one quote, so every face and the door read the same figure. Nobody else's
  -- quote, the mid and the published price are untouched. (v_unit is free once the walk is done; it holds the factor.)
  if p_fleet is not null and public.bargain_on() then
    v_unit  := public.bargain_factor(p_fleet, p_port, p_good, p_side);
    v_hag_t := v_hag_t + case when p_side = 'buy' then v_total - v_total * v_unit else v_total * v_unit - v_total end;
    v_total := v_total * v_unit;
  end if;
  units     := v_units;
$h$),
  ('world.haggle_state(uuid,uuid)', 1,
$h$  v_max    int := public.wc_int('haggle_attempts_per_day');
$h$,
$h$  v_max    int := public.haggle_attempts_max();   -- 0506 (dark: bargain_total_enabled): 10 lit, haggle_attempts_per_day as before
$h$),
  ('world.haggle_state(uuid,uuid)', 2,
$h$    'spent_on', 'the next trade of this good at this port, or the day''s end');
$h$,
$h$    'spent_on', 'the next trade of this good at this port, or the day''s end')
    || public.bargain_state(v_player, p_fleet, f.port_id, p_good);   -- 0506: lit, the key `bargain` (a share of her total); dark, nothing
$h$),
  ('cmd.do_buy(uuid,jsonb)', 1,
$h$  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$,
$h$  perform public.job_bargain(p_fleet, g.id, 'buy');   -- 0506 (dark: nothing): a standing job makes its tries first, through cmd.haggle
  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$),
  ('cmd.do_sell(uuid,jsonb)', 1,
$h$  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$,
$h$  perform public.job_bargain(p_fleet, g.id, 'sell');   -- 0506 (dark: nothing): a standing job makes its tries first, through cmd.haggle
  v_conc := public.haggle_concession(f.player_id, f.port_id, g.id);
$h$),
  ('public.level_skills_card(uuid,jsonb)', 1,
$h$                where s.side = 'sea' or public.land_skill_on(s.code)))   -- 0461: and its own switch   -- 0455: a land skill only while land_enabled
$h$,
$h$                where (s.side = 'sea' and (s.lit_by is null or public.wc(s.lit_by) = 'true'::jsonb))   -- 0506: a sea level that waits for its switch (Negotiation)
                   or (s.side = 'land' and public.land_skill_on(s.code))))   -- 0461: and its own switch   -- 0455: a land skill only while land_enabled
$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
$h$,
$h$  -- 0506 (dark: nothing): the job setting `bargain` (false = this job does not bargain; the default is on)
  if public.bargain_on() then
    v_p := v_p || public.job_bargain_param(p_params);
  end if;
  insert into public.fleet_jobs as j (fleet_id, player_id, kind, params, since, seen_at)
$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 1,
$h$    select q.units, q.total into v_got, v_buy from$h$,
$h$    select q.units, public.bargain_first(p_fleet, p_buy, p_good, 'buy', q.total, p_cost) /* 0506 (dark: nothing): a bargain is one trade's */ into v_got, v_buy from$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 2,
$h$        select q.total into v_buy from$h$,
$h$        select public.bargain_first(p_fleet, p_buy, p_good, 'buy', q.total, p_cost) /* 0506 (dark: nothing): a bargain is one trade's */ into v_buy from$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 3,
$h$    select q.units, q.total into v_got, v_sale from$h$,
$h$    select q.units, public.bargain_first(p_fleet, p_sell, p_good, 'sell', q.total, p_gross) /* 0506 (dark: nothing): a bargain is one trade's */ into v_got, v_sale from$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 4,
$h$        select q.total into v_cb from$h$,
$h$        select public.bargain_first(p_fleet, p_buy, p_good, 'buy', q.total, p_cost) /* 0506 (dark: nothing): a bargain is one trade's */ into v_cb from$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 5,
$h$        select q.total into v_cs from$h$,
$h$        select public.bargain_first(p_fleet, p_sell, p_good, 'sell', q.total, p_gross) /* 0506 (dark: nothing): a bargain is one trade's */ into v_cs from$h$);

  for x in select distinct h.fn from hunks_0506 h loop
    v_pre := (select p.def from pre_0506 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0506 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0506 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0506 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0506 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0506 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0506) <> 20 or (select count(distinct h.fn) from hunks_0506 h) <> 10 then
    raise exception '0506 self-assert FAIL: the hunks are not the 20 of the ten re-cut bodies';
  end if;

  -- ── 7. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0506 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0506 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before
     or public.bargain_on() or public.haggle_attempts_max() <> public.wc_int('haggle_attempts_per_day')
     or public.haggle_step() <> public.wc_num('haggle_concession_step') or public.haggle_cap() <> public.wc_num('haggle_concession_max') then
    raise exception '0506 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute')) then
    raise exception '0506 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 8. DARK IDENTITY ──
  begin
    raise exception using errcode = 'ZX506', message = pg_temp.scene_0506(c_ua, 'dark')::text;
  exception when sqlstate 'ZX506' then v_d := sqlerrm::jsonb;
  end;
  if v_d is distinct from v_b then
    raise exception '0506 self-assert FAIL: DARK IS NOT IDENTICAL. Before: % After: %', left(v_b::text, 1200), left(v_d::text, 1200);
  end if;

  -- ── 9. LIT ──
  begin
    raise exception using errcode = 'ZX506', message = pg_temp.scene_0506(c_ua, 'lit')::text;
  exception when sqlstate 'ZX506' then v_l := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0506(uuid, text);
  drop function pg_temp.job_0506(uuid, uuid, jsonb);

  -- THE CURVE: 0.25, then half of it at every try spent; ten tries; the level adds 19 points; the ceiling is 0.50
  if v_l->'curve' is distinct from '[0.2500, 0.1250, 0.0625, 0.0313]'::jsonb or (v_l->>'max')::int <> 10 or (v_l->>'p1')::numeric <> 0.25
     or (v_l->>'p1_l20')::numeric <> 0.44 or (v_l->>'p1_cap')::numeric <> 0.50 then
    raise exception '0506 self-assert FAIL: the chance is not p1 x 0.5^(n-1) with the level and the ceiling: % % % % %', v_l->'curve', v_l->'max', v_l->'p1', v_l->'p1_l20', v_l->'p1_cap';
  end if;
  -- TEN LOST TRIES move nothing; the eleventh is refused
  v_x := v_l->'lost';
  if v_x->'q1' <> v_x->'q0' or v_x->>'eleventh' <> 'E_HAGGLE_SPENT' or v_x->'row' <> '[10, 0, 0]'::jsonb then
    raise exception '0506 self-assert FAIL: ten lost tries moved her price, or an eleventh was heard: %', v_x;
  end if;
  -- ONE WIN IS 5 % OF HER TOTAL, THREE 15 % (to the coin: the total is ceiled once); nobody else's quote moved; the other side refused
  v_x := v_l->'win1';
  if (v_x->>'won')::boolean is not true or (v_x->>'pct')::numeric <> 5.0 or (v_x->>'q1')::bigint not between floor((v_x->>'q0')::numeric * 0.95) - 1 and ceil((v_x->>'q0')::numeric * 0.95)
     or (v_x->>'q1')::bigint >= (v_x->>'q0')::bigint
     or v_x #>> '{state,of}' <> 'total' or (v_x #>> '{state,held_pct}')::numeric <> 5.0 or (v_x #>> '{state,buy_factor}')::numeric <> 0.95 or v_x #>> '{state,side}' <> 'buy' then
    raise exception '0506 self-assert FAIL: one win is not 5 %% of her total: %', v_x;
  end if;
  v_x := v_l->'win3';
  if (v_x->>'q1')::bigint not between floor((v_x->>'q0')::numeric * 0.85) - 1 and ceil((v_x->>'q0')::numeric * 0.85)
     or (v_x->>'any_same')::boolean is not true then
    raise exception '0506 self-assert FAIL: three wins are not 15 %%, or another''s price moved: %', v_x;
  end if;
  -- THE TRADE charges the quote and spends it; a second trade gets none
  v_x := v_l->'spend';
  if v_x->'paid' <> v_x->'quoted' or (v_x->>'left')::numeric <> 0 or (v_x->>'factor_after')::numeric <> 1 then
    raise exception '0506 self-assert FAIL: the trade did not charge the quoted price, or did not spend the bargain: %', v_x;
  end if;
  -- THE RESALE on the same quay the same day: the city takes back its 15 %; she gets no more than she paid
  v_x := v_l->'resale';
  if v_x->>'other_side' is distinct from 'E_BARGAIN_SIDE' or (v_x->>'factor')::numeric <> 0.85 or (v_x->>'got')::bigint > (v_x->>'paid')::bigint
     or v_x->'got' <> v_x->'quoted' then
    raise exception '0506 self-assert FAIL: a good bought with a bargain sold on the same quay for more than was paid: %', v_x;
  end if;
  -- SELLING: two wins add 10 % to her total, the sale pays the quote; buying it back there costs 10 % more
  v_x := v_l->'sell';
  if (v_x->>'s1')::bigint not between floor((v_x->>'s0')::numeric * 1.10) and ceil((v_x->>'s0')::numeric * 1.10) + 1 or v_x->'got' <> v_x->'s1'
     or (v_x->>'back_factor')::numeric <> 1.10 or (v_x->>'back_hers')::bigint < (v_x->>'got')::bigint then
    raise exception '0506 self-assert FAIL: a selling bargain is not + 5 %% a win, or the good was bought back for less than it sold: %', v_x;
  end if;
  -- A JOB: below level 8 none; 3 / 6 / 10 tries at 8 / 12 / 16 (and 20); its quote is the EXPECTED factor, above the best
  if v_l->'tries' is distinct from '[0, 3, 6, 10, 10]'::jsonb then
    raise exception '0506 self-assert FAIL: a job''s tries are not 0 / 3 / 6 / 10 by her level: %', v_l->'tries';
  end if;
  if (v_l #>> '{expected,3}')::numeric <> 0.32
     or abs((v_l #>> '{expected,0}')::numeric - (1 - 0.05 * (v_l #>> '{expected,2}')::numeric * 1.75)) > 0.000000001
     or (v_l #>> '{expected,0}')::numeric <= 0.85 or (v_l #>> '{expected,0}')::numeric >= 1
     or round((v_l #>> '{expected,0}')::numeric + (v_l #>> '{expected,1}')::numeric, 9) <> 2 then
    raise exception '0506 self-assert FAIL: a job''s quote is not the expected bargain: %', v_l->'expected';
  end if;
  if (v_l #>> '{day,0}')::numeric <> 4972 or (v_l #>> '{day,1}')::numeric <> 5028 then
    raise exception '0506 self-assert FAIL: a day of runs counts the bargain on more than its first run: %', v_l->'day';
  end if;
  if v_l->'off' is distinct from '[0, 1, {"bargain": false}, {}, {}]'::jsonb then
    raise exception '0506 self-assert FAIL: the job setting off still bargains: %', v_l->'off';
  end if;
  -- its buy made the three tries through cmd.haggle (three HAGGLED events, the row at 3), was charged 15 % less, earned no experience;
  -- a second buy that day made none
  v_x := v_l->'jobbuy';
  if v_x->'row' is distinct from '[3, 3, 0, "buy"]'::jsonb or (v_x->>'events')::int <> 3 or (v_x->>'xp')::int <> 0
     or (v_x->>'paid')::bigint not between floor((v_x->>'plain')::numeric * 0.85) - 1 and ceil((v_x->>'plain')::numeric * 0.85) then
    raise exception '0506 self-assert FAIL: a job''s buy did not bargain three times through cmd.haggle and pay 15 %% less: %', v_x;
  end if;
  v_x := v_l->'jobbuy2';
  if (v_x->>'attempts')::int <> 3 or v_x->'paid' <> v_x->'plain' then
    raise exception '0506 self-assert FAIL: a second run the same day bargained again: %', v_x;
  end if;
  -- her own try earns experience; the level is on her card only while lit; the setting is kept by the door only while lit
  if (v_l->>'xp_own')::int is distinct from 20 or (v_l->>'card_lit')::boolean is not true or (v_l->>'card_dark')::boolean is not false
     or v_l->'job' ? 'bargain' or v_l->'job' ? 'refused' or v_l #>> '{job_lit,bargain}' is distinct from 'false' then
    raise exception '0506 self-assert FAIL: the level, its card or the job setting: xp % card % / % job % / %', v_l->'xp_own', v_l->'card_lit', v_l->'card_dark', v_l->'job', v_l->'job_lit';
  end if;

  -- ── 10. NOTHING OF THE PROBE SURVIVES; the switch is dark ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0506') or public.bargain_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0506 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0506 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0506 self-assert ok: TEN BARGAINS, FIVE PER CENT EACH (dark). 20 hunks once and reversing in ten bodies; no other function moved; grants and settings unmoved; fifteen new functions server only; six knobs (bargain_total_enabled false), no other moved; the level Negotiation in the level tables, hidden while dark. DARK IDENTICAL: a bargain won, its state, its quote, the buy that spends it, the fourth try refused, a sale, the card, a job set: equal. LIT (no outcome hangs on the dice or the market): the chance 0.25, 0.125, 0.0625, 0.0313; level 20 -> 0.44; ceiling 0.50; ten lost tries moved nothing, the eleventh refused; one win % -> % (5 %%), three wins % (15 %%), nobody else''s quote moved; the trade paid the quote and spent it; the other side refused (E_BARGAIN_SIDE) and the same-day resale paid % for what cost %; two selling wins % -> %; a job below level 8 none, 3 / 6 / 10 tries at 8 / 12 / 16, its quote the expected factor % (best 0.85), its buy three tries through cmd.haggle and 15 %% less, a second run none, the setting off none. % ms.',
    v_l #>> '{win1,q0}', v_l #>> '{win1,q1}', v_l #>> '{win3,q1}', v_l #>> '{resale,got}', v_l #>> '{resale,paid}', v_l #>> '{sell,s0}', v_l #>> '{sell,s1}',
    v_l #>> '{expected,0}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0506;
  drop table pre_0506;
end $m$;

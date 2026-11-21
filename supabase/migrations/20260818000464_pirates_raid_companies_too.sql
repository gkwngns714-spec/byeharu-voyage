-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0464 - PIRATES RAID COMPANIES TOO  (dark: the owner's switch raid_companies_enabled, false; lit, a pirate takes the nearest ship in reach,
--        whoever owns her, and passes over a company whose title is under Master)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-22: "make this game a proper game" (settles the open decision of docs/design/content-plan-2026-11.md 5.6, row 1).
-- THE DESIGN: docs/design/content-plan-2026-11.md 5.3 item 1, 5.4 row A, 5.6 defaults. docs/dev-log/2026-11-22-raid-companies.md.
--
-- WHY NO COMPANY HAS BEEN RAIDED (prod, 2026-11-16, docs/dev-log/2026-11-16-evasion.md B2): 2,339 closed raids in 48 h, 0 on a company's ship.
--   public.raid_target orders the ships in reach by 0432's rule "the world's merchants first, then a player's" (fleet_kind = 'COMPANY' sorts last),
--   so a company is taken only when no merchant or crown cargo ship is within reach, which on the open sea is never.
--
-- WHAT THIS FILE DOES (one body, public.raid_target, two hunks, each once and reversing):
--   R1. THE SWITCH raid_companies_enabled (false, DARK). False: 0432's order and nothing else, to the row (asserted below on the live pirates).
--       True: the NEAREST ship in reach wins, a merchant's, a crown's or a company's alike (0427's own rule, before 0432 put the world first).
--   R2. THE BEGINNER'S PEACE (lit only): a company whose title (public.title_level: the lower of Trading and Exploration) is under
--       raid_company_title_min (3, Master) is passed over, so a new company sails her first half hour or so unmolested. A title unknown (null)
--       is not passed over (0215: only a merchant's title is null).
--   R3. THE WEIGHT (lit only): a company's ship is ordered by her miles x raid_company_weight (1: as near as she is). Over 1 a pirate looks at
--       a company's ship as if further off (rarer), under 1 nearer. Reach itself is unchanged: she must still be within attack_reach_nm.
--   Decided by default (the design's 5.6): nearest wins; passed over under Master; weight 1. All three are knobs; the switch is the owner's to light.
-- NOT CHANGED: how many raids the pirates open (pirate_strikes_per_run, pirate_strike_minutes), the fight, Run, Pay, the standing order, the
--   peace after a fight, insurance, Evasion; a voyage day's raid (public.fight_sides, 0357) keeps its own rule. No client change: a company's ship
--   set upon already gets the battle card, the action bar and her BATTLE_REPORT (0427, 0439).
-- ROWS: none while dark. Lit: no more raids than today (at most pirate_strikes_per_run, 2, a minute); a raid on a company writes her BATTLE_REPORT
--   event and at most 2 level_book + 1 level_xp rows (Evasion, 0453) beyond a merchant's raid. -- budget: none (no table, no job, no index, no cron).
--   -- retention: none.
-- COST: lit, public.title_level once per company candidate in a pirate's sieve (at most 8 pirates asked a minute; prod has 19 companies).
-- LOCKS: CREATE OR REPLACE x1 by hunks. No new function. TIME: a few seconds. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, raid_companies_enabled false (0432's order, to the row). Full: a new migration reversing the two hunks
--   (their OLD texts are below verbatim) and deleting the three knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; raid_target's grants, volatility, definer, search path, owner unmoved; the
--   knobs; DARK IS TODAY: up to 4 hunting pirates of this world choose the same ship after the hunks as before; THE PROBE (rolled back): a probe
--   pirate and a probe company (title Apprentice) at one point far out in the South Pacific: dark, she is chosen as today (no merchant in reach);
--   lit, she is passed over; lit with raid_company_title_min 1, she is chosen. Proof 167 proves nearest-wins against a merchant and the weight.
-- VERSION: 0464 = prod head 0462 + 2 (0463 is #775, open; this file touches none of its bodies and does not read it).
-- news: none (dark: nothing changes for a player until the owner lights raid_companies_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.raid_target(uuid,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_pirates   uuid[];
  v_before    uuid[];
  v_after     uuid[];
  v_note      text := 'no hunting pirate in this world';
  v_nat       uuid;
  v_port      uuid;
  v_pirp      uuid;
  v_pir       uuid;
  v_mep       uuid;
  v_me        uuid;
  v_t         uuid;
  v_dark      uuid;
  v_peace     uuid;
  v_lit       uuid;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'raid_companies_enabled') then
    raise exception '0464 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.raid_target(uuid,timestamp with time zone)') is null or to_regprocedure('public.fleet_peace_until(uuid)') is null
     or to_regprocedure('public.title_level(uuid)') is null or to_regclass('public.pirate_ships_cruising') is null then
    raise exception '0464 refuses: 0427 (the raids), 0432 (the world first, the peace) or 0215 (the title) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE, and what the live pirates choose today ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select coalesce(array_agg(q.fleet_id order by q.ord), '{}') into v_pirates
    from (select c.fleet_id, c.ord from public.pirate_ships_cruising c join public.fleets f on f.id = c.fleet_id
           where f.busy_until is null order by c.ord limit 4) q;
  select coalesce(array_agg(public.raid_target(u.p, now()) order by u.i), '{}') into v_before from unnest(v_pirates) with ordinality u(p, i);

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('raid_companies_enabled', 'false'::jsonb, '0464: THE SWITCH (the owner''s). false: a pirate takes the world''s merchants first, then a company''s ship (0432). true: the nearest ship in reach wins, whoever owns her; a company under raid_company_title_min is passed over; a company''s miles are weighed by raid_company_weight (public.raid_target).'),
    ('raid_company_title_min', to_jsonb(3), '0464: lit, a company whose title (public.title_level) is under this is passed over by every pirate: the beginner''s peace. 3 = Master. 1: nobody is passed over.'),
    ('raid_company_weight', to_jsonb(1), '0464: lit, a company''s ship is ordered by her miles times this (1: as near as she is; 2: as if twice as far, so rarer; 0.5: likelier). Reach (attack_reach_nm) is unchanged.');

  -- ── 3. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0464 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0464 values
  ('public.raid_target(uuid,timestamp with time zone)', 1,
$h$  v_nm    numeric;$h$,
$h$  v_nm    numeric;
  v_lit   boolean := coalesce(public.wc('raid_companies_enabled') = 'true'::jsonb, false);   -- 0464: the owner's switch; false: 0432's order, to the row
  v_title int := coalesce(public.wc_int('raid_company_title_min'), 1);                         -- 0464: lit, a company under this title is passed over
  v_w     numeric := coalesce(public.wc_num('raid_company_weight'), 1);                        -- 0464: lit, a company's miles are weighed by this$h$),
  ('public.raid_target(uuid,timestamp with time zone)', 2,
$h$     where public.fleet_kind(c.id) in ('MERCHANT', 'CARGO_SHIP', 'COMPANY')
     order by public.fleet_kind(c.id) = 'COMPANY', c.nm, c.id   -- 0432: the world's merchants first ("pirates' main goal is to attack other npcs"), then a player's$h$,
$h$     where public.fleet_kind(c.id) in ('MERCHANT', 'CARGO_SHIP', 'COMPANY')
       -- 0464: lit, the beginner's peace: a company whose title is under raid_company_title_min (3, Master) is passed over
       and case when not v_lit then true
                when public.fleet_kind(c.id) <> 'COMPANY' then true
                else coalesce(public.title_level((select f.player_id from public.fleets f where f.id = c.id)), v_title) >= v_title end
     -- 0432: the world's merchants first ("pirates' main goal is to attack other npcs"), then a player's; 0464 lit: the nearest wins, whoever owns her,
     -- a company's miles weighed by raid_company_weight
     order by case when v_lit then false else public.fleet_kind(c.id) = 'COMPANY' end,
              c.nm * case when v_lit and public.fleet_kind(c.id) = 'COMPANY' then v_w else 1 end, c.id$h$);

  for v_h in select h.fn from hunks_0464 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0464 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0464 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0464 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0464 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0464 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the knobs, dark is today ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_fn_before then
    raise exception '0464 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0464 self-assert FAIL: the grants, volatility, definer, search path or owner of public.raid_target moved';
  end if;
  if public.wc('raid_companies_enabled') <> 'false'::jsonb or public.wc_int('raid_company_title_min') <> 3 or public.wc_num('raid_company_weight') <> 1 then
    raise exception '0464 self-assert FAIL: the knobs are not this file''s';
  end if;
  select coalesce(array_agg(public.raid_target(u.p, now()) order by u.i), '{}') into v_after from unnest(v_pirates) with ordinality u(p, i);
  if v_after is distinct from v_before then
    raise exception '0464 self-assert FAIL: dark, a hunting pirate chose another ship than before this file: % / %', v_before, v_after;
  end if;
  if cardinality(v_pirates) > 0 then
    v_note := format('%s hunting pirate(s) chose the same ship dark as before (%s with a target)', cardinality(v_pirates),
                     (select count(*) from unnest(v_after) a where a is not null));
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel: a pirate and a beginner company at one point far out in the South Pacific ──
  begin
    select n.id into v_nat from public.nations n where n.code = 'PRT';
    select p.id into v_port from public.ports p where p.code = 'LIS';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values ('00000000-0464-4000-8000-0000000000c1', 'Casa Presa 0464', v_nat, 0, false) returning id into v_mep;
    v_me := public.form_fleet(v_mep, 'Presa 0464', v_port);
    perform public.commission_ship(v_mep, v_me, 'carlat', 'Presa 0464', true, true);
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Lobos 0464', public.pirate_nation(), 0, true) returning id into v_pirp;
    v_pir := public.form_fleet(v_pirp, 'Lobos 0464', v_port);
    perform public.commission_ship(v_pirp, v_pir, 'xebec', 'Lobos 0464', true, true);
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id in (v_me, v_pir);
    update public.fleets f set status = 'ANCHORED', port_id = null, lat = -50.0, lon = -140.0, busy_until = null, ready_at = null where f.id in (v_me, v_pir);
    if public.title_level(v_mep) is distinct from 1 then
      raise exception '0464 self-assert FAIL: the probe company is not an Apprentice: title %', public.title_level(v_mep);
    end if;
    -- dark: today's rule; nothing of the world's lies out there, so she is taken (a merchant or crown ship, were one in reach, would come first)
    v_dark := public.raid_target(v_pir, now());
    if v_dark is distinct from v_me and coalesce(public.fleet_kind(v_dark), '-') not in ('MERCHANT', 'CARGO_SHIP') then
      raise exception '0464 self-assert FAIL: dark, the pirate chose % (%), not the company nor a ship of the world', v_dark, public.fleet_kind(v_dark);
    end if;
    -- lit: the beginner's peace passes her over
    update public.world_config set value = 'true'::jsonb where key = 'raid_companies_enabled';
    v_peace := public.raid_target(v_pir, now());
    if v_peace is not distinct from v_me then
      raise exception '0464 self-assert FAIL: lit, an Apprentice company was chosen under raid_company_title_min %', public.wc_int('raid_company_title_min');
    end if;
    -- lit, nobody passed over: she lies at the pirate's own point, so she is the nearest and is chosen
    update public.world_config set value = to_jsonb(1) where key = 'raid_company_title_min';
    v_lit := public.raid_target(v_pir, now());
    if v_lit is distinct from v_me then
      raise exception '0464 self-assert FAIL: lit with raid_company_title_min 1, the pirate chose %, not the company beside her', v_lit;
    end if;
    v_note := v_note || format('; probe: dark %s, lit Apprentice passed over (%s), lit title 1 the company', coalesce(public.fleet_kind(v_dark), 'none'),
                               coalesce(public.fleet_kind(v_peace), 'none'));
    raise exception sqlstate 'BV464';
  exception when sqlstate 'BV464' then null;
  end;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0464 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0464 self-assert ok: PIRATES RAID COMPANIES TOO (dark). % hunks once each and reversing; grants and volatility unmoved; no other function moved; knobs raid_companies_enabled false, raid_company_title_min 3, raid_company_weight 1. %; % ms.',
    (select count(*) from hunks_0464), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0464;
end $m$;

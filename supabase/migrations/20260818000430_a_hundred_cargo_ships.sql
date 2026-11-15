-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0430 - A HUNDRED CARGO SHIPS  (the world keeps cargo_fleet_total (100) cargo ships, shared by the countries in proportion to their size,
--        the pirates included; an empty cargo ship sails straight home and never roams)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "make it so that pirates are active, we don't need 372 cargo ships... make it 150, reduce them but remember, each
-- countries including pirates should have cargo ships that are proportional to their size." Then: "i see cargoships without money, just roaming
-- around in ocean, wtf is this/" and "fix the issue. cargo ships are used for cities to deliver gold to poorer cities. reduce the cargo ship
-- number to 100 appropriately." (The 100 overrides the 150.)
--
-- WHY (prod, 2026-11-15, read by the lead; docs/dev-log/2026-11-15-a-hundred-cargo-ships.md): 372 cargo ships, 120 at sea, ~236 idle at home
--   with nothing to carry, 11 laid up. 136 sailing, of them 79 EMPTY, and 77 of those not heading home: each sailing on between her own
--   country's cities after a DELIVERED (LIS RIO->CAP after SLV; LIS NAM->MCH after DIU; BSR ACC->ANG after KAN; ...).
--
-- ROOT CAUSE OF THE ROAMING (public.cargo_ship_step, 0309/0324, away from home): after a city's delivery she always takes the next leg of her
--   circuit, `v_leg := c.leg + 1`, whether or not anything is left aboard. A circuit visits every city of her realm and only its last leg comes
--   home, so a ship emptied at her first city sails the whole rest of the circuit with nothing aboard.
--
-- WHAT THIS FILE DOES:
--   S1. THE SHARE (public.convoy_ships_wanted, re-cut whole): SIZE IS A COUNTRY'S HARBOURS, the harbours under its flag (public.port_allegiance,
--       kind HARBOUR): the same count the cash of a country is summed over (public.realm_purse), but not its purse, which swings by millions an
--       hour. Every great power with a harbour, THE PIRATES INCLUDED, keeps 1, and the rest of cargo_fleet_total is shared by harbours, whole
--       ships by the largest remainder, so the shares sum to the total exactly. A power with no harbour has no share (0 ships).
--   S2. THE NUMBER IS THE SHARE (public.convoy_fleet_settle, re-cut): each convoy_size_read_minutes it writes every power's share exactly, and
--       drops the row of a power with no share. The dead band is gone: a band would let the total drift from cargo_fleet_total. Shares move
--       only when a harbour changes flag. public.convoy_ships_of answers 0, not convoy_ships_min, for a power with no row.
--   S3. THE SURPLUS RETIRES SAFELY, by the path 0326 built: public.cargo_ships_retire lays up a ship whose ord is above her country's number,
--       DOCKED at her home, no lap, nothing aboard, no wreck; highest ord first, convoy_retire_per_run a run (3 -> 10). A ship at sea, or with
--       funds aboard, takes no new load (public.cargo_ships_load: ord inside the number) and lays up when she is home and empty. Laying up
--       writes laid_up_at and nothing else: no gold, no goods, no ledger row; her hull stays hers (hulls are free, her house's purse is 0, 0308).
--       A laid-up ship takes no step and is off the map; a rise of a share wakes her in her ord (0326), so no row is ever added for her again.
--   S4. AN EMPTY SHIP SAILS HOME (public.cargo_ship_step, 2 hunks): away from home on a lap, once nothing is left aboard after the city's
--       delivery, she sails ONE leg straight home (public.cargo_circuit_plan, the course every rebase leg takes), and at home the lap closes
--       as before (HOME: what is left returned, mended, the lap cleared). With funds still aboard she sails on to the next city, as before.
--   KNOBS: + cargo_fleet_total 100. RETIRED (no body reads them after this file; the self-assert scans the catalog): convoy_ships_min,
--       convoy_ships_max, convoy_ships_span, convoy_ships_band. convoy_retire_per_run 3 -> 10 (an owner's own value is left and named).
--
-- THE PIRATES: their share is public.convoy_ships_of(<the Brethren>), written now. The crown cargo job still makes no ship for them (0338:
--   no circuit, no commission), so until the pirates' own cargo ships exist (0429, five gold ships from Port Royal) the world sails
--   cargo_fleet_total less the pirates' share. HOOK for 0429 or its follow-up: the pirates' gold ships count INSIDE their share, so the number of
--   them reads public.convoy_ships_of(<pirates>) and not a flat 5 (their share: 7 on the local world, 4 on prod's flags of 2026-11-15, one under five).
--
-- NOT DONE: no ship is deleted. A cargo ship's house and fleet are named by append-only rows (public.convoy_cargo, public.events), so 0326's law
--   stands: a ship is laid up, never deleted. The database does not shrink by rows; it stops growing (no ship is ever made again until a share
--   rises above the laid-up ords) and the job's work falls with the ships in service (see budget).
-- budget: the lay-ups are 1 row each, at most convoy_retire_per_run (10) rows a run of byeharu-voyage:cargo-ships (every minute) while the
--   ~270 surplus ships come home (~30 minutes for those idle now, the rest as their laps end), then 0 rows. The homeward legs replace the rest
--   of a circuit: fewer legs, so fewer voyage, stores and arrival rows a minute than today (77 ships roaming empty at the read). The settle reads
--   ~11 rows an hour, as before. No job is added or rescheduled, no table is made.
-- LOCKS: CREATE OR REPLACE x4 (by hunks); knobs; one UPSERT of ~11 rows of public.cargo_fleet_sizes.
-- TIME: the cut is milliseconds; the probe lays up surplus ships and sails one empty ship home, rolled back: under 5 s.
--   BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/cargo-150/rollback-0430.sql (a draft: the hunks reversed, the four knobs back at 0326's
--   values, cargo_fleet_total dropped). At once with no file: cargo_fleet_total 1000 gives every country far more than it has, so nothing more
--   lays up (and the job makes ships up to it: set it to the ships in service, ~360, to hold the fleet where it stands).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; no body names a
--   retired knob; the shares sum to the total, every harboured power (the pirates too) at least 1; then the probe, rolled back.
-- VERSION: 0430. 0427 (#706) and 0428 (#707) touch none of these bodies or knobs; 0429 (the pirates' gold ships) is not on main as written.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_meta      text;
  v_kept      text := '';
  v_h         record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_pir       uuid;
  v_note      text := 'no cargo ship docked at home over her share in this world: proof 131 lays them up';
  v_note2     text := 'no cargo ship in this world: proof 131 sails one home';
  v_fleet     uuid;
  v_home      uuid;
  v_at        uuid;
  v_w         bigint;
  v_r         text;
  v_cir       bigint;
  v_ord       int;
  v_load      bigint;
  c_retired   constant text[] := array['convoy_ships_min', 'convoy_ships_max', 'convoy_ships_span', 'convoy_ships_band'];
  c_hunked    constant text[] := array['public.convoy_ships_wanted()', 'public.convoy_ships_of(uuid)',
                                       'public.convoy_fleet_settle(timestamp with time zone)', 'public.cargo_ship_step(uuid,timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.cargo_fleet_sizes') is null or to_regprocedure('public.cargo_ships_retire(uuid,timestamp with time zone)') is null
     or to_regprocedure('public.cargo_circuit_plan(uuid,uuid,uuid)') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or not exists (select 1 from public.world_config where key = 'convoy_ships_band') then
    raise exception '0430 refuses: the fleet numbers (0326), the circuit planner, the news or 0326''s knobs are not all in this world';
  end if;
  if exists (select 1 from public.world_config where key = 'cargo_fleet_total') then
    raise exception '0430 refuses: it has been applied once';
  end if;
  select g.nation_id into v_pir from public.great_powers g where g.pirate;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('cargo_fleet_total', to_jsonb(100),
     '0430: the cargo ships of the whole world (owner 2026-11-15: "reduce the cargo ship number to 100"), shared by public.convoy_ships_wanted: every great power with a harbour, the pirates too, keeps 1, the rest by its harbours, whole ships by the largest remainder.');
  update public.world_config set value = to_jsonb(10),
         description = description || ' 0430: 3 -> 10 (the ~270 surplus ships of the cut to 100 lay up in about half an hour as they come home empty).'
   where key = 'convoy_retire_per_run' and value = to_jsonb(3);
  if not found then v_kept := v_kept || 'convoy_retire_per_run '; end if;
  delete from public.world_config c where c.key = any (c_retired);

  -- ── 3. THE HUNKS ──
  create temp table hunks_0430 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0430 values
  -- S1. the share
  ('public.convoy_ships_wanted()', 1,
$h$  -- 0326: THE curve (owner: "bigger country with more cash - max 50, min 20"). Cash: the summed public.treasury_balance of the harbours under a flag, so a bigger country has more. Log from lo to the richest, whole ships.
  -- lo is the larger of the poorest realm and the richest / convoy_ships_span, so the poorest is always min and a realm near nothing cannot stretch the rest. All level: min. Read by public.convoy_fleet_settle alone.
  with c as (
    select g.nation_id,
           public.realm_purse(g.nation_id) as cash   -- 0331: lifted
      from public.great_powers g
     where not g.pirate   -- 0338: the pirates have no crown, so no cargo ships
  ), b as (
    select max(c.cash)::numeric as hi, greatest(min(c.cash)::numeric, max(c.cash)::numeric / public.wc_num('convoy_ships_span'), 1) as lo from c
  )
  select c.nation_id, c.cash,
         case when b.hi <= b.lo then public.wc_int('convoy_ships_min')
              else public.wc_int('convoy_ships_min')
                   + round((public.wc_int('convoy_ships_max') - public.wc_int('convoy_ships_min')) * ln(greatest(c.cash::numeric, b.lo) / b.lo) / ln(b.hi / b.lo))::integer end
    from c cross join b
$h$,
$h$  -- 0430: THE SHARE (owner 2026-11-15: "each countries including pirates should have cargo ships that are proportional to their size"; "reduce the cargo ship number to 100").
  -- Size: the harbours under a flag (the harbours public.realm_purse sums). Every great power with a harbour, the pirates too, keeps 1; the rest of cargo_fleet_total is shared by harbours,
  -- whole ships by the largest remainder (ties: more harbours, then the code), so the shares sum to the total exactly. No harbour: no row, no share. cash: the purse, for the record.
  -- Read by public.convoy_fleet_settle alone.
  with s as (
    select g.nation_id, n.code,
           (select count(*) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = g.nation_id)::numeric as harbours
      from public.great_powers g join public.nations n on n.id = g.nation_id
  ), t as (
    select greatest(public.wc_int('cargo_fleet_total'), count(*))::numeric as total, count(*)::numeric as k, sum(s.harbours) as hs from s where s.harbours > 0
  ), q as (
    select s.nation_id, s.code, s.harbours, 1 + (t.total - t.k) * s.harbours / t.hs as quota from s cross join t where s.harbours > 0
  ), r as (
    select q.*, floor(q.quota)::integer as base,
           row_number() over (order by q.quota - floor(q.quota) desc, q.harbours desc, q.code) as rk from q
  )
  select r.nation_id, public.realm_purse(r.nation_id) as cash,
         r.base + case when r.rk <= (select t.total from t) - (select sum(r2.base) from r r2) then 1 else 0 end as ships
    from r
$h$),
  -- S2. no row: no ship
  ('public.convoy_ships_of(uuid)', 1,
$h$  -- 0326: THE ONE READER of how many cargo ships a country keeps: the number it rests at. A power with no row yet: min, until the next read of the curve.
  select coalesce((select s.ships from public.cargo_fleet_sizes s where s.nation_id = p_nation), public.wc_int('convoy_ships_min'))
$h$,
$h$  -- 0326: THE ONE READER of how many cargo ships a country keeps: the number it rests at. 0430: a power with no row has no share: 0.
  select coalesce((select s.ships from public.cargo_fleet_sizes s where s.nation_id = p_nation), 0)
$h$),
  -- S2. the number is the share
  ('public.convoy_fleet_settle(timestamp with time zone)', 1,
$h$-- 0326: the one writer of public.cargo_fleet_sizes. Each convoy_size_read_minutes it reads the curve once. A number moves only when the curve is more than convoy_ships_band from it, or it has left min..max: the dead band, so
-- ordinary swings of a purse never turn ships over. Answers how many numbers moved. Between reads: one indexed read.
$h$,
$h$-- 0326: the one writer of public.cargo_fleet_sizes. Each convoy_size_read_minutes it reads the curve once.
-- 0430: it writes every power's share (public.convoy_ships_wanted) exactly, so the numbers sum to cargo_fleet_total, and drops the row of a power with no share. No dead band: shares move only when a
-- harbour changes flag. Answers how many numbers moved. Between reads: one indexed read.
$h$),
  ('public.convoy_fleet_settle(timestamp with time zone)', 2,
$h$       set cash = excluded.cash, read_at = p_now,
           ships = case when abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')
                          or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')
                        then excluded.ships else s.ships end,
           set_at = case when abs(excluded.ships - s.ships) > public.wc_int('convoy_ships_band')
                           or s.ships not between public.wc_int('convoy_ships_min') and public.wc_int('convoy_ships_max')
                         then p_now else s.set_at end
    returning s.set_at
  )
  select count(*) into v_n from u where u.set_at = p_now;
$h$,
$h$       set cash = excluded.cash, read_at = p_now,
           ships = excluded.ships,
           set_at = case when excluded.ships <> s.ships then p_now else s.set_at end
    returning s.set_at
  ), d as (
    delete from public.cargo_fleet_sizes x where not exists (select 1 from w where w.nation_id = x.nation_id)
    returning x.nation_id
  )
  select (select count(*) from u where u.set_at = p_now) + (select count(*) from d) into v_n;
$h$),
  -- S4. an empty ship sails home
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$  v_cir   bigint;
  v_leg   int;
$h$,
$h$  v_cir   bigint;
  v_leg   int;
  v_home  jsonb;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
    -- 0430: EMPTY, SHE SAILS HOME. Nothing left aboard after this city: not the rest of the circuit (that was the roaming, owner 2026-11-15) but one leg straight home, the course
    -- a rebase leg takes. At home the lap closes as before (HOME). No course home: she goes on by the circuit, whose last leg is home.
    if c.out_load is not null and not exists (select 1 from public.cargo_ship_aboard(p_fleet)) then
      if f.ready_at is not null and f.ready_at > p_now then
        return 'IN_PORT';
      end if;
      v_home := public.cargo_circuit_plan(c.nation_id, f.port_id, c.home_port_id) #> '{legs,0}';
      if v_home is not null then
        perform public.cargo_upkeep(p_fleet, f.port_id);   -- 0328: this leg too, as every leg
        perform voyage.depart(p_fleet, voyage.segments_from_course(v_home -> 'course'), f.port_id, c.home_port_id, p_now);
        return 'HOMEWARD';
      end if;
    end if;
$h$);

  for v_h in select h.fn from hunks_0430 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0430 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0430 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0430 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0430 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0430 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 4. THE SHARES, written now (the next settle would write the same) ──
  update public.cargo_fleet_sizes set read_at = '-infinity';
  perform public.convoy_fleet_settle(now());

  -- ── 5. THE SELF-ASSERT: the catalog and the shares ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_fn_before then
    raise exception '0430 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta then
    raise exception '0430 self-assert FAIL: the grants, volatility, definer, search path or owner of a re-cut function moved';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace cross join unnest(c_retired) k
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and strpos(pg_get_functiondef(p.oid), k) > 0)
     or exists (select 1 from public.world_config c where c.key = any (c_retired)) then
    raise exception '0430 self-assert FAIL: a retired knob is still read or still stands';
  end if;
  if (select sum(s.ships) from public.cargo_fleet_sizes s) <> greatest(public.wc_int('cargo_fleet_total'), (select count(*) from public.cargo_fleet_sizes))
     or exists (select 1 from public.great_powers g
                 where exists (select 1 from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = g.nation_id)
                   and public.convoy_ships_of(g.nation_id) < 1)
     or (v_pir is not null and exists (select 1 from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = v_pir)
         and not exists (select 1 from public.cargo_fleet_sizes s where s.nation_id = v_pir)) then
    raise exception '0430 self-assert FAIL: the shares do not sum to the total, or a harboured power (the pirates?) has none: %',
      (select jsonb_object_agg(n.code, s.ships) from public.cargo_fleet_sizes s join public.nations n on n.id = s.nation_id);
  end if;

  -- ── 6. THE NEWS (0347's law) ──
  perform public.news_update('0430', 'A hundred cargo ships, shared by each country''s size; an empty cargo ship sails home',
                             '화물선은 100척, 나라 크기만큼 나눈다; 빈 화물선은 곧장 귀항한다');

  -- ── 7. THE PROBE, rolled back by a raised sentinel ──
  --   (a) the retire on the world as it stands: every ship it lays up is over her share, docked at her home, nothing aboard, no lap; at most the knob;
  --   (b) one cargo ship staged docked at another city of her realm on a lap with nothing aboard: her step sails her straight home, and no purse moves.
  begin
    v_w := (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) + public.funds_aboard();
    v_n := public.cargo_ships_retire(null, now());
    if v_n > public.wc_int('convoy_retire_per_run')
       or exists (select 1 from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
                   where c.laid_up_at = now()
                     and (c.ord <= public.convoy_ships_of(c.nation_id) or f.status <> 'DOCKED' or f.port_id <> c.home_port_id or c.out_load is not null
                          or c.circuit_id is not null or exists (select 1 from public.cargo_ship_aboard(c.fleet_id)))) then
      raise exception '0430 self-assert FAIL: the retire laid up a ship inside her share, away, on a lap or with funds aboard';
    end if;
    if v_n > 0 then
      v_note := v_n || ' surplus ships laid up in one run (the knob ' || public.wc_int('convoy_retire_per_run') || '), each home, empty and over her share';
    end if;
    -- a ship docked (not at sea), nothing aboard, with a closed load of her own to stand for her lap's load, and a circuit leg to another city of her realm
    select c.fleet_id, c.home_port_id, l.to_port, l.circuit_id, l.ord, b.id into v_fleet, v_home, v_at, v_cir, v_ord, v_load
      from public.cargo_ships_in_service c
      join public.fleets f on f.id = c.fleet_id and f.status = 'DOCKED'
      join lateral (select b0.id from public.convoy_cargo b0 where b0.fleet_id = c.fleet_id and b0.stage = 'LOADED' order by b0.id desc limit 1) b on true
      join public.cargo_circuits k on k.nation_id = c.nation_id
      join public.cargo_circuit_legs l on l.circuit_id = k.id and l.to_port <> c.home_port_id
     where not exists (select 1 from public.cargo_ship_aboard(c.fleet_id)) and public.port_nation(l.to_port) = c.nation_id
     order by c.nation_id, c.ord, l.ord
     limit 1;
    if v_fleet is not null then
      update public.fleets f set port_id = v_at, ready_at = null where f.id = v_fleet;
      update public.cargo_ships c set circuit_id = v_cir, leg = v_ord, out_load = v_load where c.fleet_id = v_fleet;
      v_r := public.cargo_ship_step(v_fleet, now());
      if v_r = 'HOMEWARD' then
        if (select f.status from public.fleets f where f.id = v_fleet) <> 'SAILING'
           or (select o.dest_port_id from public.voyages o where o.fleet_id = v_fleet and o.status = 'SAILING') <> v_home then
          raise exception '0430 self-assert FAIL: an empty ship said HOMEWARD but is not sailing home';
        end if;
        v_note2 := 'an empty ship on a lap at ' || (select p.code from public.ports p where p.id = v_at) || ' sailed straight home to '
                   || (select p.code from public.ports p where p.id = v_home);
      elsif v_r = 'SAILED' and public.cargo_circuit_plan((select c.nation_id from public.cargo_ships c where c.fleet_id = v_fleet), v_at, v_home) #> '{legs,0}' is null then
        v_note2 := 'an empty ship at ' || (select p.code from public.ports p where p.id = v_at) || ' has no course home: she went on by the circuit';
      else
        raise exception '0430 self-assert FAIL: an empty ship on a lap answered % and did not sail home', v_r;
      end if;
    end if;
    if (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) + public.funds_aboard() <> v_w then
      raise exception '0430 self-assert FAIL: the probe moved gold';
    end if;
    raise exception sqlstate 'BV430';
  exception when sqlstate 'BV430' then null;
  end;
  if exists (select 1 from public.cargo_ships c where c.laid_up_at = now()) or public.wc_int('cargo_fleet_total') <> 100 then
    raise exception '0430 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0430 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0430 self-assert ok: A HUNDRED CARGO SHIPS. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 4 knobs retired. Shares (total %): %. convoy_retire_per_run %.% Probe: %; %. % ms.',
    (select count(*) from hunks_0430), public.wc_int('cargo_fleet_total'),
    (select string_agg(n.code || ' ' || s.ships, ', ' order by s.ships desc, n.code) from public.cargo_fleet_sizes s join public.nations n on n.id = s.nation_id),
    public.wc_int('convoy_retire_per_run'), case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note, v_note2,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0430;
end $m$;

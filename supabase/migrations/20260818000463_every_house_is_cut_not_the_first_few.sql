-- ═════════════════════════════════════════════════════════════════════
-- 0463 - EVERY HOUSE IS CUT, NOT THE FIRST FEW  (the compactor's due list reaches a merchant house that has no ledger to roll; DARK-SAFE: no switch, no knob, no table)
-- ═════════════════════════════════════════════════════════════════════
-- news: none
-- budget: no table, no job, no cron, no trigger, no autovacuum setting; this file writes 0 rows itself. The compactor's own minute run (public.tick_compact, its
--   compact_budget_ms 8 s a run, unchanged) then walks a backlog of about 430,000 old rows off in the hours after the deploy (about 2,400 rows a minute, under the 5,000 a run).
-- retention: npc_retention_hours (3), the rule that already exists; this file makes it reach every merchant house, it adds no second mechanism.
--
-- WHY (prod, read-only, 2026-11-20 05:35 to 05:45 UTC, head 0461; the database stood at 638 MB after 11-15's runbook and 1,004 MB today, about 50 MB a day):
--   The hot set read 731 MB (over the 700) and the cache hit 98.49 % because the merchants' books are not being cut. 1,428 computer houses exist; 443 of them have NO ledger
--   row at all (the navy and pirate fleets of 0422 / 0431: they sail and fight, they do not trade). public.tick_compact calls a house DUE only when her oldest ledger row is
--   over an hour past the cut, so those 443 are never due. The hour's sweep (:07) was meant to catch them ("a house with no ledger row to roll still loses her old events,
--   voyages and trade days"), but it takes every house NOT due in id order and the 8-second budget ends it after about 75 houses (compact_runs receipts at 01:07 to 05:07
--   UTC: swept 1,418, houses cut 69 to 137, left 1,290 to 1,359): the same first ~75 ids each hour, the other ~1,350 never. What is left lying:
--     public.voyages        90,698 rows, 128 MB (43,791 on 11-15, 54,583 on 11-16 01:30, 70,633 on 11-18, 80,215 on 11-19): +10,000 a day. 98.5 % ARRIVED. The planner's
--                           statistics say 71 % of all rows belong to ONE HUNDRED fleets; the top twelve hold 1,106 to 1,686 voyages each, every one older than the 3-hour cut,
--                           the oldest from the day the fleet was born (11-05). 97 of those 100 fleets belong to ledger-less houses (read: ledger_rows 0 for the three biggest).
--     public.voyage_events  435,138 rows, 82 MB (288,521 on 11-15);  public.events 131,729 rows, 96 MB (79,676 on 11-15): the same houses' books, one event a voyage.
--   Size by gate log: 638 (11-15 12:26) 785 (11-16 01:33) 905 (11-18 05:50) 951 (11-19 05:02) 1,001 (11-20 03:35) 1,004 MB (05:32): about 50 MB a day, still rising; at that rate
--   the 1,500 MB ceiling is reached about 2026-11-30. The compactor is not slow: its minute runs take 1.4 to 2.3 s of 8 and say left 0. They are never asked.
--
-- WHAT THIS FILE DOES. One change to one body, public.tick_compact, in two hunks (each once in the live body, each reversing to its pre-image):
--   1. A house is DUE when her oldest ended voyage, as well as her oldest ledger row, is over c_due past the cut (the older of the two). The probe is one index read a fleet
--      (voyages_fleet_ended_0249, (fleet_id, eta) where status <> 'SAILING'), ordered, limit 1. Nothing else of the compactor moves: the rules that decide WHAT goes
--      (public.npc_compact_houses), the lock, the batch size, the budget, the cut, the 6-hour step a visit and the sweep are untouched. The sweep stays: it now has nothing
--      much to find, and its orders step is not mine.
--   2. The comment above the due rule says so.
--   A visit still cuts a house as of her oldest row + the retention + 6 hours, so the backlog is walked oldest hours first, a few houses in each transaction, 200 ms a hold:
--   about 12,000 small visits (443 houses, 14 days, 6 hours a visit), 60 to 80 a minute: roughly 3 to 5 hours at the 8-second budget. The compactor then holds each
--   ledger-less house at 3 hours of books, as it holds every other.
-- WHAT IT CHANGES ON PROD WHEN DEPLOYED: 0 rows at the deploy. Over the next hours the compactor deletes about 65,000 voyages, 300,000 voyage_events, 60,000 events (and their
--   insurance rows) a few dozen a transaction, each transaction under the house's own row lock for at most the 200 ms hold (SKIP LOCKED: the beat is never made to wait for it,
--   it waits for at most one such transaction). No table lock is taken. The space is reused by the tables' own autovacuum; it is GIVEN BACK to the disk only by the runbook
--   (docs/dev-log/2026-11-20-hot-set.md), the owner's call.
-- A PLAYER LOSES: nothing. Only computer houses are touched, rows older than the three hours a merchant's books were always kept; no screen reads one.
-- DELETES: none by this file; its probe rows are rolled back. NEVER from events / ledger outside the compactor's documented retention.
-- ROLLBACK (forward, owner only): put hunk 2's old text back (scripts/ops/harness/hot-set/before-0463.sql carries both texts); the compactor then cuts as it did.
-- VERSION: 0463 (production head 0461 on 2026-11-20; 0462 is queued ahead of it).
-- ═════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn     constant text := 'public.tick_compact(boolean,boolean)';
  v_t0     timestamptz := clock_timestamp();
  v_def    text;
  v_pre    text;
  v_acl    text;
  v_vol    "char";
  v_cfg    text;
  v_old    text[];
  v_new    text[];
  v_fn_before text;
  v_budget jsonb;
  i        int;
  v_now    timestamptz := now();
  v_a      uuid;
  v_b      uuid;
  v_fa     uuid;
  v_fb     uuid;
  v_va     uuid := gen_random_uuid();
  v_vb     uuid := gen_random_uuid();
  v_pa     uuid;
  v_pb     uuid;
  v_etaa   constant timestamptz := '2019-01-01 00:00:00+00';
  v_etab   constant timestamptz := '2020-01-01 00:00:00+00';
  v_r      jsonb;
  v_note   text := '';
  v_lit    boolean;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('public.npc_compact_locked(uuid[],timestamptz)') is null
     or to_regclass('public.compact_runs') is null or to_regclass('public.voyages') is null then
    raise exception '0463 refuses: the compactor of 0265 is not in this world';
  end if;
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('public.voyages_fleet_ended_0249') and i.indisvalid) then
    raise exception '0463 refuses: voyages_fleet_ended_0249 is not there; the due read would walk a fleet''s whole history';
  end if;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if position('-- 0463:' in v_def) > 0 then
    raise exception '0463 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_pre := v_def;
  select coalesce(p.proacl::text, ''), p.provolatile, coalesce(p.proconfig::text, '') into v_acl, v_vol, v_cfg
    from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;
  select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) into v_budget from public.world_config c where c.key like 'compact\_%';

  -- ── 2. THE HUNKS (each OLD text occurs once in the live body and its NEW text not at all) ──
  v_old := array[
$h$THE DUE HOUSES: a merchant
-- whose oldest ledger row awaiting a roll (her NPC_CARRIED row skipped) is over c_due past the cut, oldest
-- first. A BATCH$h$,
$h$      from (select p.id, (select min(l.created_at) from public.ledger l
                           where l.player_id = p.id and l.kind <> 'NPC_CARRIED') as m
              from public.players p where p.is_npc) x
$h$];
  v_new := array[
$h$THE DUE HOUSES (0463): a merchant
-- whose oldest row awaiting a cut, her oldest ledger row (her NPC_CARRIED row skipped) or her oldest ended voyage, whichever is
-- older, is over c_due past the cut, oldest first (a house with no ledger, a navy or pirate fleet, was never due before 0463).
-- A BATCH$h$,
$h$      from (select p.id, least(
                     (select min(l.created_at) from public.ledger l
                       where l.player_id = p.id and l.kind <> 'NPC_CARRIED'),
                     -- 0463: her oldest ended voyage (voyages_fleet_ended_0249: one ordered probe a fleet, limit 1)
                     (select min(w.eta) from public.fleets f
                        cross join lateral (select v.eta from public.voyages v
                                             where v.fleet_id = f.id and v.status <> 'SAILING'
                                             order by v.eta limit 1) w
                       where f.player_id = p.id)) as m
              from public.players p where p.is_npc) x
$h$];
  for i in 1 .. 2 loop
    if (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]) <> 1
       or (length(v_def) - length(replace(v_def, v_new[i], ''))) / length(v_new[i]) <> 0 then
      raise exception '0463 refuses: hunk % is not once in the live body of %', i, c_fn;
    end if;
    v_def := replace(v_def, v_old[i], v_new[i]);
  end loop;
  execute v_def;

  -- ── 3. SELF-ASSERT: the body ──
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  for i in 1 .. 2 loop
    if (length(v_def) - length(replace(v_def, v_new[i], ''))) / length(v_new[i]) <> 1 then
      raise exception '0463 self-assert FAIL: hunk % is not in the new body exactly once', i;
    end if;
  end loop;
  v_def := replace(replace(v_def, v_new[2], v_old[2]), v_new[1], v_old[1]);
  if v_def <> v_pre then
    raise exception '0463 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;
  if exists (select 1 from pg_proc p where p.oid = c_fn::regprocedure
              and (coalesce(p.proacl::text, '') <> v_acl or p.provolatile <> v_vol or coalesce(p.proconfig::text, '') <> v_cfg)) then
    raise exception '0463 self-assert FAIL: % changed its grants, volatility or config', c_fn;
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) is distinct from v_fn_before then
    raise exception '0463 self-assert FAIL: a function other than % moved', c_fn;
  end if;
  if (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'compact\_%') <> v_budget then
    raise exception '0463 self-assert FAIL: a compactor knob moved';
  end if;

  -- ── 4. THE PROBE (rolled back; only its own two houses are read): the due list sees a house by her voyage ──
  --   Two computer houses, each with a ledger row of now (so the ledger alone never makes her due) and one ENDED voyage: A's of 2019, B's of 2020, both older
  --   than every real row. The compactor runs with its budget at 1 ms: it reads the due list and the receipt names the OLDEST row waiting and how many are due,
  --   and it cuts nothing. A's voyage is the oldest waiting; with A's voyage gone B's is; with B's voyage moved to 3.5 hours ago (inside the hour of grace) B is not.
  begin
    v_lit := public.npc_traders_on();
    if not v_lit then
      update public.world_config set value = 'true'::jsonb
       where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
    end if;
    if not public.npc_traders_on() then
      v_note := 'the probe could not light the merchants in this world: skipped';
    else
      v_a := public.new_house(null, 'Casa da Fila A 0463', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_b := public.new_house(null, 'Casa da Fila B 0463', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_fa := (select f.id from public.fleets f where f.player_id = v_a order by f.created_at limit 1);
      v_fb := (select f.id from public.fleets f where f.player_id = v_b order by f.created_at limit 1);
      v_pa := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_pb := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_pa order by p.code limit 1);
      if v_fa is null or v_fb is null or v_pb is null then
        raise exception '0463 self-assert FAIL: the probe houses have no fleet or the world has one harbour';
      end if;
      if exists (select 1 from public.ledger l where l.player_id in (v_a, v_b) and l.created_at < v_now - interval '1 hour') then
        raise exception '0463 self-assert FAIL: a probe house has an old ledger row';
      end if;
      insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id, created_at) values
        (v_va, v_fa, v_a, '[]', 100, '{}', v_etaa - interval '1 day', v_etaa, 'ARRIVED', v_pa, v_pb, v_etaa - interval '1 day'),
        (v_vb, v_fb, v_b, '[]', 100, '{}', v_etab - interval '1 day', v_etab, 'ARRIVED', v_pa, v_pb, v_etab - interval '1 day');
      update public.world_config set value = to_jsonb(1) where key = 'compact_budget_ms';

      call public.tick_compact(false, false);
      v_r := (select c.receipt from public.compact_runs c order by c.at desc limit 1);
      if (v_r->>'oldest')::timestamptz is distinct from v_etaa or coalesce((v_r->>'due')::int, 0) < 2 then
        raise exception '0463 self-assert FAIL: a house with an old ended voyage and a new ledger is not due (oldest waiting %, due %)', v_r->>'oldest', v_r->>'due';
      end if;
      delete from public.voyages where id = v_va;
      call public.tick_compact(false, false);
      v_r := (select c.receipt from public.compact_runs c order by c.at desc limit 1);
      if (v_r->>'oldest')::timestamptz is distinct from v_etab then
        raise exception '0463 self-assert FAIL: with A''s voyage gone the oldest waiting is not B''s (%)', v_r->>'oldest';
      end if;
      update public.voyages set eta = v_now - interval '3 hours 30 minutes', departed_at = v_now - interval '1 day' where id = v_vb;
      call public.tick_compact(false, false);
      v_r := (select c.receipt from public.compact_runs c order by c.at desc limit 1);
      if (v_r->>'oldest')::timestamptz is not distinct from v_etab
         or (v_r->>'oldest')::timestamptz is not distinct from v_now - interval '3 hours 30 minutes' then
        raise exception '0463 self-assert FAIL: a house whose only ended voyage is inside the hour of grace is due (%)', v_r->>'oldest';
      end if;
      v_note := 'a house with a new ledger and one ended voyage of 2019 is the oldest waiting and due, then B''s of 2020, and a voyage 3.5 hours old is not due';
    end if;
    raise exception sqlstate 'BV463';
  exception when sqlstate 'BV463' then null;
  end;
  perform set_config('lock_timeout', '5s', true);
  if v_note = '' then
    raise exception '0463 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name in ('Casa da Fila A 0463', 'Casa da Fila B 0463'))
     or exists (select 1 from public.voyages v where v.id in (v_va, v_vb))
     or (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'compact\_%') <> v_budget then
    raise exception '0463 self-assert FAIL: the probe was not rolled back';
  end if;

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0463 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0463 self-assert ok: EVERY HOUSE IS CUT, NOT THE FIRST FEW. public.tick_compact: two hunks, each once and reversing; grants, volatility and config unmoved; no other function and no compactor knob moved. Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0371 — A FLEET FIGHTS, FLEES OR PAYS: world_config `raid_orders_enabled` false -> true. One knob row is written and one news row is posted. No function, no table, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. Owner row 315 (the fight log and a standing order per fleet). 0353 built slice C2 dark behind this one switch (docs/COMBAT_LOG.md 2) and left its news to "the file that lights
--   raid_orders_enabled". Owner, 2026-11-13 (row 324): "do all, make everything work. open them if everything is built and is workable." This file is that one light
--   (the form of 0178 and 0179).
-- WHAT THE SWITCH TURNS ON (every reader is live already, 0353; none is touched here):
--   * cmd.raid_order(fleet, FIGHT | FLEE | PAY) keeps a company's order for one fleet (no row is Fight); world.raid_read serves the picker's read: her guns, her slip, the price of Pay,
--     the raiders' word by danger level. The picker stands on the map's Send tray and on the fleet's page (src/live/RaidOrder.tsx draws nothing while the switch is off);
--   * voyage.depart freezes the order on each segment at her NEXT departure (voyage.freeze_order), and voyage.leg_order reads it: a raid on that water is fought under it.
--     Fight is today's fight. Flee: her guns are silent and she rolls to get away each round (fight_flee_base 0.15 plus 0.03 a point of sighting lead, floor 0.05, top 0.30).
--     Pay: 8 % of her cargo at cost (ransom_share) to the raider or to the pirate capital, no shot fired; refused, and she fights, with nothing aboard or nobody to take it.
--   * A merchant, a cargo ship, a navy ship and a pirate ship never hold an order: their raids are fought as today, byte for byte.
-- THE FLEE KNOBS (docs/COMBAT_LOG.md 7, R7: "reasoned, not measured"): measured before this file, scripts/ops/harness/combat-log/flee-knobs-scene.sql, the table in
--   docs/dev-log/2026-11-13-light-raid-orders.md. At the seed values no order is best everywhere and none is useless, so THIS FILE CHANGES NO KNOB; the guard below refuses if the
--   two knobs are not the measured 0.15 and 0.05.
-- GUARD (the file refuses, and nothing is written, when any of these is not so):
--   * 0353's functions and table and 0347's news exist;
--   * the switch row exists and reads exactly false;
--   * nobody holds an order yet (public.fleet_raid_orders is empty: the door was dark), so no order starts to count that its company did not choose under the lit rules;
--   * fight_flee_base is 0.15 and fight_flee_floor is 0.05 (the values the table was measured at).
--   NOT a guard, on purpose: whether there is someone to take a ransom (purses lit, a pirate capital, the hoard under its cap). A world without one is still safe to light: Pay is refused
--   and she fights, and the log says why. Read scripts/ops/harness/combat-log/payee.sql before the deploy; the file prints what it found in its receipt.
-- SELF-ASSERT, on a probe company of this file's own, rolled back: the door takes FLEE and PAY and refuses a bad word; the read says on and names her order; a departure's segments
--   freeze the order for her fleet and for no merchant's; FIGHT leaves no row; THE ROLLBACK PLAYED inside the probe (the switch set false): a frozen order is read as none, the door
--   refuses E_NOT_IN_USE, the read says {on: false}. The catalog: no function moved; exactly one world_config row moved; the news row is one row.
-- ALTERS LIVE PLAY: its own window, a 30-minute after-check (scripts/ops/harness/combat-log/after-check.sh <start> <end>, and after-lit.sql: RANSOM in the ledger = the sum of ransom_paid).
-- ROLLBACK (forward; a draft is scripts/ops/harness/combat-log/rollback-0371.sql): the same row set back to false. voyage.leg_order answers null, so every frozen order is ignored at
--   once; the door refuses; rows and logs stay. The one-line form (owner only): update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s.
-- NEWS: this file posts its own UPDATE row, public.news_update('0371', 'Raids: Fight, Flee or Pay', '습격: 전투, 도주, 지불') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0371 - deploys after 0370 (fleet_room_bite), in its own window. It names no function of 0364 to 0370.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_lived       boolean := false;
  v_lis         uuid;
  v_prt         uuid;
  v_pl          uuid;
  v_npc         uuid;
  v_fl          uuid;
  v_nfl         uuid;
  v_segs        jsonb;
  v_r           jsonb;
  v_payee       text;
  v_ms_probe    numeric;
  c_key         constant text := 'raid_orders_enabled';
  c_uid         constant uuid := '00000000-0371-4000-8000-000000000001';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['public.raid_orders_on()', 'cmd.raid_order(uuid,text)', 'world.raid_read(uuid)', 'voyage.freeze_order(jsonb,uuid)', 'voyage.leg_order(jsonb)',
                                        'public.raid_payee(uuid)', 'public.fight_flee_chance(numeric)', 'public.form_fleet(uuid,text,uuid)', 'cmd.assume_identity(uuid)',
                                        'public.news_update(text,text,text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.fleet_raid_orders') is null then
    raise exception '0371 refuses: the standing order (0353) or the news (0347) are not in this world';
  end if;
  if (select c.value from public.world_config c where c.key = c_key) is distinct from 'false'::jsonb or public.raid_orders_on() then
    raise exception '0371 refuses: % is not false in this world (it reads %): this file lights it once, from dark', c_key, (select c.value from public.world_config c where c.key = c_key);
  end if;
  if exists (select 1 from public.fleet_raid_orders) then
    raise exception '0371 refuses: % fleet(s) already hold an order while the door was dark; read scripts/ops/harness/combat-log/after-lit.sql (`order_rows`) first', (select count(*) from public.fleet_raid_orders);
  end if;
  if public.wc_num('fight_flee_base') is distinct from 0.15 or public.wc_num('fight_flee_floor') is distinct from 0.05 then
    raise exception '0371 refuses: the flee knobs read % and %, not the 0.15 and 0.05 its table was measured at (scripts/ops/harness/combat-log/flee-knobs-scene.sql)',
      public.wc_num('fight_flee_base'), public.wc_num('fight_flee_floor');
  end if;
  v_payee := case when public.raid_payee(null) is null then 'NO payee in this world now (purses dark, no pirate capital, or the hoard at its cap): a Pay is refused and she fights'
                  else 'a payee stands (the pirate capital takes a ransom)' end;

  -- ── 1. BEFORE: the catalog and every OTHER knob ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c where c.key <> c_key;

  -- ── 2. THE LIGHT ──
  update public.world_config
     set value = 'true'::jsonb, updated_at = now(), description = description || ' LIT by 0371 (owner row 324, 2026-11-13).'
   where key = c_key and value = 'false'::jsonb;
  get diagnostics v_n = row_count;
  if v_n <> 1 or not public.raid_orders_on() then
    raise exception '0371 self-assert FAIL: % row(s) written, and the reader says %', v_n, public.raid_orders_on();
  end if;

  -- ── 3. THE SELF-ASSERT: a probe company and a probe merchant of this file's own, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select n.id into v_prt from public.nations n where n.code = 'PRT';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_uid, 'Casa da Prova 0371', v_prt, 40000, false) returning id into v_pl;
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Mercador da Prova 0371', v_prt, 40000, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Ordem 0371', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova 0371', true, true);
    v_nfl := public.form_fleet(v_npc, 'Mercante 0371', v_lis);
    perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante 0371', true, true);
    v_segs := jsonb_build_array(jsonb_build_object('nm', 100, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0.2),
                                jsonb_build_object('nm', 50, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0.2));
    perform cmd.assume_identity(c_uid);

    -- the door and the read
    v_r := cmd.raid_order(v_fl, 'FLEE');
    if v_r is distinct from '{"ok": true, "order": "FLEE"}'::jsonb or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_fl) is distinct from 'FLEE' then
      raise exception '0371 self-assert FAIL: lit, the door did not keep Flee: %', v_r;
    end if;
    v_r := world.raid_read(v_fl);
    if (v_r ->> 'on')::boolean is not true or v_r ->> 'order' is distinct from 'FLEE' or (v_r ->> 'guns')::boolean is not false
       or coalesce(v_r ->> 'slip', '') not in ('poor', 'fair', 'good') or coalesce(jsonb_array_length(v_r -> 'foes'), 0) < 1 then
      raise exception '0371 self-assert FAIL: lit, the read of a gunless barca under Flee: %', v_r;
    end if;
    -- a departure freezes it on each segment of HER fleet, and on no merchant's
    if voyage.freeze_order(v_segs, v_fl)::text is distinct from jsonb_build_array(v_segs -> 0 || '{"order": "FLEE"}'::jsonb, v_segs -> 1 || '{"order": "FLEE"}'::jsonb)::text
       or voyage.freeze_order(v_segs, v_nfl)::text is distinct from v_segs::text
       or voyage.leg_order(voyage.freeze_order(v_segs, v_fl) -> 1) is distinct from 'FLEE' or voyage.leg_order(v_segs -> 0) is not null then
      raise exception '0371 self-assert FAIL: lit, Flee was not frozen on each segment of her fleet alone';
    end if;
    v_r := cmd.raid_order(v_fl, 'PAY');
    if v_r is distinct from '{"ok": true, "order": "PAY"}'::jsonb or world.raid_read(v_fl) ->> 'order' is distinct from 'PAY' then
      raise exception '0371 self-assert FAIL: lit, Pay did not replace Flee: %', v_r;
    end if;
    if cmd.raid_order(v_fl, 'RUN') ->> 'error_code' is distinct from 'E_BAD_ORDER' or cmd.raid_order(v_nfl, 'FLEE') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET'
       or world.raid_read(v_nfl) is distinct from '{"on": false}'::jsonb or exists (select 1 from public.fleet_raid_orders o where o.fleet_id is distinct from v_fl) then
      raise exception '0371 self-assert FAIL: lit, a bad word or another house''s fleet was taken';
    end if;
    -- THE ROLLBACK, PLAYED: with the switch set back a frozen order is read as none, the door refuses and the read says off; her row stays
    update public.world_config set value = 'false'::jsonb where key = c_key;
    if voyage.leg_order(v_segs -> 0 || '{"order": "PAY"}'::jsonb) is not null or voyage.freeze_order(v_segs, v_fl)::text is distinct from v_segs::text
       or cmd.raid_order(v_fl, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_IN_USE' or world.raid_read(v_fl) is distinct from '{"on": false}'::jsonb
       or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_fl) is distinct from 'PAY' then
      raise exception '0371 self-assert FAIL: with the switch set back an order was still read, frozen or taken, or her row was lost';
    end if;
    update public.world_config set value = 'true'::jsonb where key = c_key;
    -- FIGHT is no row
    v_r := cmd.raid_order(v_fl, 'FIGHT');
    if v_r is distinct from '{"ok": true, "order": "FIGHT"}'::jsonb or exists (select 1 from public.fleet_raid_orders o where o.fleet_id = v_fl)
       or voyage.freeze_order(v_segs, v_fl)::text is distinct from v_segs::text then
      raise exception '0371 self-assert FAIL: lit, Fight left a row or froze an order: %', v_r;
    end if;
    raise exception using errcode = 'ZX371', message = 'PROBE_ROLLBACK_0371';
  exception when sqlstate 'ZX371' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0371 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.auth_uid = c_uid or pl.company_name = 'Mercador da Prova 0371') or exists (select 1 from public.fleet_raid_orders) then
    raise exception '0371 self-assert FAIL: a probe house or an order outlived the probe';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 4. AFTER: lit, and nothing else moved ──
  if not public.raid_orders_on() or (select c.value from public.world_config c where c.key = c_key) is distinct from 'true'::jsonb then
    raise exception '0371 self-assert FAIL: the switch is not lit after the probe';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0371 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.description || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c where c.key <> c_key) <> v_cfg_before then
    raise exception '0371 self-assert FAIL: another world_config row moved: this file writes one';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0371', 'Raids: Fight, Flee or Pay', '습격: 전투, 도주, 지불');
  if (select count(*) from public.world_news w where w.key = 'update:0371') <> 1 then
    raise exception '0371 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0371 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0371 self-assert ok: A FLEET FIGHTS, FLEES OR PAYS. raid_orders_enabled was false and is true; no fleet held an order; the flee knobs are the measured 0.15 and 0.05. A probe company: the door kept Flee, then Pay, and refused a bad word and a merchant''s fleet; the read says on and names her order; a departure freezes it on each segment of her fleet and on no merchant''s; Fight leaves no row; with the switch set back (the rollback, played and rolled back) a frozen order is read as none, the door refuses E_NOT_IN_USE and the read says off. %. No function moved, no other knob moved, its UPDATE row is one row. Probe % ms, whole file % ms.',
    v_payee, v_ms_probe, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;

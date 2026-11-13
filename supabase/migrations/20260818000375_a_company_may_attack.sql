-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0375 - A COMPANY MAY ATTACK: attack_enabled is LIT. One switch, one news row. No function, no table, no other knob.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: owner row 324 (2026-11-13): "do all, make everything work. open them if everything is built and is workable." Attacks were built dark in 0323 (the timed battle), 0327 (a
--   player attacks), 0333 (the navy comes), 0334 (WANTED), 0339 (pirate ships), 0357 (fought round by round), 0364 (the ring on the map) and made ready in 0374 (loot follows the
--   risk taken). The sim on what really sails, the battle driven in a browser and the after-check are docs/dev-log/2026-11-13-attacks-ready.md.
-- WHAT A PLAYER MAY DO FROM THIS DEPLOY (docs/COMBAT_LOG.md 3.6):
--   * press Attack on the card of a cargo ship, a navy ship or a pirate ship of another country, at sea, within attack_reach_nm (240 miles), with a fleet that has guns and an empty
--     hold. NEVER another player's fleet (E_HUMAN_TARGET, untouched), never a merchant, never a ship of her own country, never a ship in port.
--   * a battle of seven minutes: six rounds a minute apart and the boarding. Fight keeps fighting; Flee tries to break off from the next round. Both fleets stand still for it.
--   * boarded: loot_share (15 %) of the funds aboard; paid off: ransom_share (8 %); each counted for the share of her own hull she lost in the fight (0374), at most loot_per_ship
--     (60,000 d.) a battle and loot_per_company_day (240,000 d.) a company in any 24 hours. Gold is moved from the ship's funds, never minted.
-- WHAT IT COSTS HER: her standing with that country at once (regard_attack_cargo -150, regard_attack_navy -250, regard_sink -100 more); the country's navy sails to the battle
--   (up to navy_call_ships 3); a tenth of her hands when she is beaten or breaks off; her hull; and a WANTED mark of wanted_hours (48) when she wins or no navy came in time.
-- THE GUARD: public.attack_ready() (0374), the same reading scripts/ops/harness/attacks/before-light.sql prints on production first. It refuses unless the loot rule of 0374 is on
--   and the round clock is sane, and, in a world where the crown's cargo ships sail (production): regard_enabled, npc_ship_level_enabled (with the level written on 9 cargo hulls
--   in 10), convoy_armed_enabled and navy_enabled are lit, and the UNARMED cargo ships at sea are at most a tenth of the cargo ships at sea. A world built from this chain alone has
--   no cargo ship, so nothing there needs protecting and the file applies (the chain's own switches for regard and the rest are the owner's on production, not this chain's).
--   It also refuses a world where attacks are already lit, or where a battle is being fought.
-- NEWS: this file posts its own UPDATE row, public.news_update('0375', 'Attack ships at sea: it costs standing, and the navy answers', '해상 선박 공격 개방: 평판이 떨어지고 해군이 출동합니다')
--   (0347's law, tests/news.lint.spec.ts): the step that lights is the step that tells (docs/dev-log/2026-11-12-live-rounds.md, "Decided by default").
-- ALTERS LIVE PLAY: its own measured window. THE 30-MINUTE AFTER-CHECK is scripts/ops/harness/attacks/after-check.sh <start> <end> (the seven lines of docs/COMBAT_LOG.md 3.6).
-- ROLLBACK (forward, owner only): attack_enabled false. scripts/ops/harness/attacks/rollback-0375.sql is the draft of that migration; the owner's one line does the same at once:
--   update public.world_config set value = 'false'::jsonb where key = 'attack_enabled'. Running battles finish and still pay (0327, 4.6); loot taken, regard lost and WANTED marks stay.
-- NOT IN THIS FILE: navy_hunt_per_day stays 0 (the hunt of a Hostile or WANTED company is its own later light; the recommended value and why are in the dev-log).
-- SELF-ASSERT: ONE DO block, statement_timeout 30 s, lock_timeout 5 s; fails above 20 s. The switch reads true through public.attack_on; every other world_config row and every
--   function is as it was; the news row is there once; and, on a probe of this file's own rows rolled back by a raised sentinel: the door is open (a probe company's preview is
--   refused for its target, not for E_NOT_IN_USE) and NO PLAYER ATTACKS A PLAYER (E_HUMAN_TARGET). No table is counted or summed. THE REAL BATTLE IS PROOF 75's.
-- VERSION: 0375, after 0374. On production it deploys after the lights 0369 to 0373 (ship stores, fleet room, raid orders, NPC levels, regard).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_ready      jsonb;
  v_cfg_before text;
  v_fn_before  text;
  v_n          int;
  v_r          jsonb;
  v_a          uuid;
  v_b          uuid;
  v_fa         uuid;
  v_fb         uuid;
  v_lived      boolean := false;
  c_uid_a      constant uuid := '00000000-0375-4000-8000-0000000000a1';
  c_uid_b      constant uuid := '00000000-0375-4000-8000-0000000000b2';
  c_en         constant text := 'Attack ships at sea: it costs standing, and the navy answers';
  c_ko         constant text := '해상 선박 공격 개방: 평판이 떨어지고 해군이 출동합니다';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['public.attack_ready()', 'public.attack_on()', 'public.loot_risk(jsonb)', 'cmd.attack(uuid,uuid,integer)', 'cmd.preview_attack(uuid,uuid)',
                                        'cmd.battle_stance(uuid,text)', 'world.battle(uuid)', 'world.fights()', 'public.tick_battles(timestamp with time zone)',
                                        'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 'cmd.assume_identity(uuid)', 'public.news_update(text,text,text)']) f
              where to_regprocedure(f) is null) then
    raise exception '0375 refuses: the attack (0327), its rounds (0357), its ring (0364) or its readiness (0374) are not in this world; this file deploys after them';
  end if;
  if public.attack_on() then
    raise exception '0375 refuses: attack_enabled is already on';
  end if;
  if not exists (select 1 from public.world_config c where c.key = 'attack_enabled' and c.value = 'false'::jsonb) then
    raise exception '0375 refuses: world_config has no attack_enabled row that reads false';
  end if;
  if exists (select 1 from public.battles b where b.status = 'FIGHTING') then
    raise exception '0375 refuses: a battle is being fought in a world where attacks are dark';
  end if;
  v_ready := public.attack_ready();
  if not (v_ready ->> 'ready')::boolean then
    raise exception '0375 refuses: attacks are not ready to light: % (public.attack_ready: %)', v_ready -> 'why', v_ready;
  end if;

  -- ── 1. BEFORE ──
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) into v_cfg_before from public.world_config c where c.key <> 'attack_enabled';
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');

  -- ── 2. THE LIGHT ──
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0375 self-assert FAIL: % row(s) of attack_enabled were written, not 1', v_n;
  end if;

  -- ── 3. THE SELF-ASSERT ──
  if not public.attack_on() then
    raise exception '0375 self-assert FAIL: public.attack_on does not read the switch as on';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> 'attack_enabled') <> v_cfg_before then
    raise exception '0375 self-assert FAIL: another world_config row moved: this file writes one switch';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0375 self-assert FAIL: a function moved: this file edits none';
  end if;

  -- THE PROBE, on this file's own rows, rolled back by a raised sentinel: the door is open, and no player attacks a player
  begin
    v_a := public.new_house(c_uid_a, 'Probe 0375 A', 'PRT', 'LIS', 'Probe 0375 A', (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Probe 0375 A', null, false);
    v_b := public.new_house(c_uid_b, 'Probe 0375 B', 'ESP', 'SVQ', 'Probe 0375 B', 'barca', 'Probe 0375 B', null, false);
    select f.id into v_fa from public.fleets f where f.player_id = v_a;
    select f.id into v_fb from public.fleets f where f.player_id = v_b;
    update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_fa;
    perform cmd.assume_identity(c_uid_a);
    -- no such ship: refused for the target, so the door itself is open
    v_r := cmd.preview_attack(v_fa, '00000000-0375-4000-8000-00000000dead'::uuid);
    if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' is distinct from 'E_NOT_FOUND' then
      raise exception '0375 self-assert FAIL: lit, a preview of no ship answers % (wanted E_NOT_FOUND: the door open, the target refused)', v_r;
    end if;
    -- another player's fleet: the law that is not touched
    v_r := cmd.preview_attack(v_fa, v_fb);
    if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' is distinct from 'E_HUMAN_TARGET' then
      raise exception '0375 self-assert FAIL: a player''s fleet as a target answers % (wanted E_HUMAN_TARGET)', v_r;
    end if;
    v_r := cmd.attack(v_fa, v_fb, null);
    if (v_r ->> 'ok')::boolean or v_r ->> 'error_code' is distinct from 'E_HUMAN_TARGET' then
      raise exception '0375 self-assert FAIL: the press on a player''s fleet answers % (wanted E_HUMAN_TARGET)', v_r;
    end if;
    if exists (select 1 from public.battle_sides bs where bs.fleet_id in (v_fa, v_fb)) then
      raise exception '0375 self-assert FAIL: a refused attack opened a battle';
    end if;
    v_lived := true;
    raise exception using errcode = 'ZX375', message = 'probe rolled back';
  exception when sqlstate 'ZX375' then
    null;
  end;
  if not v_lived then
    raise exception '0375 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid in (c_uid_a, c_uid_b)) then
    raise exception '0375 self-assert FAIL: a probe company is left behind';
  end if;
  if not public.attack_on() then
    raise exception '0375 self-assert FAIL: the probe''s rollback took the light with it';
  end if;

  -- ── 4. THE NEWS (0347's law): the step that lights is the step that tells ──
  perform public.news_update('0375', c_en, c_ko);
  if (select count(*) from public.world_news x where x.key = 'update:0375') <> 1 then
    raise exception '0375 self-assert FAIL: the UPDATE row of this file is not there exactly once';
  end if;

  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0375 self-assert FAIL: it took % (the limit is 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0375 self-assert ok: A COMPANY MAY ATTACK. attack_enabled is on (public.attack_on); no other knob and no function moved; the door is open and a player''s fleet is refused (E_HUMAN_TARGET) on a rolled-back probe; the news row is posted once. Ready as: %. % ms.',
    v_ready, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

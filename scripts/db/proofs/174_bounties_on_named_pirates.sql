-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 174 - BOUNTIES ON NAMED PIRATES  (migration 0471; docs/design/playable-2026-11-22.md P2; docs/dev-log/2026-11-22-pirate-bounties.md)
--
--   Through the pirates' minute job (public.tick_pirates) and the one battle (public.battle_resolve), rolled back with proof.mjs's
--   transaction. The scene is proof 167's: a hunting pirate at her haunt and a company's ship 15 miles off, the pirates, the purses and
--   the attacks lit, companies raided from title 1. A second pirate of the same haunt lies at home for the respawn.
--
-- @pass BT_DARK     dark: the minute job names nobody and answers no `bounties`; the read is {"on": false}; the close is '{}'
-- @pass BT_NAME     lit: the job names the pirate at work into slot 1 (an epithet, a given name, her home, a poster the pirates do not hold), once
-- @pass BT_RAID     lit: her real RAID on the company, closed by battle_resolve: claimed exactly when bounty_beaten says so, paid from the
--                   poster to the company on PIRATE_BOUNTY, said on the company's BATTLE_REPORT and in battles.result; a won raid is a ship on her record
-- @pass BT_TAKE     a raid of hers won (forced shape) puts the ship on her record and grows the bounty by bounty_per_ship
-- @pass BT_SUNK    a company's ship that sinks her, through battle_resolve: paid, said on her report and in battles.result
-- @pass BT_ATTACK   the ATTACK arm: a company that boards a named pirate collects; a company driven off collects nothing
-- @pass BT_RESPAWN  a slot whose pirate was beaten is not named again before bounty_respawn_hours; after it, another pirate (not the one beaten) is
-- @pass BT_READ     the read: the rates, the standing bounty with her value and record, and the claims
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config set value = case key when 'pirate_strike_from_port' then 'true'::jsonb else to_jsonb(720) end where key in ('pirate_strike_from_port', 'pirate_port_minutes');
update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';   -- 0435: the one-call fight (public.fight_sides), resolved at its clock

create function pg_temp.lie_174(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

-- a battle of the given kind between two fleets, opened by hand (the close reads only its kind and its OPENED sides)
create function pg_temp.battle_174(p_kind text, p_attacker uuid, p_defender uuid, p_at timestamptz) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.battles (kind, site, started_at, resolves_at, status) values (p_kind, '{}'::jsonb, p_at, p_at + interval '10 minutes', 'FIGHTING') returning id into v;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values
    (v, p_attacker, 'ATTACKER', p_at, p_at, 'OPENED'), (v, p_defender, 'DEFENDER', p_at, p_at, 'OPENED');
  return v;
end $f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0471-4000-8000-000000000001';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf    uuid;
  v_pf2   uuid;
  v_h     uuid;
  v_hp    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_r     jsonb;
  v_b     public.battles%rowtype;
  v_bid   uuid;
  v_row   public.pirate_bounties%rowtype;
  v_purse bigint;
  v_beat  boolean;
  v_val   bigint;
  v_ev    jsonb;
  r       record;
begin
  -- ── THE SCENE (proof 167's) ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled', 'raid_companies_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  update public.world_config set value = to_jsonb(1) where key in ('raid_company_title_min', 'bounty_named');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 900000000 where t.port_id = public.pirate_capital();
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 6;
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  v_hp := public.new_house(v_uid, 'Casa Caccia 174', 'PRT', 'LIS', 'Caccia 174', 'galion', 'Caccia 174', null, false);
  select f.id into v_h from public.fleets f where f.player_id = v_hp;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_h;
  perform pg_temp.lie_174(v_h, v_lat + 0.25, v_lon);
  -- the second pirate, at home, at work but not hunting (for the respawn)
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 7;
  v_pf2 := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  update public.pirate_ships x set laid_up_at = t0 where x.fleet_id = v_pf2;   -- laid up until BT_RESPAWN wakes her

  -- ── BT_DARK ──
  v_r := public.tick_pirates(t0);
  if v_r ? 'bounties' or exists (select 1 from public.pirate_bounties) or world.pirate_bounties() <> '{"on": false}'::jsonb
     or public.bounty_close(gen_random_uuid(), '{"outcome":"DRIVEN_OFF"}'::jsonb, t0) <> '{}'::jsonb then
    raise exception 'PROOF 174 FAIL: dark, something was named or served: %', v_r;
  end if;
  raise notice 'PASS: BT_DARK — dark: no bounties key on the job''s answer, no row, the read {"on": false}, the close {}';

  -- ── BT_NAME ──
  update public.world_config set value = 'true'::jsonb where key = 'pirate_bounties_enabled';
  -- the dark run opened her RAID on the company (proof 167's RC_STRIKE); it is fought below, after she is named
  v_r := public.tick_pirates(t0 + interval '1 minute');
  select * into v_row from public.pirate_bounties x where x.closed_at is null;
  if (v_r #>> '{bounties,named}')::int is distinct from 1 or v_row.fleet_id is distinct from v_pf or v_row.slot <> 1
     or v_row.home_port is distinct from (select n.home_port from public.pirate_ships n where n.fleet_id = v_pf)
     or v_row.poster_port is null or public.pirate_power(public.port_nation(v_row.poster_port)) or v_row.given is null or v_row.epithet is null then
    raise exception 'PROOF 174 FAIL: lit, the job did not name the hunting pirate into slot 1: % / %', v_r, row_to_json(v_row);
  end if;
  v_r := public.tick_pirates(t0 + interval '2 minutes');
  if (v_r #>> '{bounties,named}') is not null or (select count(*) from public.pirate_bounties) <> 1 then
    raise exception 'PROOF 174 FAIL: lit, a second run named a second pirate with one slot: %', v_r;
  end if;
  raise notice 'PASS: BT_NAME — named "%" (slot 1), poster %, once', public.bounty_name(v_row.epithet, v_row.given, v_row.home_port),
    (select p.code from public.ports p where p.id = v_row.poster_port);

  -- ── BT_RAID: her real raid on the company, through battle_resolve ──
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_h and s.side = 'DEFENDER'
   where b.status = 'FIGHTING' and b.kind = 'RAID';
  if v_b.id is null then
    raise exception 'PROOF 174 FAIL: the job opened no RAID on the company (the scene)';
  end if;
  update public.ships s set durability = least(s.durability, 3) where s.fleet_id = v_pf;   -- a battered raider: most seeds see her thrown back
  select pl.ducats into v_purse from public.players pl where pl.id = v_hp;
  v_val := public.bounty_value(v_row.named_at, v_row.taken, v_b.resolves_at);
  perform public.battle_resolve(v_b.id, v_b.resolves_at);
  select * into v_b from public.battles b where b.id = v_b.id;
  v_beat := public.bounty_beaten('RAID', v_b.result, v_pf);
  select e.payload into v_ev from public.events e where e.player_id = v_hp and e.kind = 'BATTLE_REPORT' and e.payload ->> 'battle_id' = v_b.id::text;
  select * into v_row from public.pirate_bounties x where x.id = v_row.id;
  if v_beat then
    if v_row.closed is distinct from 'CLAIMED' or v_row.claimed_by <> v_hp or v_row.paid <> v_val or v_row.battle_id <> v_b.id
       or (select pl.ducats from public.players pl where pl.id = v_hp) <> v_purse + v_val
       or not exists (select 1 from public.ledger l where l.player_id = v_hp and l.kind = 'PIRATE_BOUNTY' and l.ducats_delta = v_val)
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_row.poster_port and tf.kind = 'PIRATE_BOUNTY' and tf.ducats = -v_val)
       or (v_ev #>> '{bounty,paid}')::bigint is distinct from v_val or (v_b.result #>> '{bounty,paid}')::bigint is distinct from v_val then
      raise exception 'PROOF 174 FAIL: lit, the company beat her (%) and was not paid % once: % / report %', v_b.result ->> 'outcome', v_val, row_to_json(v_row), v_ev;
    end if;
  else
    if v_row.closed is not null or v_ev ? 'bounty' or v_b.result ? 'bounty'
       or v_row.taken <> (case when v_b.result ->> 'outcome' in ('PLUNDERED', 'RANSOM') then 1 else 0 end) then
      raise exception 'PROOF 174 FAIL: lit, she was not beaten (%) yet the bounty moved: %', v_b.result ->> 'outcome', row_to_json(v_row);
    end if;
  end if;
  raise notice 'PASS: BT_RAID — a real raid ended %, beaten %, claimed % (paid %), the report says %', v_b.result ->> 'outcome', v_beat, v_row.closed, coalesce(v_row.paid, 0), v_ev -> 'bounty';

  -- ── BT_TAKE (and the claim, forced shapes, if the real raid did not settle it) ──
  if v_row.closed is null then
    v_bid := pg_temp.battle_174('RAID', v_pf, v_h, t0 + interval '20 minutes');
    v_val := public.bounty_value(v_row.named_at, v_row.taken, t0 + interval '20 minutes');
    v_r := public.bounty_close(v_bid, '{"outcome":"PLUNDERED"}'::jsonb, t0 + interval '20 minutes');
    if v_r <> '{}'::jsonb or (select x.taken from public.pirate_bounties x where x.id = v_row.id) <> v_row.taken + 1
       or public.bounty_value(v_row.named_at, v_row.taken + 1, t0 + interval '20 minutes') <> v_val + public.wc_num('bounty_per_ship')
       or (select x.took -> 0 ->> 'house' from public.pirate_bounties x where x.id = v_row.id) <> 'Casa Caccia 174' then
      raise exception 'PROOF 174 FAIL: a raid she won is not on her record: %', v_r;
    end if;
    -- the claim through the real close: every hull of hers at 0 (sunk), resolved by public.battle_resolve at its clock
    select pl.ducats into v_purse from public.players pl where pl.id = v_hp;
    update public.ships s set durability = 0 where s.fleet_id = v_pf;
    v_val := public.bounty_value(v_row.named_at, v_row.taken + 1, t0 + interval '30 minutes');
    perform public.battle_resolve(v_bid, t0 + interval '30 minutes');
    select * into v_b from public.battles b where b.id = v_bid;
    select e.payload into v_ev from public.events e where e.player_id = v_hp and e.kind = 'BATTLE_REPORT' and e.payload ->> 'battle_id' = v_bid::text;
    select * into v_row from public.pirate_bounties x where x.id = v_row.id;
    if v_row.closed is distinct from 'CLAIMED' or v_row.paid <> v_val or (select pl.ducats from public.players pl where pl.id = v_hp) <> v_purse + v_val
       or (v_ev #>> '{bounty,paid}')::bigint is distinct from v_val or (v_b.result #>> '{bounty,paid}')::bigint is distinct from v_val then
      raise exception 'PROOF 174 FAIL: sunk, the company was not paid % through battle_resolve: % / % / %', v_val, row_to_json(v_row), v_ev, v_b.result;
    end if;
    raise notice 'PASS: BT_SUNK — she sank (%): battle_resolve paid % on PIRATE_BOUNTY, said on the company''s report and in the result', v_b.result ->> 'outcome', v_val;
  else
    raise notice 'PASS: BT_SUNK — the real raid itself was her defeat (above)';
    v_bid := pg_temp.battle_174('RAID', v_pf, v_h, t0 + interval '20 minutes');
    if public.bounty_close(v_bid, '{"outcome":"PLUNDERED"}'::jsonb, t0 + interval '20 minutes') <> '{}'::jsonb
       or (select x.taken from public.pirate_bounties x where x.id = v_row.id) <> v_row.taken then
      raise exception 'PROOF 174 FAIL: a claimed pirate''s raid still wrote to her closed record';
    end if;
  end if;
  raise notice 'PASS: BT_TAKE — a won raid is a ship on her record (+% to the bounty); a closed record takes none', public.wc_num('bounty_per_ship');

  -- ── BT_RESPAWN ──
  update public.pirate_ships x set laid_up_at = null where x.fleet_id = v_pf2;
  if (public.bounty_step(v_row.closed_at + interval '5 hours') ->> 'named') is not null then
    raise exception 'PROOF 174 FAIL: the slot was named again before bounty_respawn_hours';
  end if;
  v_r := public.bounty_step(v_row.closed_at + interval '6 hours 1 minute');
  if (v_r ->> 'named')::int is distinct from 1
     or (select x.fleet_id from public.pirate_bounties x where x.closed_at is null) is distinct from v_pf2 then
    raise exception 'PROOF 174 FAIL: after the respawn the slot did not name the other pirate: % (%)', v_r, (select x.fleet_id from public.pirate_bounties x where x.closed_at is null);
  end if;
  raise notice 'PASS: BT_RESPAWN — not at 5 h; at 6 h 1 min the other pirate, never the one beaten';

  -- ── BT_ATTACK ──
  select * into v_row from public.pirate_bounties x where x.closed_at is null;
  v_bid := pg_temp.battle_174('ATTACK', v_h, v_pf2, v_row.named_at + interval '3 hours');
  if public.bounty_close(v_bid, '{"outcome":"DRIVEN_OFF"}'::jsonb, v_row.named_at + interval '3 hours') <> '{}'::jsonb
     or (select x.closed from public.pirate_bounties x where x.id = v_row.id) is not null then
    raise exception 'PROOF 174 FAIL: a company driven off by her collected';
  end if;
  select pl.ducats into v_purse from public.players pl where pl.id = v_hp;
  v_r := public.bounty_close(v_bid, '{"outcome":"PLUNDERED"}'::jsonb, v_row.named_at + interval '3 hours');
  if (v_r #>> '{bounty,paid}')::bigint is distinct from 16500
     or (select pl.ducats from public.players pl where pl.id = v_hp) <> v_purse + 16500 then
    raise exception 'PROOF 174 FAIL: the company that boarded her was not paid 16,500 (15,000 + 3 hours): %', v_r;
  end if;
  raise notice 'PASS: BT_ATTACK — driven off: nothing; boarded her 3 hours after her naming: 16,500 paid';

  -- ── BT_READ ──
  update public.pirate_ships x set laid_up_at = null where x.fleet_id = v_pf;
  update public.world_config set value = to_jsonb(2) where key = 'bounty_named';
  delete from public.pirate_bounties x where x.fleet_id = v_pf;   -- her day of exclusion over, for the read's standing row
  v_r := public.bounty_step(t0 + interval '2 days');
  v_r := world.pirate_bounties();
  if (v_r ->> 'on')::boolean is not true or (v_r #>> '{rates,base}')::numeric <> 15000 or (v_r #>> '{rates,cap}')::numeric <> 60000
     or jsonb_array_length(v_r -> 'bounties') < 1 or (v_r #>> '{bounties,0,value}')::bigint < 15000 or v_r #>> '{bounties,0,home}' is null
     or jsonb_array_length(v_r -> 'claims') < 1 or (v_r #>> '{claims,0,paid}')::bigint <> 16500 or v_r #>> '{claims,0,house}' <> 'Casa Caccia 174'
     or jsonb_typeof(v_r -> 'mine') <> 'array' then
    raise exception 'PROOF 174 FAIL: the read: %', v_r;
  end if;
  raise notice 'PASS: BT_READ — rates, % standing (first "%" at %), % claims (latest % by %)', jsonb_array_length(v_r -> 'bounties'),
    v_r #>> '{bounties,0,name}', v_r #>> '{bounties,0,value}', jsonb_array_length(v_r -> 'claims'), v_r #>> '{claims,0,paid}', v_r #>> '{claims,0,house}';
end
$p$;

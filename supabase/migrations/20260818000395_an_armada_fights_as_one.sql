-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0395 - AN ARMADA FIGHTS AS ONE: EVERY FLEET OF HERS ON HER SIDE OF THE BATTLE SHE STARTS  (owner row 323; docs/ARMADA.md section 7)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 323: "with more than one fleet, max 6 fleet - an armada." 0367 built the sailing and the raid. This is the part that was designed and not built: when a
-- fleet of an armada attacks (cmd.attack -> public.attack_for -> public.battle_open), every fleet of hers THAT IS THERE fights on her side.
--
-- BEHIND THE OWNER'S SWITCH, WHICHEVER WAY IT STANDS. A battle exists only behind `attack_enabled` (the owner's switch; this file does not write it, nor any existing key, and
-- adds no key). 0375 LIT IT ON PROD (2026-11-13), so this file deploys LIT: from the moment it lands, a company whose attacking fleet is in an armada fights with all of her.
-- The file still takes the switch as it finds it:
--   OFF: no body of this file takes a new branch for anyone (each door reads the switch before it reads this file);
--   ON:  a fleet in NO armada attacks, fights and closes exactly as she did, and an armada's fleets fight together from this deploy.
-- The self-assert proves BOTH ARMS on its own rows: with the switch off, every door old against new as text; with it on, a lone fleet's battle old against new as text.
-- NEWS (0347's law): one row, "Armada battles" / "대함대 해전", posted ONLY IF attacks are lit at this deploy (then a player can see the change). Deployed dark, it posts nothing:
--   the news is then the lighting step's.
--
-- THE RULES (docs/ARMADA.md section 7; each one that is this file's own is a default in docs/dev-log/2026-11-13-armada-battle.md)
--   WHO TAKES PART   the fleet that attacks, and every other fleet of her armada that is THERE and has a ship (public.battle_armada, the one reading):
--                      she lies in port: the fleets of hers docked in that same port;
--                      she is at sea: the fleets sailing under the same lead voyage (0367's one schedule) and within attack_reach_nm of her (a fleet turned for port alone is not there);
--                      she lies at anchor: nobody (an armada never anchors as one).
--                    A fleet of hers that is elsewhere takes no part and is not held. A fleet in no armada attacks alone, as before.
--   ALL OR NONE      each fleet that would take part is judged before anything moves (public.attack_armada_gates): free to fight (E_FLEET_BUSY), her hold empty (E_HOLD_NOT_EMPTY, the
--                    war fleet's rule), not in a battle within attack_cooldown_minutes (E_ATTACK_COOLDOWN). One refused refuses the attack, under HER name. The fleet that
--                    attacks keeps her own gates as they were (guns, reach, version, the target's).
--   THE SHEET        each joins as ATTACKER with how = 'ARMADA' (public.battle_armada_join, from public.battle_open, before 0357 freezes the sheet), the fleet that attacked
--                    first, then the armada's own order (her flagship fleet first). Side b of the sheet holds all their hulls; the sheet says the armada's name and
--                    `fleets` [[name, hulls]], and the pre-fight word reads the armada (the sum of voyage.escort_score). The engine and the freeze are not cut.
--   HELD AND FREED   every one of them is stopped for the battle by public.battle_open's own loop (public.battle_stop: IN_BATTLE in port, a free hold at sea) and freed by
--                    public.battle_resolve's own loop at its end; a hold is cut with the battle, for each. At sea they are held for the same span, so they still arrive together.
--   THE STANCE       one for the side, the fleet's that attacked: cmd.battle_stance and public.battle_fight are not cut. Fight or Flee acts for the whole armada.
--   HULL DAMAGE      each ship loses what the one fight says for HER (public.fight_hulls_write, by ship id): the guns choose among all the hulls in the line.
--   CREW LOSS        thrown back, broken off or fled: every fleet on her side loses attack_crew_lost.beaten of each ship's hands, each softened by her own surgeon
--                    (public.raid_crew_lost). The report's `crew_lost` is the sum.
--   LOOT             gold, to the company's one purse, once (public.loot_take, the day's cap once), as before. The report says each fleet's SHARE: in proportion to the guns
--                    she brought (the attack of her hulls on the sheet), rounded down, the remainder to the fleet that attacked. `shares` [{fleet, name, loot, crew_lost, hull_lost}].
--   ONE REPORT       one BATTLE_REPORT a battle, to the company, under the fleet that attacked, with the shares.
--   THE PREVIEW      cmd.preview_attack is the real attack rolled back, so it reads all of this: the word is the armada's, `armada` {name, fleets, ships} is in the estimate,
--                    and a sister's refusal is the preview's refusal.
--   THE RING         public.fight_card (0364) counts the fleets that are there, so the ring grows with the armada with no change to it; its `sides` list her fleets.
--   THE READ         world.battle answers for ANY fleet of hers in the battle (her sister's card shows the same battle), with `armada`, `lead`, `fleets` and, closed, `shares`;
--                    the stance it says is the side's.
--   NO PLAYER FIGHTS A PLAYER, in every path: both refusals (E_HUMAN_TARGET in public.battle_open and public.attack_for) are untouched and come BEFORE anything of this file.
--
-- WHAT IT ADDS (seven functions, all server-only; no table, no column, no knob, no door)
--   public.battle_armada(fleet, now)                  who else of her armada is there, in the armada's order
--   public.attack_armada_gates(player, fleet, now)    the armada's row locked, every fleet of hers settled and locked in id order, then the three refusals above
--   public.battle_armada_join(battle, kind, fleet, now)   the side rows; answers the fleets for public.battle_open's stop loop. A probe, or a fleet in no armada: none
--   public.battle_armada_sheet(battle)                the armada's name, her fleets and her word on the frozen sheet. No armada: nothing
--   public.battle_armada_note(battle)                 what the attack's answer adds: {word, armada {name, fleets, ships}}, from the sheet. No armada: {}
--   public.attack_armada_close(battle, fight, gold, lost)   the sisters' crew loss and the shares. No armada: {}
--   public.battle_armada_view(battle, fleet)          what world.battle adds: {armada, lead, stance, fleets, shares}. No armada: {}
--   battle_sides_how_check takes 'ARMADA' (the constraint is dropped and added again; every row there says one of the three old words).
--
-- SUPERSEDES, BY RE-CUT (13 hunks sliced from the live bodies: each OLD text once in its live body, each reversing; anchored on lines no file of batch 6 touches):
--   public.attack_for (2)          the gates before the fleets are settled; the answer's last line takes public.battle_armada_note.
--   public.battle_open (1)         the stop loop's list takes the fleets public.battle_armada_join wrote.
--   public.battle_sheet_freeze (1) after the sheet is written, public.battle_armada_sheet.
--   public.battle_resolve (1)      one report a battle: a fleet that joined as ARMADA sends none.
--   public.attack_close (2)        "the attacker" is the fleet that opened it; the answer takes public.attack_armada_close.
--   public.battle_log (1)          the attacker's log names her fleets when the sheet does (`fleets`, the key a raid's log has since 0367).
--   world.battle (2)               a fleet that joined as ARMADA reads her battle; the answer takes public.battle_armada_view.
--   public.navy_close (2)          "who came" never counts her own armada.
--   public.battle_navy_served (1)  nor does the navy's clock on her card.
--   NOT cut: public.fight_sides, public.battle_fight, public.battle_advance, cmd.battle_stance, cmd.attack, cmd.preview_attack, public.fight_card, world.fights, world.fight,
--   public.battle_stop, public.navy_call, voyage.hold, public.client_rpc_entry_points.
--   AGAINST BATCH 6: 0364 (fight rings), 0366 (more ships) and 0367 (armada) cut none of these nine bodies. 0357 cut public.battle_open (2 hunks) and public.battle_resolve (5)
--   and made public.battle_sheet_freeze, public.battle_log and world.battle; no hunk here stands inside a text 0357 added, and proof 60 still reverses 0357 on these bodies.
--
-- COST: off, nothing runs. On, a fleet in no armada: one primary-key probe of public.armada_fleets at the attack, one indexed probe of public.battle_sides at the open, the
--   freeze, the close and the read. An armada of six: six settles and six stops at the open, six hulls' lists on the sheet; the rounds are the engine's, unchanged.
-- ROLLBACK (forward, owner only): attack_enabled false stops new battles. The whole slice: scripts/ops/harness/armada-battle/rollback-0395.sql (the hunks swapped back, the
--   seven functions dropped, the constraint as it was; it refuses while a battle is being fought or a side row says ARMADA).
-- SELF-ASSERT: ONE DO block, statement_timeout 45 s, lock_timeout 5 s first; fails above 40 s; a notice prints the milliseconds of every part. The catalog (hunks once and
--   reversing; ACL, volatility, definer and config unmoved; no other function; no knob; the registry; no client reaches a new function), then ONE probe of this file's own rows,
--   rolled back by a raised sentinel, BOTH ARMS of the switch set there: OFF, old against new door by door as text (the old bodies are put back inside a subtransaction that
--   is rolled back); ON: no player fights a player; a fleet in no armada opens and fights her rounds as text under old and new; an armada of two opens, is held, fights, changes stance and is shared
--   out. No table is counted or summed. The real doors, a real cargo ship and navy ship, an armada of six and the close: scripts/db/proofs/69_armada_battle.sql.
-- LOCKS: ALTER TABLE public.battle_sides (ACCESS EXCLUSIVE until this file commits, about a second: a read of a battle's sides waits that long; the table is a few rows a
--   battle), under lock_timeout 5 s.
-- VERSION: 0395 (first written as 0368 on the bodies of batch 6, then 0379; now on main at 0375, where every hunk was found once again: 0374 re-cut one line of
--   public.battle_sheet_freeze and one of public.loot_take, neither a line this file anchors on). 0380, 0381 and 0390 to 0394 deploy before it and were not there to read:
--   if one of them re-cuts a line this file anchors on, the slice refuses by name, "hunk N of F occurs 0 time(s)", and before.sql says so on prod before the deploy.
-- WITH 0374 (loot follows the risk taken): the gold that reaches the purse is 0374's figure and this file does not touch it. public.loot_take reads the battle's kept result,
--   whose side b is the WHOLE armada's hull: the risk is (hull all her fleets lost) / (hull all her fleets brought) over loot_risk_full. That gold is then shared out here by
--   the guns each fleet brought. So: gold G = public.loot_due(outcome, floor(aboard x public.loot_risk(result)), the day's loot so far); a fleet that joined is counted
--   floor(G x her guns / all the guns); the fleet that attacked is counted the rest. The shares add up to G to the ducat.
-- A BATTLE BEING FOUGHT AT THE DEPLOY (possible once attacks are lit): it has no ARMADA side, so every re-cut body reads it as it did; the probe proves a battle opened under
--   the old bodies' rules fights its rounds to the same text under the new.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_tp         timestamptz := clock_timestamp();
  v_ms         jsonb := '{}'::jsonb;
  v_fn_before  text;
  v_cfg_before text;
  v_def        text;
  fd           record;
  h            record;
  v_p          record;
  v_m          int;
  v_entry      int;
  v_lived      boolean := false;
  v_lit0       boolean;
  v_pass       int;
  v_dark       text[] := array[null, null]::text[];
  v_open       text[] := array[null, null]::text[];
  v_fought     text[] := array[null, null]::text[];
  v_which      text[] := array[null, null]::text[];
  v_pl         uuid;
  v_pl2        uuid;
  v_npc        uuid;
  v_fl         uuid;
  v_fl2        uuid;
  v_fl3        uuid;
  v_nfl        uuid;
  v_nfl2       uuid;
  v_arm        uuid;
  v_lis        uuid;
  v_bat        uuid;
  v_bat2       uuid;
  v_good       text;
  v_r          jsonb;
  v_f          jsonb;
  v_x          jsonb;
  v_e1         text;
  v_e2         text;
  v_e3         text;
  v_t          timestamptz;
  v_crew       bigint;
  v_note       text := '';
  c_uid   constant uuid := '00000000-0395-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0395-4000-8000-000000000002';
  c_none  constant uuid := '00000000-0395-4000-8000-0000000000ff';
  c_cut_fns constant text[] := array[
    'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 'public.battle_open(text,uuid,uuid,timestamp with time zone)',
    'public.battle_sheet_freeze(uuid,timestamp with time zone)', 'public.battle_resolve(uuid,timestamp with time zone)',
    'public.attack_close(uuid,jsonb,timestamp with time zone)', 'public.battle_log(jsonb,jsonb,text)', 'world.battle(uuid)',
    'public.navy_close(uuid,timestamp with time zone)', 'public.battle_navy_served(uuid)'];
  c_new_fns constant text[] := array[
    'public.battle_armada(uuid,timestamp with time zone)', 'public.attack_armada_gates(uuid,uuid,timestamp with time zone)',
    'public.battle_armada_join(uuid,text,uuid,timestamp with time zone)', 'public.battle_armada_sheet(uuid)', 'public.battle_armada_note(uuid)',
    'public.attack_armada_close(uuid,jsonb,bigint,bigint)', 'public.battle_armada_view(uuid,uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new_fns) f where to_regprocedure(f) is not null)
     or exists (select 1 from pg_constraint c where c.conrelid = 'public.battle_sides'::regclass and c.conname = 'battle_sides_how_check' and pg_get_constraintdef(c.oid) like '%ARMADA%') then
    raise exception '0395 refuses: it has been applied once';
  end if;
  if to_regclass('public.armadas') is null or to_regclass('public.armada_fleets') is null or to_regclass('public.armada_voyages') is null
     or to_regprocedure('public.armada_of(uuid)') is null or to_regprocedure('public.fight_card(uuid,uuid)') is null or to_regprocedure('world.fights()') is null
     or to_regprocedure('public.battle_fight(uuid,integer)') is null or to_regprocedure('public.battle_advance(uuid,timestamp with time zone)') is null
     or to_regprocedure('cmd.battle_stance(uuid,text)') is null or to_regprocedure('public.battle_stance_at(uuid,uuid,timestamp with time zone)') is null
     or to_regprocedure('public.battle_stop(uuid,timestamp with time zone,timestamp with time zone)') is null or to_regprocedure('public.attack_word(numeric,numeric)') is null
     or to_regprocedure('voyage.escort_score(uuid)') is null or to_regprocedure('voyage.fleet_point(uuid,timestamp with time zone)') is null
     or to_regprocedure('voyage.gc_distance_nm(double precision,double precision,double precision,double precision)') is null
     or to_regprocedure('public.raid_crew_lost(uuid,numeric,numeric)') is null or to_regprocedure('public.ship_cargo_tuns(uuid)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('cmd.refuse(text,text,jsonb)') is null or to_regprocedure('cmd.figures(numeric,numeric,text)') is null or to_regprocedure('public.attack_on()') is null
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.battles'::regclass and a.attname = 'sheet' and not a.attisdropped)
     or exists (select 1 from unnest(c_cut_fns) f where to_regprocedure(f) is null) then
    raise exception '0395 refuses: a table or a function it reads or cuts is not in this world (0327 / 0333 / 0357 / 0364 / 0367)';
  end if;
  v_lit0 := public.attack_on();   -- the owner's switch as this file finds it: it is not written, and both arms are proved below

  -- ── 1. THE PRE-IMAGES ──
  create temp table defs_0395 on commit drop as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
         (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
         (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
         (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
    from unnest(c_cut_fns) f(fn);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns) f);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;
  v_entry := (select count(*) from public.client_rpc_entry_points());

  v_ms := v_ms || jsonb_build_object('guard_and_pre_images', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 2. THE HUNKS (each OLD text once in its live body) ──
  create temp table hunks_0395 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0395 (fn, n, old, new) values
    -- THE ATTACK
    ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 1,
$o$  foreach v_fleet in array array[least(p_fleet, p_target), greatest(p_fleet, p_target)] loop
$o$,
$n$  -- 0395 (docs/ARMADA.md section 7): a fleet of an armada attacks with every fleet of hers that is there. Each of them is judged before anything moves, and one refused
  -- refuses the attack under her name (public.attack_armada_gates). A fleet in no armada: one primary-key probe, and nothing.
  perform public.attack_armada_gates(p_player, p_fleet, p_now);
  foreach v_fleet in array array[least(p_fleet, p_target), greatest(p_fleet, p_target)] loop
$n$),
    ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 2,
$o$    'resolves_at', (select b.resolves_at from public.battles b where b.id = v_battle));
$o$,
$n$    'resolves_at', (select b.resolves_at from public.battles b where b.id = v_battle))
    || public.battle_armada_note(v_battle);   -- 0395: an armada's battle says her name and her fleets, and the word is the armada's; any other battle: {}
$n$),
    -- THE OPEN
    ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1,
$o$  foreach v_fleet in array array[p_attacker, p_defender] loop
$o$,
$n$  -- 0395 (docs/ARMADA.md section 7): the fleets of her armada that are there join her side now, before the sheet is frozen, and are stopped by this same loop
  foreach v_fleet in array array[p_attacker, p_defender] || public.battle_armada_join(v_id, p_kind, p_attacker, p_now) loop
$n$),
    ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 1,
$o$  v_st := public.battle_opening_stance(v_def);
$o$,
$n$  perform public.battle_armada_sheet(p_battle);   -- 0395: an armada's sheet names her and her fleets, and its word reads all of them; any other sheet: nothing
  v_st := public.battle_opening_stance(v_def);
$n$),
    -- THE CLOSE
    ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$o$    if s.side = 'ATTACKER' and not s.is_npc then
$o$,
$n$    if s.side = 'ATTACKER' and not s.is_npc   -- 0395: one report a battle, under the fleet that attacked: a fleet that joined as her armada sends none
       and not exists (select 1 from public.battle_sides x where x.battle_id = p_battle and x.fleet_id = s.fleet_id and x.how = 'ARMADA') then
$n$),
    ('public.attack_close(uuid,jsonb,timestamp with time zone)', 1,
$o$   where bs.battle_id = p_battle and bs.side = 'ATTACKER';
$o$,
$n$   where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';   -- 0395: the fleet that attacked; her armada's fleets are public.attack_armada_close's
$n$),
    ('public.attack_close(uuid,jsonb,timestamp with time zone)', 2,
$o$  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);
$o$,
$n$  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost)
      || public.attack_armada_close(p_battle, p_fight, v_gold, v_lost);   -- 0395: her armada's fleets lose their hands by the same row, and each fleet's share is said; no armada: {}
$n$),
    -- THE LOG AND THE READ
    ('public.battle_log(jsonb,jsonb,text)', 1,
$o$  return (v_log - 'end') || '{"atk": true}'::jsonb || case when v_end is null then '{}'::jsonb else jsonb_build_object('end', v_end) end;
$o$,
$n$  return (v_log - 'end') || '{"atk": true}'::jsonb || case when v_end is null then '{}'::jsonb else jsonb_build_object('end', v_end) end
      || case when p_sheet ? 'fleets' then jsonb_build_object('fleets', p_sheet->'fleets') else '{}'::jsonb end;   -- 0395: an armada's log names her fleets above their ships, as a raid's does (0367)
$n$),
    ('world.battle(uuid)', 1,
$o$   where bs.fleet_id = p_fleet and bs.how = 'OPENED' and f.player_id = v_player and bt.sheet is not null
$o$,
$n$   where bs.fleet_id = p_fleet and bs.how in ('OPENED', 'ARMADA') and f.player_id = v_player and bt.sheet is not null   -- 0395: any fleet of hers in it reads the battle
$n$),
    ('world.battle(uuid)', 2,
$o$                                    'navy', b.result #> '{navy,line}') end;
$o$,
$n$                                    'navy', b.result #> '{navy,line}') end
    || public.battle_armada_view(b.id, p_fleet);   -- 0395: her armada's name, her fleets, the side's stance and, closed, each fleet's share; no armada: {}
$n$),
    -- THE NAVY'S COUNT
    ('public.navy_close(uuid,timestamp with time zone)', 1,
$o$  select count(*) filter (where bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at),
$o$,
$n$  select count(*) filter (where bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at),   -- 0395: her own armada is no navy
$n$),
    ('public.navy_close(uuid,timestamp with time zone)', 2,
$o$         bool_or(bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at or ($o$,
$n$         bool_or(bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at or ($n$),
    ('public.battle_navy_served(uuid)', 1,
$o$                     join public.battle_sides o on o.battle_id = b.id and o.how <> 'OPENED' and o.arrives_at <= b.resolves_at
$o$,
$n$                     join public.battle_sides o on o.battle_id = b.id and o.how not in ('OPENED', 'ARMADA') and o.arrives_at <= b.resolves_at   -- 0395: her own armada is no help coming to the other side
$n$);

  -- ── 3. THE CONSTRAINT ──
  alter table public.battle_sides drop constraint battle_sides_how_check;
  alter table public.battle_sides add constraint battle_sides_how_check check (how = any (array['OPENED'::text, 'ESCORT'::text, 'CALLED'::text, 'ARMADA'::text]));

  -- ── 4. THE NEW LEAVES ──
  execute $f$
create function public.battle_armada(p_fleet uuid, p_now timestamptz)
returns table (fleet_id uuid, ord integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0395 (docs/ARMADA.md section 7): WHO ELSE OF HER ARMADA IS THERE, the one reading. For a fleet of an armada, the other fleets of that armada that hold a ship and
  --   lie docked in the port she lies docked in; or
  --   sail under the lead voyage she sails under (0367's one schedule) and are within attack_reach_nm of her (a fleet turned for port alone is not there).
  -- A fleet at anchor has nobody there. In the armada's own order: her flagship fleet first, then as the fleets were made. A fleet in no armada: no row (one primary-key probe).
  select f.id, (row_number() over (order by (f.id = a.flagship_fleet_id) desc, f.created_at, f.id))::int
    from public.armada_fleets me
    join public.armadas a on a.id = me.armada_id
    join public.fleets o on o.id = me.fleet_id
    join public.armada_fleets m on m.armada_id = me.armada_id and m.fleet_id <> me.fleet_id
    join public.fleets f on f.id = m.fleet_id
   where me.fleet_id = p_fleet and f.player_id = o.player_id
     and exists (select 1 from public.ships s where s.fleet_id = f.id)
     and ((o.status = 'DOCKED' and f.status = 'DOCKED' and f.port_id = o.port_id)
       or (o.status = 'SAILING' and f.status = 'SAILING'
           and (select av.lead_voyage_id from public.voyages v join public.armada_voyages av on av.voyage_id = v.id where v.fleet_id = o.id and v.status = 'SAILING')
             = (select av.lead_voyage_id from public.voyages v join public.armada_voyages av on av.voyage_id = v.id where v.fleet_id = f.id and v.status = 'SAILING')
           and (select voyage.gc_distance_nm(x.lat::float8, x.lon::float8, y.lat::float8, y.lon::float8)::numeric
                  from voyage.fleet_point(o.id, p_now) x, voyage.fleet_point(f.id, p_now) y) <= public.wc_num('attack_reach_nm')))
$body$;
$f$;
  comment on function public.battle_armada(uuid, timestamptz) is '0395: the other fleets of a fleet''s armada that are there for a battle she starts (same port, or the same lead voyage within reach), in the armada''s order. Read by public.attack_armada_gates and public.battle_armada_join. Server-only.';

  execute $f$
create function public.attack_armada_gates(p_player uuid, p_fleet uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0395 (docs/ARMADA.md section 7): BEFORE AN ARMADA'S FLEET ATTACKS. The armada's row is locked first (two attacks of one armada wait on each other, never on each other's fleets),
-- every fleet of hers is settled (an act must not reason about a stale position, D.2) and locked in id order, as every verb locks them. Then each fleet that would take part
-- (public.battle_armada) is judged, in the armada's order, and the first refused refuses the attack under HER name: she is not free (E_FLEET_BUSY), she carries cargo
-- (E_HOLD_NOT_EMPTY: a war fleet sails with an empty hold), she fought within attack_cooldown_minutes (E_ATTACK_COOLDOWN). The fleet that attacks is judged by public.attack_for,
-- as she was. A fleet in no armada: one primary-key probe, and nothing.
declare
  v_arm  uuid := public.armada_of(p_fleet);
  v_wait numeric := public.wc_num('attack_cooldown_minutes');
  v_last timestamptz;
  r      record;
begin
  if v_arm is null then
    return;
  end if;
  perform 1 from public.armadas a where a.id = v_arm and a.player_id = p_player for update;
  for r in select af.fleet_id from public.armada_fleets af where af.armada_id = v_arm order by af.fleet_id loop
    perform voyage.settle(r.fleet_id, p_now);
  end loop;
  perform 1 from public.fleets f where f.id in (select af.fleet_id from public.armada_fleets af where af.armada_id = v_arm) order by f.id for update;
  for r in select f.id, f.name, f.busy_until from public.battle_armada(p_fleet, p_now) t join public.fleets f on f.id = t.fleet_id order by t.ord loop
    if r.busy_until is not null then
      perform cmd.refuse('E_FLEET_BUSY', format('%s is not free to fight', r.name));
    end if;
    if exists (select 1 from public.ships s where s.fleet_id = r.id and public.ship_cargo_tuns(s.id) > 0) then
      perform cmd.refuse('E_HOLD_NOT_EMPTY', format('%s carries cargo: a war fleet sails with an empty hold', r.name));
    end if;
    select max(bs.joined_at) into v_last
      from public.battle_sides bs join public.battles b on b.id = bs.battle_id
     where bs.fleet_id = r.id and bs.side = 'ATTACKER' and b.kind = 'ATTACK';
    if v_last is not null and v_last > p_now - make_interval(mins => v_wait::int) then
      perform cmd.refuse('E_ATTACK_COOLDOWN', format('%s fought %s minutes ago: one battle in %s', r.name, floor(extract(epoch from p_now - v_last) / 60), v_wait),
                         cmd.figures(extract(epoch from p_now - v_last) / 60, v_wait, 'minutes'));
    end if;
  end loop;
end
$body$;
$f$;
  comment on function public.attack_armada_gates(uuid, uuid, timestamptz) is '0395: before a fleet of an armada attacks: the armada locked, her fleets settled and locked, and each fleet that would take part judged (free, empty hold, cooldown), refused under her name. Called by public.attack_for. Server-only.';

  execute $f$
create function public.battle_armada_join(p_battle uuid, p_kind text, p_attacker uuid, p_now timestamptz)
returns uuid[]
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0395 (docs/ARMADA.md section 7): HER ARMADA JOINS HER SIDE, at the open, before the sheet is frozen. Each fleet of hers that is there (public.battle_armada) and free takes a
-- row: ATTACKER, how ARMADA, there at once. joined_at is the open's instant and one microsecond more for each, in the armada's order, so every reading that orders a battle's
-- sides by joined_at (the freeze, the close, the map's card) lists the fleet that attacked first and then her armada in its own order, with no change to any of them.
-- Answers the fleets it wrote: public.battle_open's own loop stops them (public.battle_stop), as it stops the two that started it. A probe, or a fleet in no armada: none.
declare
  v_out uuid[] := '{}';
  r     record;
begin
  if p_kind is distinct from 'ATTACK' then
    return v_out;
  end if;
  for r in select t.fleet_id, t.ord from public.battle_armada(p_attacker, p_now) t join public.fleets f on f.id = t.fleet_id where f.busy_until is null order by t.ord loop
    insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how)
    values (p_battle, r.fleet_id, 'ATTACKER', p_now + make_interval(secs => r.ord * 0.000001), p_now, 'ARMADA');
    v_out := v_out || r.fleet_id;
  end loop;
  return v_out;
end
$body$;
$f$;
  comment on function public.battle_armada_join(uuid, text, uuid, timestamptz) is '0395: at an ATTACK''s open, the fleets of the attacker''s armada that are there join her side (how ARMADA); answers them for public.battle_open''s stop loop. Called by public.battle_open. Server-only.';

  execute $f$
create function public.battle_armada_sheet(p_battle uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0395 (docs/ARMADA.md section 7): AN ARMADA'S SHEET, written once, right after public.battle_sheet_freeze froze the hulls. The freeze already holds every hull of her fleets on
-- side b (it reads every side that is there). This adds what names them: `armada` her name, `fleets` [[name, hulls]] in the order of side b (the key a raid's log has: 0367),
-- and `word`, the pre-fight read with ALL of her on her side (the sum of voyage.escort_score). A battle with no ARMADA row: nothing is written.
declare
  v_att uuid;
  v_def uuid;
begin
  if not exists (select 1 from public.battle_sides bs where bs.battle_id = p_battle and bs.how = 'ARMADA') then
    return;
  end if;
  select bs.fleet_id into v_att from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';
  select bs.fleet_id into v_def from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';
  update public.battles b
     set sheet = b.sheet || jsonb_build_object(
           'armada', (select a.name from public.armada_fleets af join public.armadas a on a.id = af.armada_id where af.fleet_id = v_att),
           'fleets', (select jsonb_agg(jsonb_build_array(f.name, (select count(*) from public.ships s where s.fleet_id = f.id)) order by bs.joined_at, bs.fleet_id)
                        from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
                       where bs.battle_id = p_battle and bs.side = 'ATTACKER'),
           'word', public.attack_word((select sum(voyage.escort_score(bs.fleet_id)) from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER'),
                                      voyage.escort_score(v_def)))
   where b.id = p_battle;
end
$body$;
$f$;
  comment on function public.battle_armada_sheet(uuid) is '0395: on an armada''s frozen sheet: her name, her fleets [[name, hulls]] and the word read with all of her. Called by public.battle_sheet_freeze. Server-only.';

  execute $f$
create function public.battle_armada_note(p_battle uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0395: WHAT AN ARMADA'S ATTACK SAYS BESIDE A FLEET'S (public.attack_for's answer, so the preview's too): the word read with all of her, and `armada` {name, fleets (names, in
  -- the sheet's order), ships}. From the sheet, so the preview, the card and the log cannot disagree. Any other battle: {}.
  select coalesce((select jsonb_build_object('word', b.sheet -> 'word',
                            'armada', jsonb_build_object('name', b.sheet -> 'armada',
                                        'fleets', (select jsonb_agg(x.e -> 0 order by x.o) from jsonb_array_elements(b.sheet -> 'fleets') with ordinality x(e, o)),
                                        'ships', jsonb_array_length(b.sheet -> 'b')))
                     from public.battles b where b.id = p_battle and b.sheet ? 'armada'), '{}'::jsonb)
$body$;
$f$;
  comment on function public.battle_armada_note(uuid) is '0395: what an armada''s attack adds to public.attack_for''s answer: the armada''s word and {name, fleets, ships}; {} for any other battle. Server-only.';

  execute $f$
create function public.attack_armada_close(p_battle uuid, p_fight jsonb, p_gold bigint, p_lost bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0395 (docs/ARMADA.md section 7): WHAT AN ATTACK'S END DOES FOR THE REST OF HER ARMADA, and how it is shared out. Called by public.attack_close alone, under the battle's lock,
-- once, after the fleet that attacked took her own (p_gold the gold that reached the purse, p_lost the hands she lost). A battle with no ARMADA row: {} and nothing is written.
--   CREW   thrown back, broken off or fled (public.attack_close's own test): each fleet that joined loses attack_crew_lost.beaten of every ship's hands, her own surgeon saving
--          his share (public.raid_crew_lost), as the fleet that attacked just did.
--   HULL   nothing is written here: public.fight_hulls_write has put the fight's loss on each ship. A fleet's `hull_lost` is the sum for her ships, never above what stood on the sheet.
--   LOOT   the gold is in the company's purse already, once. A fleet's share is in proportion to the guns she brought (the attack of her hulls on the sheet), rounded down; the
--          remainder is the share of the fleet that attacked. No guns on the sheet at all: all of it is hers.
-- Answers {crew_lost (the sum, which replaces the one fleet's), armada (her name), shares [{fleet, name, loot, crew_lost, hull_lost}]} in the sheet's order.
declare
  b        public.battles%rowtype;
  v_rate   numeric := (public.wc('attack_crew_lost') ->> 'beaten')::numeric;
  v_beaten boolean := p_fight ->> 'outcome' = 'DRIVEN_OFF' or coalesce((p_fight ->> 'broke_off')::boolean, false);
  v_guns   numeric;
  v_total  bigint := coalesce(p_lost, 0);
  v_given  bigint := 0;
  v_before bigint;
  v_l      bigint;
  v_g      bigint;
  v_rows   jsonb := '[]'::jsonb;
  r        record;
begin
  if not exists (select 1 from public.battle_sides bs where bs.battle_id = p_battle and bs.how = 'ARMADA') then
    return '{}'::jsonb;
  end if;
  select * into b from public.battles where id = p_battle;
  select coalesce(sum((e ->> 'attack')::numeric), 0) into v_guns from jsonb_array_elements(b.sheet -> 'b') e;
  for r in select bs.fleet_id, bs.how, f.name,
                  (select coalesce(sum((e ->> 'attack')::numeric), 0) from jsonb_array_elements(b.sheet -> 'b') e join public.ships s on s.id = (e ->> 'id')::uuid where s.fleet_id = bs.fleet_id) as guns,
                  (select coalesce(sum(least((e ->> 'hull')::numeric, coalesce((p_fight -> 'hull_lost' -> 'b' ->> (e ->> 'id'))::numeric, 0))), 0)
                     from jsonb_array_elements(b.sheet -> 'b') e join public.ships s on s.id = (e ->> 'id')::uuid where s.fleet_id = bs.fleet_id) as hull
             from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
            where bs.battle_id = p_battle and bs.side = 'ATTACKER'
            order by bs.how = 'OPENED', bs.joined_at, bs.fleet_id loop   -- the fleet that attacked is read last: her share of the gold is what the others left
    if r.how = 'OPENED' then
      v_l := coalesce(p_lost, 0);
      v_g := coalesce(p_gold, 0) - v_given;
    else
      v_l := 0;
      if v_beaten then
        select coalesce(sum(s.crew), 0) into v_before from public.ships s where s.fleet_id = r.fleet_id;
        update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(r.fleet_id, s.crew, v_rate)) where s.fleet_id = r.fleet_id;
        v_l := v_before - (select coalesce(sum(s.crew), 0) from public.ships s where s.fleet_id = r.fleet_id);
      end if;
      v_g := case when v_guns > 0 then floor(coalesce(p_gold, 0) * r.guns / v_guns)::bigint else 0 end;
      v_given := v_given + v_g;
      v_total := v_total + v_l;
    end if;
    v_rows := case when r.how = 'OPENED' then jsonb_build_array(jsonb_build_object('fleet', r.fleet_id, 'name', r.name, 'loot', v_g, 'crew_lost', v_l, 'hull_lost', round(r.hull, 1))) || v_rows
                   else v_rows || jsonb_build_array(jsonb_build_object('fleet', r.fleet_id, 'name', r.name, 'loot', v_g, 'crew_lost', v_l, 'hull_lost', round(r.hull, 1))) end;
  end loop;
  return jsonb_build_object('crew_lost', v_total, 'armada', b.sheet -> 'armada', 'shares', v_rows);
end
$body$;
$f$;
  comment on function public.attack_armada_close(uuid, jsonb, bigint, bigint) is '0395: at an armada''s battle''s end: the fleets that joined lose their hands by the beaten row, and each fleet''s share of loot, crew loss and hull loss is said. {} for any other battle. Called by public.attack_close. Server-only.';

  execute $f$
create function public.battle_armada_view(p_battle uuid, p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0395: WHAT world.battle ADDS FOR A FLEET OF AN ARMADA'S BATTLE (the side that attacked): `armada` her name; `lead` the fleet that attacked; `stance` the SIDE's stance, which
  -- is that fleet's (cmd.battle_stance keeps one stance a side, so Fight or Flee acts for all of her); `fleets` [{id, name, ships, lead}] in the sheet's order; and, once it is
  -- closed, `shares` (public.attack_armada_close). Any other battle, or a fleet that is not on that side: {}.
  select coalesce((
    select jsonb_build_object(
             'armada', b.sheet -> 'armada', 'lead', o.fleet_id,
             'stance', public.battle_stance_at(b.id, o.fleet_id, 'infinity'),
             'fleets', (select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'ships', (select count(*) from public.ships s where s.fleet_id = f.id), 'lead', bs.how = 'OPENED')
                                         order by bs.joined_at, bs.fleet_id)
                          from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
                         where bs.battle_id = b.id and bs.side = 'ATTACKER'))
           || case when b.status <> 'FIGHTING' and b.result ? 'shares' then jsonb_build_object('shares', b.result -> 'shares') else '{}'::jsonb end
      from public.battles b
      join public.battle_sides o on o.battle_id = b.id and o.side = 'ATTACKER' and o.how = 'OPENED'
     where b.id = p_battle and b.sheet ? 'armada'
       and exists (select 1 from public.battle_sides me where me.battle_id = b.id and me.fleet_id = p_fleet and me.side = 'ATTACKER')), '{}'::jsonb)
$body$;
$f$;
  comment on function public.battle_armada_view(uuid, uuid) is '0395: what world.battle adds for a fleet of an armada''s battle: the armada''s name, the fleet that attacked, the side''s stance, her fleets and, closed, the shares. {} otherwise. Server-only.';

  revoke all on function public.battle_armada(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.attack_armada_gates(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_armada_join(uuid, text, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_armada_sheet(uuid) from public, anon, authenticated;
  revoke all on function public.battle_armada_note(uuid) from public, anon, authenticated;
  revoke all on function public.attack_armada_close(uuid, jsonb, bigint, bigint) from public, anon, authenticated;
  revoke all on function public.battle_armada_view(uuid, uuid) from public, anon, authenticated;

  -- ── 5. THE RE-CUTS (each hunk once) ──
  for fd in select * from defs_0395 x order by x.fn loop
    v_def := fd.def;
    for h in select * from hunks_0395 x where x.fn = fd.fn order by x.n loop
      v_m := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_m <> 1 then
        raise exception '0395 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, fd.fn, v_m;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  for fd in select * from defs_0395 order by fn loop
    v_def := replace(pg_get_functiondef(fd.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0395 x where x.fn = fd.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) is distinct from 1 then
        raise exception '0395 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, h.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def is distinct from fd.def then
      raise exception '0395 self-assert FAIL: % does not reverse to its pre-image', fd.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = fd.fn::regprocedure;
    if v_p.acl is distinct from fd.acl or v_p.vol is distinct from fd.vol or v_p.secdef is distinct from fd.secdef or v_p.cfg is distinct from fd.cfg then
      raise exception '0395 self-assert FAIL: % changed its ACL, volatility, definer or config', fd.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0395) is distinct from 13 then
    raise exception '0395 self-assert FAIL: % hunks, not 13', (select count(*) from hunks_0395);
  end if;
  if exists (select 1 from hunks_0395 x where not exists (select 1 from defs_0395 d where d.fn = x.fn))
     or exists (select 1 from defs_0395 d where not exists (select 1 from hunks_0395 x where x.fn = d.fn)) then
    raise exception '0395 self-assert FAIL: a hunk names a function this file does not cut, or a function it cuts has no hunk';
  end if;
  -- NO PLAYER FIGHTS A PLAYER: the two refusals stand in the two live bodies, word for word, and each comes BEFORE the first line of this file in its body
  if (select p.prosrc from pg_proc p where p.oid = 'public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure)
       not like '%if not (select p.is_npc from public.players p where p.id = d.player_id) then%raise exception ''E_HUMAN_TARGET: no player fights another player''%public.battle_armada_join(%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure)
       not like '%if v_kind = ''COMPANY'' then%perform cmd.refuse(''E_HUMAN_TARGET'', ''no player attacks another player'');%public.attack_armada_gates(%' then
    raise exception '0395 self-assert FAIL: a refusal of a human target is gone, or no longer comes first';
  end if;
  -- DARK BY CONSTRUCTION: in each door's body the switch is read before the first line of this file
  if (select p.prosrc from pg_proc p where p.oid = 'public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure) not like '%if not public.attack_on() then%public.battle_armada_join(%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure) not like '%if not public.attack_on() then%public.attack_armada_gates(%' then
    raise exception '0395 self-assert FAIL: a door reads this file before it reads the switch';
  end if;
  -- each new leaf has the one caller it names, and each of those is behind public.battle_open or public.attack_for (the switch) or reads a battle that only they can make
  if exists (select 1 from (values ('attack_armada_gates', 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'), ('battle_armada_join', 'public.battle_open(text,uuid,uuid,timestamp with time zone)'),
                                   ('battle_armada_sheet', 'public.battle_sheet_freeze(uuid,timestamp with time zone)'), ('battle_armada_note', 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'),
                                   ('attack_armada_close', 'public.attack_close(uuid,jsonb,timestamp with time zone)'), ('battle_armada_view', 'world.battle(uuid)')) w(leaf, caller)
              where exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                             where n.nspname in ('public', 'cmd', 'world', 'voyage') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ ('public\.' || w.leaf || '\(')
                               and p.oid is distinct from w.caller::regprocedure)
                 or regexp_replace((select p.prosrc from pg_proc p where p.oid = w.caller::regprocedure), '--[^\n]*', '', 'g') !~ ('public\.' || w.leaf || '\(')) then
    raise exception '0395 self-assert FAIL: a new leaf is called from a body that is not the one it names, or its caller does not call it';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ '''ARMADA''\)' and p.prosrc ~ 'insert into public\.battle_sides'
                and p.oid is distinct from 'public.battle_armada_join(uuid,text,uuid,timestamp with time zone)'::regprocedure) then
    raise exception '0395 self-assert FAIL: an ARMADA side is written in another place';
  end if;
  -- no client calls a new function; the registry did not move; the reads are STABLE
  if exists (select 1 from unnest(c_new_fns) f cross join unnest(array['anon', 'authenticated']) r(role) where has_function_privilege(r.role, f, 'execute')) then
    raise exception '0395 self-assert FAIL: a client may call a new function';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) is distinct from v_entry or (select count(*) from public.client_write_grants()) is distinct from 0 then
    raise exception '0395 self-assert FAIL: the registry moved, or a client may write a table';
  end if;
  if exists (select 1 from unnest(array['public.battle_armada(uuid,timestamp with time zone)', 'public.battle_armada_note(uuid)', 'public.battle_armada_view(uuid,uuid)', 'world.battle(uuid)',
                                        'public.battle_navy_served(uuid)', 'public.battle_log(jsonb,jsonb,text)']) f
              where (select p.provolatile from pg_proc p where p.oid = f::regprocedure) is distinct from 's') then
    raise exception '0395 self-assert FAIL: a read is not STABLE';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.battle_sides'::regclass and c.conname = 'battle_sides_how_check')
       is distinct from 'CHECK ((how = ANY (ARRAY[''OPENED''::text, ''ESCORT''::text, ''CALLED''::text, ''ARMADA''::text])))' then
    raise exception '0395 self-assert FAIL: the constraint on a side''s `how` is not the four words';
  end if;
  if exists (select 1 from public.battle_sides bs where bs.how = 'ARMADA') then
    raise exception '0395 self-assert FAIL: an ARMADA side exists at the deploy';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_new_fns) f)) is distinct from v_fn_before then
    raise exception '0395 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) is distinct from v_cfg_before or public.attack_on() is distinct from v_lit0 then
    raise exception '0395 self-assert FAIL: a world_config row moved or was added, or the owner''s switch moved';
  end if;

  v_ms := v_ms || jsonb_build_object('made_cut_and_catalog', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 7. THE PROBE, on this file's own rows, rolled back by a raised sentinel ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select g.code into v_good from public.goods g where g.bulk = 1 order by g.code limit 1;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Armada 0395', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa Sozinha 0395', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl2;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0395', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Capitania 0395', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Capitania Um 0395', true, true);
    insert into public.house_room (player_id, kind, steps) values (v_pl, 'FLEET', 4);   -- this probe's own row: room for her second fleet, whatever the owner's free number is
    v_fl2 := public.form_fleet(v_pl, 'Almiranta 0395', v_lis);
    perform public.commission_ship(v_pl, v_fl2, 'barca', 'Almiranta Um 0395', true, true);
    v_fl3 := public.form_fleet(v_pl2, 'Sozinha 0395', v_lis);
    perform public.commission_ship(v_pl2, v_fl3, 'barca', 'Sozinha Um 0395', true, true);
    v_nfl := public.form_fleet(v_npc, 'Mercante 0395', v_lis);
    perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante Um 0395', true, true);
    v_nfl2 := public.form_fleet(v_npc, 'Mercante Dois 0395', v_lis);
    perform public.commission_ship(v_npc, v_nfl2, 'barca', 'Mercante Dois Um 0395', true, true);
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.6 where id in (v_nfl, v_nfl2);
    -- the armada, on this probe's own rows (the forming door is 0367's and is proved there; this file must not lean on armada_enabled)
    insert into public.armadas (player_id, name, flagship_fleet_id) values (v_pl, 'Armada 0395', v_fl2) returning id into v_arm;
    insert into public.armada_fleets (fleet_id, armada_id) values (v_fl, v_arm), (v_fl2, v_arm);
    v_t := date_trunc('second', now());

    -- THE SWITCH OFF (here only; rolled back with the probe), whichever way the owner has it
    update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
    -- (a) DARK, OLD AGAINST NEW, DOOR BY DOOR, AS TEXT, with an armada standing in port. Pass 1 puts the nine old bodies back (inside a subtransaction that is rolled back),
    --     pass 2 is this file. Every door a client has to a battle, the closer, and each re-cut read. (The minute job is not called here: on a lit world it would fight other
    --     companies' battles inside this probe. It is not cut, and proof 69 plays it.)
    for v_pass in 1 .. 2 loop
      begin
        if v_pass = 1 then
          for fd in select * from defs_0395 order by fn loop
            execute fd.def;
          end loop;
        end if;
        v_which[v_pass] := (select string_agg(md5(replace(pg_get_functiondef(f::regprocedure), E'\r', '')), ',' order by f) from unnest(c_cut_fns) f);
        begin perform public.attack_for(v_pl, v_fl, v_nfl, null, v_t); v_e1 := 'attacked'; exception when others then v_e1 := sqlerrm; end;
        begin perform public.battle_open('ATTACK', v_fl, v_nfl, v_t); v_e2 := 'opened'; exception when others then v_e2 := sqlerrm; end;
        begin perform public.attack_for(v_pl2, v_fl3, v_nfl2, null, v_t); v_e3 := 'attacked'; exception when others then v_e3 := sqlerrm; end;
        perform cmd.assume_identity(c_uid);
        v_dark[v_pass] := jsonb_build_object(
          'attack_for', v_e1, 'battle_open', v_e2, 'attack_for_alone', v_e3,
          'cmd_attack', cmd.attack(v_fl, v_nfl, null), 'cmd_preview_attack', cmd.preview_attack(v_fl, v_nfl), 'cmd_preview_sister', cmd.preview_attack(v_fl2, v_nfl),
          'cmd_battle_stance', cmd.battle_stance(c_none, 'FLEE'), 'world_battle', world.battle(v_fl), 'world_battle_sister', world.battle(v_fl2),
          'world_fights', world.fights(), 'world_fight', world.fight(c_none),
          'battle_resolve', public.battle_resolve(c_none, v_t), 'battle_advance', public.battle_advance(c_none, v_t),
          'navy_served', jsonb_build_array(public.battle_navy_served(v_fl), public.battle_navy_served(v_fl2)), 'navy_close', public.navy_close(c_none, v_t),
          'battle_log', public.battle_log('{"a": [], "b": [], "foe": "X", "you": "Y"}'::jsonb, '{"outcome": "NO_FIGHT"}'::jsonb, 'ATTACKER'),
          'sides', (select count(*) from public.battle_sides bs where bs.fleet_id in (v_fl, v_fl2, v_fl3)),
          'fleets', (select jsonb_agg(jsonb_build_array(f.status, f.busy_until, f.version) order by f.name) from public.fleets f where f.id in (v_fl, v_fl2, v_fl3, v_nfl, v_nfl2)))::text;
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('request.jwt.claims', '', true);
        raise exception using errcode = 'ZY395', message = 'PASS_ROLLBACK_0395';
      exception when sqlstate 'ZY395' then
        null;
      end;
    end loop;
    if v_which[1] is not distinct from v_which[2]
       or v_which[1] is distinct from (select string_agg(md5(d.def), ',' order by d.fn) from defs_0395 d) then
      raise exception '0395 self-assert FAIL: the old bodies were not the ones the dark pass ran under';
    end if;
    if v_dark[1] is null or v_dark[1] is distinct from v_dark[2] then
      raise exception '0395 self-assert FAIL: DARK, a door answers another thing than it did: old % new %', v_dark[1], v_dark[2];
    end if;
    if v_dark[2] not like '%E_NOT_IN_USE: attacks are not in use%' or v_dark[2] not like '%E_NOT_YET: attack_enabled is off%' then
      raise exception '0395 self-assert FAIL: dark, the attack or the open did not refuse by the switch: %', v_dark[2];
    end if;
    if (select string_agg(md5(replace(pg_get_functiondef(f::regprocedure), E'\r', '')), ',' order by f) from unnest(c_cut_fns) f) is not distinct from v_which[1] then
      raise exception '0395 self-assert FAIL: the old bodies outlived the dark pass';
    end if;

    -- (b) LIT (here only; rolled back). NO PLAYER FIGHTS A PLAYER, by either door, with an armada on the attacking side: nothing is written.
    update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
    begin perform public.battle_open('ATTACK', v_fl, v_fl3, v_t); v_e1 := 'opened'; exception when others then v_e1 := sqlerrm; end;
    begin perform public.attack_for(v_pl, v_fl, v_fl3, null, v_t); v_e2 := 'attacked'; exception when others then v_e2 := sqlerrm; end;
    if v_e1 not like 'E_HUMAN_TARGET:%' or v_e2 not like 'E_HUMAN_TARGET:%' or exists (select 1 from public.battles b join public.battle_sides bs on bs.battle_id = b.id where bs.fleet_id in (v_fl, v_fl2, v_fl3)) then
      raise exception '0395 self-assert FAIL: A PLAYER COULD FIGHT A PLAYER: battle_open %, attack_for %', v_e1, v_e2;
    end if;

    -- (c) LIT, A FLEET IN NO ARMADA: her battle opens, and fights its first rounds, to the same text under the old bodies and the new. The open is compared with the battle's
    --     id written out (it is random); the rounds are fought on ONE battle (opened by this file), first under the old bodies, then under the new, each rolled back.
    for v_pass in 1 .. 2 loop
      begin
        if v_pass = 1 then
          for fd in select * from defs_0395 order by fn loop
            execute fd.def;
          end loop;
        end if;
        v_bat2 := public.battle_open('ATTACK', v_fl3, v_nfl2, v_t);
        perform cmd.assume_identity(c_uid2);
        v_open[v_pass] := replace(jsonb_build_object(
          'battle', (select to_jsonb(b) from public.battles b where b.id = v_bat2),
          'sides', (select jsonb_agg(to_jsonb(bs) order by bs.joined_at, bs.fleet_id) from public.battle_sides bs where bs.battle_id = v_bat2),
          'fleets', (select jsonb_agg(jsonb_build_array(f.status, f.busy_until, f.version) order by f.name) from public.fleets f where f.id in (v_fl3, v_nfl2)),
          'read', world.battle(v_fl3), 'card', public.fight_card(v_bat2, v_pl2), 'navy', public.battle_navy_served(v_fl3),
          'log', public.battle_log((select b.sheet from public.battles b where b.id = v_bat2), public.battle_fight(v_bat2, null), 'ATTACKER'))::text, v_bat2::text, 'BATTLE');
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('request.jwt.claims', '', true);
        raise exception using errcode = 'ZY395', message = 'PASS_ROLLBACK_0395';
      exception when sqlstate 'ZY395' then
        null;
      end;
    end loop;
    if v_open[1] is null or v_open[1] is distinct from v_open[2] then
      raise exception '0395 self-assert FAIL: LIT, a fleet in no armada opens another battle than she did: old % new %', v_open[1], v_open[2];
    end if;
    v_bat2 := public.battle_open('ATTACK', v_fl3, v_nfl2, v_t);
    for v_pass in 1 .. 2 loop
      begin
        if v_pass = 1 then
          for fd in select * from defs_0395 order by fn loop
            execute fd.def;
          end loop;
        end if;
        insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (v_bat2, v_fl3, v_t + interval '90 seconds', 'FLEE');
        v_m := public.battle_advance(v_bat2, v_t + interval '185 seconds');
        perform cmd.assume_identity(c_uid2);
        v_fought[v_pass] := jsonb_build_object(
          'logged', v_m, 'battle', (select to_jsonb(b) from public.battles b where b.id = v_bat2),
          'rounds', (select jsonb_agg(to_jsonb(r) order by r.g) from public.battle_rounds r where r.battle_id = v_bat2),
          'read', world.battle(v_fl3), 'card', public.fight_card(v_bat2, v_pl2), 'watch', world.fight(v_bat2), 'navy', public.battle_navy_served(v_fl3),
          'ships', (select jsonb_agg(jsonb_build_array(s.durability, s.crew) order by s.name) from public.ships s where s.fleet_id in (v_fl3, v_nfl2)))::text;
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('request.jwt.claims', '', true);
        raise exception using errcode = 'ZY395', message = 'PASS_ROLLBACK_0395';
      exception when sqlstate 'ZY395' then
        null;
      end;
    end loop;
    if v_fought[1] is null or v_fought[1] is distinct from v_fought[2] or (v_fought[2]::jsonb ->> 'logged')::int < 1 then
      raise exception '0395 self-assert FAIL: LIT, a fleet in no armada fights other rounds, or reads another battle, than she did: old % new %', v_fought[1], v_fought[2];
    end if;
    -- and what this file adds to her battle is nothing: no side joined, no name on the sheet, no note, no view, no share
    if (select count(*) from public.battle_sides bs where bs.battle_id = v_bat2) is distinct from 2
       or (select b.sheet ?| array['armada', 'fleets'] from public.battles b where b.id = v_bat2)
       or public.battle_armada_note(v_bat2) is distinct from '{}'::jsonb or public.battle_armada_view(v_bat2, v_fl3) is distinct from '{}'::jsonb
       or public.attack_armada_close(v_bat2, '{"outcome": "DRIVEN_OFF"}'::jsonb, 1001, 3) is distinct from '{}'::jsonb
       or exists (select 1 from public.battle_armada(v_fl3, v_t)) then
      raise exception '0395 self-assert FAIL: a battle of a fleet in no armada took something of this file';
    end if;
    v_note := format('a fleet in no armada: her open and %s round(s) the same text under the old bodies and the new', (v_fought[2]::jsonb ->> 'logged'));

    -- (d) LIT, THE ARMADA. Who is there; the gates; the open; the sheet; held; the reads; the stance for the side; the rounds; the shares.
    if (select jsonb_agg(t.fleet_id order by t.ord) from public.battle_armada(v_fl, v_t) t) is distinct from jsonb_build_array(v_fl2)
       or (select jsonb_agg(t.fleet_id order by t.ord) from public.battle_armada(v_fl2, v_t) t) is distinct from jsonb_build_array(v_fl) then
      raise exception '0395 self-assert FAIL: two fleets of one armada docked in one port are not there for each other';
    end if;
    begin
      -- a sister in another port, and a fleet at anchor: nobody is there
      update public.fleets set port_id = (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_lis order by p.code limit 1) where id = v_fl2;
      if exists (select 1 from public.battle_armada(v_fl, v_t)) or public.battle_armada_join(c_none, 'ATTACK', v_fl, v_t) is distinct from '{}'::uuid[] then
        raise exception '0395 self-assert FAIL: a fleet in another port is there';
      end if;
      update public.fleets set port_id = v_lis where id = v_fl2;
      update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.6 where id = v_fl;
      if exists (select 1 from public.battle_armada(v_fl, v_t)) or exists (select 1 from public.battle_armada(v_fl2, v_t)) then
        raise exception '0395 self-assert FAIL: a fleet at anchor has her armada there';
      end if;
      raise exception using errcode = 'ZY395', message = 'PASS_ROLLBACK_0395';
    exception when sqlstate 'ZY395' then
      null;
    end;
    -- the gates: free and empty, she passes; a sister with cargo, or not free, refuses the attack under the sister's name; a probe's open takes no armada
    perform public.attack_armada_gates(v_pl, v_fl, v_t);
    perform public.attack_armada_gates(v_pl2, v_fl3, v_t);
    begin
      if public.fleet_load(v_fl2, v_good, 1, 10) is distinct from 1::numeric then
        raise exception '0395 self-assert FAIL: the probe''s cargo did not load';
      end if;
      begin perform public.attack_armada_gates(v_pl, v_fl, v_t); v_e1 := 'passed'; exception when others then v_e1 := sqlerrm; end;
      update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fl2;
      update public.fleets set busy_until = v_t + interval '5 minutes' where id = v_fl2;
      begin perform public.attack_armada_gates(v_pl, v_fl, v_t); v_e2 := 'passed'; exception when others then v_e2 := sqlerrm; end;
      raise exception using errcode = 'ZY395', message = 'PASS_ROLLBACK_0395';
    exception when sqlstate 'ZY395' then
      null;
    end;
    if v_e1 is distinct from 'E_HOLD_NOT_EMPTY: Almiranta 0395 carries cargo: a war fleet sails with an empty hold' or v_e2 is distinct from 'E_FLEET_BUSY: Almiranta 0395 is not free to fight'
       or public.battle_armada_join(c_none, 'PROBE', v_fl, v_t) is distinct from '{}'::uuid[] then
      raise exception '0395 self-assert FAIL: the gates: cargo %, busy %', v_e1, v_e2;
    end if;

    v_bat := public.battle_open('ATTACK', v_fl, v_nfl, v_t);
    select to_jsonb(b) into v_r from public.battles b where b.id = v_bat;
    if (select jsonb_agg(jsonb_build_array(bs.fleet_id, bs.side, bs.how, bs.joined_at, bs.arrives_at) order by bs.joined_at, bs.fleet_id) from public.battle_sides bs where bs.battle_id = v_bat and bs.side = 'ATTACKER')
         is distinct from jsonb_build_array(jsonb_build_array(v_fl, 'ATTACKER', 'OPENED', v_t, v_t), jsonb_build_array(v_fl2, 'ATTACKER', 'ARMADA', v_t + interval '1 microsecond', v_t))
       or (select count(*) from public.battle_sides bs where bs.battle_id = v_bat) is distinct from 3
       or (v_r -> 'sheet' -> 'b')::text is distinct from (voyage.fleet_hulls(v_fl) || voyage.fleet_hulls(v_fl2))::text
       or (v_r -> 'sheet' -> 'a')::text is distinct from voyage.fleet_hulls(v_nfl)::text
       or v_r -> 'sheet' ->> 'armada' is distinct from 'Armada 0395' or v_r -> 'sheet' ->> 'you' is distinct from 'Capitania 0395'
       or v_r -> 'sheet' -> 'fleets' is distinct from '[["Capitania 0395", 1], ["Almiranta 0395", 1]]'::jsonb
       or v_r -> 'sheet' ->> 'word' is distinct from public.attack_word(voyage.escort_score(v_fl) + voyage.escort_score(v_fl2), voyage.escort_score(v_nfl))
       or exists (select 1 from public.fleets f where f.id in (v_fl, v_fl2) and (f.status <> 'IN_BATTLE' or f.busy_until is distinct from (v_r ->> 'resolves_at')::timestamptz)) then
      raise exception '0395 self-assert FAIL: the armada''s open: sides %, battle %', (select jsonb_agg(to_jsonb(bs)) from public.battle_sides bs where bs.battle_id = v_bat), v_r;
    end if;
    if public.battle_armada_note(v_bat) is distinct from jsonb_build_object('word', v_r -> 'sheet' -> 'word', 'armada', jsonb_build_object('name', 'Armada 0395', 'fleets', '["Capitania 0395", "Almiranta 0395"]'::jsonb, 'ships', 2))
       or public.battle_navy_served(v_fl) is distinct from '{}'::jsonb or public.battle_navy_served(v_fl2) is distinct from '{}'::jsonb then
      raise exception '0395 self-assert FAIL: the attack''s note, or her own armada read as the navy coming: % / %', public.battle_armada_note(v_bat), public.battle_navy_served(v_fl);
    end if;
    v_x := public.fight_card(v_bat, v_pl);
    if (v_x ->> 'size')::int is distinct from 3 or (v_x ->> 'fleets')::int is distinct from 3 or (v_x ->> 'ships')::int is distinct from 3 or v_x ->> 'mine' is distinct from v_fl::text
       or (select jsonb_agg(e -> 'name' order by o) from jsonb_array_elements(v_x -> 'sides') with ordinality q(e, o) where e ->> 'side' = 'ATTACKER') is distinct from '["Capitania 0395", "Almiranta 0395"]'::jsonb then
      raise exception '0395 self-assert FAIL: the map''s card does not count and list her armada: %', v_x;
    end if;
    -- the read, for the fleet that attacked and for her sister: one battle, one stance, her fleets named, the log's hulls under their fleets
    perform cmd.assume_identity(c_uid);
    v_r := world.battle(v_fl);
    v_x := world.battle(v_fl2);
    if (v_r ->> 'on')::boolean is not true or v_r ->> 'battle' is distinct from v_bat::text or v_x ->> 'battle' is distinct from v_bat::text
       or v_r ->> 'armada' is distinct from 'Armada 0395' or v_r ->> 'lead' is distinct from v_fl::text or v_x ->> 'lead' is distinct from v_fl::text
       or v_r ->> 'stance' is distinct from 'FIGHT' or v_x ->> 'stance' is distinct from 'FIGHT' or v_x -> 'may' is distinct from '["FIGHT", "FLEE"]'::jsonb or v_x ->> 'side' is distinct from 'ATTACKER'
       or (select jsonb_agg(jsonb_build_array(e -> 'id', e -> 'name', e -> 'ships', e -> 'lead') order by o) from jsonb_array_elements(v_r -> 'fleets') with ordinality q(e, o))
            is distinct from jsonb_build_array(jsonb_build_array(v_fl, 'Capitania 0395', 1, true), jsonb_build_array(v_fl2, 'Almiranta 0395', 1, false))
       or v_r -> 'fleets' is distinct from v_x -> 'fleets' or v_r -> 'log' is distinct from v_x -> 'log' or v_r ? 'shares'
       or v_r -> 'log' -> 'fleets' is distinct from '[["Capitania 0395", 1], ["Almiranta 0395", 1]]'::jsonb or jsonb_array_length(v_r -> 'log' -> 'you') is distinct from 2 then
      raise exception '0395 self-assert FAIL: the read of an armada''s battle: hers %, her sister''s %', v_r, v_x;
    end if;
    -- THE STANCE IS THE SIDE'S: Flee, pressed once, is what her sister's card reads too; another company's press is refused; one stance row, the opener's
    perform cmd.assume_identity(c_uid2);
    if cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' or world.battle(v_fl) is distinct from '{"on": false}'::jsonb
       or world.battle(v_fl2) is distinct from '{"on": false}'::jsonb then
      raise exception '0395 self-assert FAIL: another company set a stance in, or read, an armada''s battle';
    end if;
    perform cmd.assume_identity(c_uid);
    v_x := cmd.battle_stance(v_bat, 'FLEE');
    if (v_x ->> 'ok')::boolean is not true or world.battle(v_fl) ->> 'stance' is distinct from 'FLEE' or world.battle(v_fl2) ->> 'stance' is distinct from 'FLEE'
       or (select jsonb_agg(jsonb_build_array(s.fleet_id, s.stance)) from public.battle_stances s where s.battle_id = v_bat) is distinct from jsonb_build_array(jsonb_build_array(v_fl, 'FLEE')) then
      raise exception '0395 self-assert FAIL: Flee did not act for the whole armada: %', v_x;
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    -- the rounds: each row logged is the re-run's row, and under Flee not a gun of the whole side fires
    v_m := public.battle_advance(v_bat, v_t + interval '185 seconds');
    v_f := public.battle_fight(v_bat, greatest(1, (select b.rounds_done from public.battles b where b.id = v_bat)));
    if exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r."row"::text is distinct from (v_f -> 'rounds' -> (r.g - 1))::text)
       or (select count(*) from public.battle_rounds r where r.battle_id = v_bat) is distinct from v_m
       or exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and (not r."row" ? 'b_flee' or (r."row" -> 'b' ->> 'fired')::int is distinct from 0)) then
      raise exception '0395 self-assert FAIL: an armada''s rounds are not the re-run''s rows, or a fleet of hers fired while she ran: % rounds, %', v_m, v_f -> 'rounds';
    end if;
    -- THE SHARES, on a fight written here (the close itself is proof 69's, on a real target). Boarded: no hands lost, the gold shared by the guns on the sheet, to the last ducat.
    v_x := public.attack_armada_close(v_bat, '{"outcome": "PLUNDERED"}'::jsonb, 1001, 0);
    if (v_x ->> 'crew_lost')::bigint is distinct from 0 or v_x ->> 'armada' is distinct from 'Armada 0395' or jsonb_array_length(v_x -> 'shares') is distinct from 2
       or v_x -> 'shares' -> 0 ->> 'fleet' is distinct from v_fl::text or v_x -> 'shares' -> 1 ->> 'fleet' is distinct from v_fl2::text
       or (v_x -> 'shares' -> 0 ->> 'loot')::bigint + (v_x -> 'shares' -> 1 ->> 'loot')::bigint is distinct from 1001
       or (v_x -> 'shares' -> 1 ->> 'loot')::bigint is distinct from
            (select case when sum((e ->> 'attack')::numeric) > 0
                         then floor(1001 * (sum((e ->> 'attack')::numeric) filter (where s.fleet_id = v_fl2)) / sum((e ->> 'attack')::numeric))::bigint else 0 end
               from public.battles b cross join jsonb_array_elements(b.sheet -> 'b') e join public.ships s on s.id = (e ->> 'id')::uuid where b.id = v_bat) then
      raise exception '0395 self-assert FAIL: the shares of a boarding: %', v_x;
    end if;
    -- Thrown back: the sister loses her hands by the beaten row (her own surgeon's share saved), the sum is the report's, and her hull loss is her own ships'
    select coalesce(sum(public.raid_crew_lost(v_fl2, s.crew, (public.wc('attack_crew_lost') ->> 'beaten')::numeric)), 0) into v_crew from public.ships s where s.fleet_id = v_fl2;
    v_e1 := (select sum(s.crew)::text from public.ships s where s.fleet_id = v_fl2);
    v_x := public.attack_armada_close(v_bat, jsonb_build_object('outcome', 'DRIVEN_OFF', 'hull_lost', jsonb_build_object('b',
             jsonb_build_object((select s.id::text from public.ships s where s.fleet_id = v_fl2 limit 1), 7.2, (select s.id::text from public.ships s where s.fleet_id = v_fl limit 1), 99999))), 0, 3);
    if (v_x ->> 'crew_lost')::bigint is distinct from 3 + v_crew or (v_x -> 'shares' -> 0 ->> 'crew_lost')::bigint is distinct from 3 or (v_x -> 'shares' -> 1 ->> 'crew_lost')::bigint is distinct from v_crew
       or (select sum(s.crew) from public.ships s where s.fleet_id = v_fl2) is distinct from v_e1::numeric - v_crew
       or (v_x -> 'shares' -> 1 ->> 'hull_lost')::numeric is distinct from 7.2
       or (v_x -> 'shares' -> 0 ->> 'hull_lost')::numeric is distinct from (select round(sum((e ->> 'hull')::numeric), 1) from jsonb_array_elements(voyage.fleet_hulls(v_fl)) e)
       or (v_x -> 'shares' -> 0 ->> 'loot')::bigint is distinct from 0 or (v_x -> 'shares' -> 1 ->> 'loot')::bigint is distinct from 0 then
      raise exception '0395 self-assert FAIL: the shares of a battle she was thrown back from (the sister''s row of hands is %): %', v_crew, v_x;
    end if;
    v_note := v_note || format('; an armada of two: both on the sheet and held, one stance for the side, %s round(s) each the re-run''s row, the gold shared to the last ducat, the sister lost %s hand(s) by the beaten row', v_m, v_crew);
    raise exception using errcode = 'ZX395', message = 'PROBE_ROLLBACK_0395';
  exception when sqlstate 'ZX395' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0395 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0395' or p.auth_uid in (c_uid, c_uid2))
     or exists (select 1 from public.armadas a where a.name = 'Armada 0395') or exists (select 1 from public.battle_sides bs where bs.how = 'ARMADA') or public.attack_on() is distinct from v_lit0 then
    raise exception '0395 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0395 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if (select string_agg(md5(replace(pg_get_functiondef(f::regprocedure), E'\r', '')), ',' order by f) from unnest(c_cut_fns) f) is not distinct from v_which[1] then
    raise exception '0395 self-assert FAIL: the old bodies outlived the probe';
  end if;

  v_ms := v_ms || jsonb_build_object('probe', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  if extract(epoch from clock_timestamp() - v_t0) > 40 then
    raise exception '0395 self-assert FAIL: the file took % (budget 40 s)', clock_timestamp() - v_t0;
  end if;
  -- THE NEWS (0347's law): only when a player can see it, which is when attacks are lit at this deploy. Idempotent by its number.
  if v_lit0 then
    perform public.news_update('0395', 'Armada battles', '대함대 해전');
  end if;
  raise notice '0395 timings (ms a part): %; total % ms.', v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise notice '0395 self-assert ok: AN ARMADA FIGHTS AS ONE (attack_enabled was % at this deploy and was not written; the news row was % posted). 7 functions (none for a client), no table, no knob, the registry unmoved; 13 hunks on 9 bodies, each once and reversing; ACL, volatility, definer and config unmoved; no other function and no world_config row moved; both refusals of a human target stand and come before anything of this file; no ARMADA side existed. The probe (rolled back), BOTH ARMS: the switch off, with an armada standing in port, every door, the closer and each re-cut read answer the same text under the nine old bodies and the new; the switch on: no player could fight a player; %. % ms.',
    v_lit0, case when v_lit0 then '' else 'not' end, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;

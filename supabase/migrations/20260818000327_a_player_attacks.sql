-- ═══════════════════════════════════════════════════════════════════════════════
-- 0327 — A PLAYER ATTACKS: a war fleet attacks a cargo ship at sea, a timed battle decides it, and gold moves. DARK behind `attack_enabled`
-- ═══════════════════════════════════════════════════════════════════════════════
-- Owner rows 283, 285, slice W11 of docs/WORLD_POWERS.md (section 4): *"people can attack these npc"*; *"players can make fleet - navy - style for pirate attack, or even attack countires which would then lose affinity to that country"*.
-- `attack_enabled` has stood false since 0323. This file does not touch it. Nothing changes for anyone until the owner lights it, and the design says that comes after W12-W14: a player must not attack a country that cannot answer.
--
-- WHO MAY BE ATTACKED (docs/WORLD_POWERS.md 4.2, as built): a cargo ship, at sea, of another country. Nothing else exists to attack: no navy ship (W12), no pirate ship (W17). A merchant is refused (owner question 2),
-- a player's fleet is refused (the no-PvP law stands, owner 2026-11-05: "not for now"), and a ship in port is never attacked.
--
-- WHAT THIS FILE ADDS:
--   public.attack_for      THE one attack: every refusal, then public.battle_open, then the lap mark and the regard. cmd.attack and cmd.preview_attack both run it, so the dry run and the press cannot disagree.
--   public.attack_close    What a closed battle does beyond the hulls: gold, crew, the sink's regard, the wreck. public.battle_resolve calls it for kind ATTACK, once, under the battle's lock.
--   public.loot_take       THE one way gold leaves a ship for a player: public.convoy_book's LOOTED row and public.credit's LOOT, together. Moved, never made.
--   public.loot_due        What the fight earned, under every cap. A pure reading, the self-assert reads it.
--   public.loot_today      What a company has looted in the last 24 hours: the ledger, the one record.
--   public.attack_word, public.funds_band   The two words of a preview. A band, never a forecast.
--   voyage.fleet_point     Where a fleet is: her voyage's point, her roadstead, or her anchor.
--   cargo_ships.last_attacked_lap   The lap she was last attacked on (her out_load; 0 for a ship with no lap).
--   ATTACK in battles_kind_check, LOOTED in convoy_cargo_stage_check, LOOT in stats_flow_words (moved).
--
-- THE HUNKS, each occurs once and reverses to its pre-image: public.battle_open (1), public.battle_resolve (3), public.convoy_book (1), world.cargo_ship_card (1), public.client_rpc_entry_points (1).
--   0324 (#525) hunks none of them. public.tg_convoy_cargo_closes needs no hunk: it counts every row of a load, whatever its stage, so a LOOTED row closes that much of the load and no more.
--
-- WHY NOT A VERB OF cmd.parse (the design's 4.2 says it is; its own slice row names cmd.attack and preview_attack): cmd.issue queues an order and cmd.advance runs a queue only in port, so a fleet at sea could never
--   attack, and an order waiting for a port would fire at a ship long gone. An attack is a helm order, like cmd.divert: its own door, run now.
--
-- MONEY (docs/WORLD_POWERS.md 4.4, docs/CLOSED_ECONOMY.md): funds aboard are inside set_aside. LOOT moves them to a player: set_aside falls by what the purse rises by, in one transaction. LOOT is a `moved` kind, so public.mint_guard passes it
--   on a closed economy, with no new exception. No city purse moves: the city paid when she loaded. A ransom (she paid off) is LOOT too, under the same caps: the design's RANSOM kind is a company paying pirates, the other way.
--
-- DARK IS BYTE-IDENTICAL: public.attack_for refuses E_NOT_IN_USE as its first line, the card serves no `attack` key, kind PROBE takes the old path and v_spoils is {}, and public.convoy_book's three old stages run the old statement.
--   Proof 34 compares the old bodies with the new. No hot path gains a read: none of these five bodies is on the beat.
--
-- DECIDED BY DEFAULT (owner may reverse): docs/dev-log/2026-11-06-a-player-attacks.md lists them all. The ones that shape this file:
--   - Gold only: no goods change hands, and a cargo ship's hold is left alone.
--   - The company cap is a rolling 24 hours, by the ledger. Her book row and the ledger row move together.
--   - A battle running when the switch goes off still pays.
--   - A ship that slipped away costs nobody crew: nothing was fought. Beaten or broken off: the attacker loses `attack_crew_lost`.beaten. The regard is written at the attack, so it stands whatever the battle does.
--   - BREAK OFF is not built: the design's 5.2 has it, this slice's row does not. BROKEN_OFF still has no writer.
--
-- SELF-ASSERT: the catalog, plus public.loot_due's arithmetic, which reads knobs and writes nothing. THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4).
-- THE LIVE PATHS ARE PROVED IN CI: proof 34, scripts/db/proofs/34_a_player_attacks.sql, on a closed economy. Mutation controls: scripts/ops/harness/attacks/proof-0327.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. convoy_cargo_stage_check and battles_kind_check are re-checked over their tables in it. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `attack_enabled` false stops new attacks and running battles finish. Regard and loot already written stay. To remove: swap this file's old and new, then drop what it created.
-- VERSION: 0327, after 0324 (#525), 0325 (Levels, #527) and 0326 (HQ Production). Written against prod head 0323. Applied after 0324 by the harness (--first); re-read 0325's and 0326's public.client_rpc_entry_points hunks before deploying.
-- ═══════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_words_before text;
  v_meta_before  text;
  c_keys constant text[] := array['loot_share', 'loot_per_ship', 'loot_per_company_day', 'attack_reach_nm', 'attack_cooldown_minutes', 'attack_crew_lost', 'attack_word_bands', 'regard_attack_cargo', 'regard_sink'];
  c_new_fns constant text[] := array[
    'public.attack_word(numeric,numeric)', 'public.funds_band(bigint)', 'public.loot_due(text,bigint,bigint)', 'public.loot_today(uuid,timestamp with time zone)',
    'public.loot_take(uuid,uuid,text,timestamp with time zone)', 'voyage.fleet_point(uuid,timestamp with time zone)', 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)',
    'public.attack_close(uuid,jsonb,timestamp with time zone)', 'cmd.attack(uuid,uuid,integer)', 'cmd.preview_attack(uuid,uuid)'];
  c_hunked constant text[] := array[
    'public.battle_open(text,uuid,uuid,timestamp with time zone)', 'public.battle_resolve(uuid,timestamp with time zone)', 'public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)',
    'world.cargo_ship_card(uuid)', 'public.client_rpc_entry_points()'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from public.stats_flow_words w where w.kind = 'LOOT')
     or exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'cargo_ships' and c.column_name = 'last_attacked_lap') then
    raise exception '0327 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.battle_open(text,uuid,uuid,timestamp with time zone)') is null or to_regprocedure('public.ransom_take(bigint)') is null then
    raise exception '0327 refuses: 0322 or 0323 is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_words_before
    from public.stats_flow_words w;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 1. THE TABLES ──
  alter table public.battles drop constraint battles_kind_check, add constraint battles_kind_check check (kind in ('PROBE', 'ATTACK'));
  alter table public.convoy_cargo drop constraint convoy_cargo_stage_check,
    add constraint convoy_cargo_stage_check check (stage = any (array['LOADED', 'DELIVERED', 'RETURNED', 'LOOTED']));
  alter table public.cargo_ships add column last_attacked_lap bigint;
  comment on column public.cargo_ships.last_attacked_lap is
    '0327 (docs/WORLD_POWERS.md 4.2): the lap she was last attacked on: her out_load then, 0 if she had none. Equal to her lap now, she is not attacked again. One writer: public.attack_for.';

  -- ── 2. THE KNOBS AND THE KIND (all new; no existing key is touched) ──
  insert into public.world_config (key, value, description) values
    ('loot_share', '0.15'::jsonb, '0327: the share of what is aboard a boarded ship pays (docs/WORLD_POWERS.md 4.4). Read by public.loot_due.'),
    ('loot_per_ship', '60000'::jsonb, '0327: the most one attack takes from one ship, boarded or paid off. Read by public.loot_due.'),
    ('loot_per_company_day', '240000'::jsonb, '0327: the most a company takes in any 24 hours. Read by public.loot_due.'),
    ('attack_reach_nm', '240'::jsonb, '0327: how far off a ship can be attacked, in nautical miles as the crow flies.'),
    ('attack_cooldown_minutes', '30'::jsonb, '0327: a fleet starts one battle in this many minutes.'),
    ('attack_crew_lost', '{"beaten": 0.10, "boarded": 0.10, "drove_off": 0.02}'::jsonb, '0327: the share of her hands lost: the attacker beaten or broken off; a cargo ship boarded; a cargo ship that drove them off (docs/WORLD_POWERS.md 3.4, 4.3). Through public.raid_crew_lost.'),
    ('attack_word_bands', '[0.7, 1.3, 2]'::jsonb, '0327: her escort score over yours: below the first she is weaker, then about even, then stronger, and far stronger from the last. Words only; it decides nothing.'),
    ('regard_attack_cargo', '-150'::jsonb, '0327: regard with her country for attacking a cargo ship (docs/WORLD_POWERS.md 2.1). Written when the attack is made.'),
    ('regard_sink', '-100'::jsonb, '0327: regard with her country, more, when every hull she had is at 0.');
  insert into public.stats_flow_words (kind, side, word, ord) values ('LOOT', 'moved', 'Loot', 50);

  -- ── 3. THE READINGS ──
  execute $f$
create function public.attack_word(p_ours numeric, p_theirs numeric)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0327: THE side's word in a preview: her escort score (voyage.escort_score) over yours, read against attack_word_bands. Decides nothing, and is no forecast: the fight is the fight.
  select case when coalesce(p_ours, 0) <= 0 then 'far_stronger'
              when p_theirs / p_ours < (b.value->>0)::numeric then 'weaker'
              when p_theirs / p_ours < (b.value->>1)::numeric then 'even'
              when p_theirs / p_ours < (b.value->>2)::numeric then 'stronger'
              else 'far_stronger' end
    from (select public.wc('attack_word_bands') as value) b
$body$;
$f$;

  execute $f$
create function public.loot_due(p_outcome text, p_aboard bigint, p_taken bigint)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0327: WHAT A FIGHT EARNS, under every cap (docs/WORLD_POWERS.md 4.3, 4.4): boarded, loot_share of what is aboard, rounded down; paid off, public.ransom_take; anything else, nothing. Then held to loot_per_ship, to what is left
  -- of loot_per_company_day after p_taken, and to what is aboard. Never below 0. Whole ducats.
  select greatest(0, least(
           case p_outcome when 'PLUNDERED' then floor(greatest(coalesce(p_aboard, 0), 0) * public.wc_num('loot_share'))::bigint
                          when 'RANSOM' then public.ransom_take(p_aboard)
                          else 0 end,
           public.wc_num('loot_per_ship')::bigint,
           public.wc_num('loot_per_company_day')::bigint - coalesce(p_taken, 0),
           coalesce(p_aboard, 0)))::bigint
$body$;
$f$;

  execute $f$
create function public.funds_band(p_aboard bigint)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0327: what a preview says of her funds: none, light, or heavy once a boarding could reach loot_per_ship. A band, never the figure.
  select case when coalesce(p_aboard, 0) <= 0 then 'none'
              when public.loot_due('PLUNDERED', p_aboard, 0) < public.wc_num('loot_per_ship') then 'light'
              else 'heavy' end
$body$;
$f$;

  execute $f$
create function public.loot_today(p_player uuid, p_now timestamptz default now())
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0327: what a company has looted in the 24 hours to p_now. The ledger is the one record; the index on (player_id, created_at) bounds it to her last day.
  select coalesce(sum(l.ducats_delta), 0)::bigint from public.ledger l
   where l.player_id = p_player and l.created_at > p_now - interval '24 hours' and l.kind = 'LOOT'
$body$;
$f$;

  execute $f$
create function voyage.fleet_point(p_fleet uuid, p_at timestamptz default now())
returns table (lat numeric, lon numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0327: WHERE A FLEET IS: at sea, her voyage's point (voyage.position); in port, her roadstead, where the map draws her; at anchor, her anchor. No row for a fleet that is nowhere.
declare
  v_voyage uuid;
begin
  select v.id into v_voyage from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING';
  if v_voyage is not null then
    return query select p.lat, p.lon from voyage.position(v_voyage, p_at) p;
    return;
  end if;
  return query
    select coalesce(r.roadstead_lat::numeric, f.lat), coalesce(r.roadstead_lon::numeric, f.lon)
      from public.fleets f left join public.sea_reaches r on r.port_id = f.port_id
     where f.id = p_fleet;
end
$body$;
$f$;

  -- ── 4. THE GOLD ──
  execute $f$
create function public.loot_take(p_fleet uuid, p_player uuid, p_outcome text, p_now timestamptz default now())
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0327: GOLD LEAVES A SHIP FOR A PLAYER, the one way. MOVED: the book row takes it out of what is aboard (public.convoy_book, stage LOOTED, set_aside down), public.credit puts it in her purse (kind LOOT), and no city purse moves.
-- The caller holds the ship's fleet row, so a delivery cannot pass this read. THE LOCK ORDER every verb takes: the fleet, then the house, so two battles of one company cannot both read the same day's room. Answers what moved.
declare
  c       public.cargo_ships%rowtype;
  v_load  bigint;
  v_left  bigint;
  v_take  bigint;
begin
  select * into c from public.cargo_ships x where x.fleet_id = p_fleet;
  if c.fleet_id is null then
    return 0;
  end if;
  select a.load_id, a.aboard into v_load, v_left from public.cargo_ship_aboard(p_fleet) a;
  if v_load is null then
    return 0;
  end if;
  perform 1 from public.players pl where pl.id = p_player for update;
  v_take := public.loot_due(p_outcome, v_left, public.loot_today(p_player, p_now));
  if v_take <= 0 then
    return 0;
  end if;
  perform public.convoy_book('LOOTED', p_fleet, c.player_id, (select l.port_id from public.convoy_cargo l where l.id = v_load), v_take, v_load);
  perform public.credit(p_player, 'LOOT', v_take);
  return v_take;
end
$body$;
$f$;

  -- ── 5. THE ATTACK ──
  execute $f$
create function public.attack_for(p_player uuid, p_fleet uuid, p_target uuid, p_version integer, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0327: THE ONE ATTACK (docs/WORLD_POWERS.md 4.2). Each refusal is its own code and comes before anything moves. Both fleets are settled first (DESIGN D.2), then held in public.battle_open's order. public.battle_open opens the battle; here
-- the lap is marked and the regard falls, whatever the battle does ("the attack was made"). Answers the words a preview prints: public.funds_band, public.attack_word, never the figure, never a forecast. Server-only.
declare
  a       public.fleets%rowtype;
  d       public.fleets%rowtype;
  c       public.cargo_ships%rowtype;
  v_kind  text;
  v_fleet uuid;
  v_nm    numeric;
  v_reach numeric := public.wc_num('attack_reach_nm');
  v_wait  numeric := public.wc_num('attack_cooldown_minutes');
  v_last  timestamptz;
  v_guns  numeric;
  v_battle uuid;
begin
  if not public.attack_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'attacks are not in use');
  end if;
  if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = p_player) then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'that fleet is not yours');
  end if;
  v_kind := public.fleet_kind(p_target);
  if v_kind is null then
    perform cmd.refuse('E_NOT_FOUND', 'there is no such ship');
  end if;
  if v_kind = 'COMPANY' then
    perform cmd.refuse('E_HUMAN_TARGET', 'no player attacks another player');
  end if;
  if v_kind <> 'CARGO_SHIP' then
    perform cmd.refuse('E_NOT_A_TARGET', 'merchants are not attacked');
  end if;

  foreach v_fleet in array array[least(p_fleet, p_target), greatest(p_fleet, p_target)] loop
    perform voyage.settle(v_fleet, p_now);
  end loop;
  select * into a from public.fleets where id = p_fleet for update;
  select * into d from public.fleets where id = p_target for update;
  if p_version is not null and p_version <> a.version then
    perform cmd.refuse('E_STALE', format('This fleet has moved on since you looked (you have version %s, it is at %s).', p_version, a.version));
  end if;
  select * into c from public.cargo_ships x where x.fleet_id = p_target;

  if c.nation_id is not distinct from (select pl.nation_id from public.players pl where pl.id = p_player) then
    perform cmd.refuse('E_YOUR_OWN_COUNTRY', format('%s sails for your own country', d.name));
  end if;
  if d.status = 'IN_BATTLE' or d.busy_until is not null then
    perform cmd.refuse('E_FLEET_BUSY', format('%s is already in a battle', d.name));
  end if;
  if d.status not in ('SAILING', 'ANCHORED') then
    perform cmd.refuse('E_TARGET_DOCKED', format('%s is in port, and a harbour keeps the peace', d.name));
  end if;
  if a.status not in ('DOCKED', 'ANCHORED', 'SAILING') or a.busy_until is not null then
    perform cmd.refuse('E_FLEET_BUSY', format('%s is not free to fight', a.name));
  end if;
  select coalesce(sum(world.ship_stat(s.id, 'attack')), 0) into v_guns from public.ships s where s.fleet_id = p_fleet and s.durability > 0;
  if v_guns <= 0 then
    perform cmd.refuse('E_NO_GUNS', format('%s has no guns', a.name));
  end if;
  if exists (select 1 from public.ships s where s.fleet_id = p_fleet and public.ship_cargo_tuns(s.id) > 0) then
    perform cmd.refuse('E_HOLD_NOT_EMPTY', format('%s carries cargo: a war fleet sails with an empty hold', a.name));
  end if;
  select voyage.gc_distance_nm(x.lat::float8, x.lon::float8, y.lat::float8, y.lon::float8)::numeric into v_nm
    from voyage.fleet_point(p_fleet, p_now) x, voyage.fleet_point(p_target, p_now) y;
  if v_nm > v_reach then
    perform cmd.refuse('E_OUT_OF_REACH', format('%s is %s miles off, and you reach %s', d.name, round(v_nm), round(v_reach)), cmd.figures(v_reach, v_nm, 'miles'));
  end if;
  if c.last_attacked_lap is not distinct from coalesce(c.out_load, 0) then
    perform cmd.refuse('E_SHIP_FOUGHT_THIS_LAP', format('%s has fought this lap', d.name));
  end if;
  select max(bs.joined_at) into v_last
    from public.battle_sides bs join public.battles b on b.id = bs.battle_id
   where bs.fleet_id = p_fleet and bs.side = 'ATTACKER' and b.kind = 'ATTACK';
  if v_last is not null and v_last > p_now - make_interval(mins => v_wait::int) then
    perform cmd.refuse('E_ATTACK_COOLDOWN', format('%s fought %s minutes ago: one battle in %s', a.name, floor(extract(epoch from p_now - v_last) / 60), v_wait),
                       cmd.figures(extract(epoch from p_now - v_last) / 60, v_wait, 'minutes'));
  end if;

  v_battle := public.battle_open('ATTACK', p_fleet, p_target, p_now);
  update public.cargo_ships x set last_attacked_lap = coalesce(x.out_load, 0) where x.fleet_id = p_target;
  perform public.regard_add(p_player, c.nation_id, public.wc_num('regard_attack_cargo'), 'ATTACK_CARGO');
  return jsonb_build_object('battle_id', v_battle, 'fleet', a.name, 'target', d.name, 'nm', round(v_nm),
    'nation', (select n.code from public.nations n where n.id = c.nation_id),
    'word', public.attack_word(voyage.escort_score(p_fleet), voyage.escort_score(p_target)),
    'funds', public.funds_band((select a2.aboard from public.cargo_ship_aboard(p_target) a2)),
    'resolves_at', (select b.resolves_at from public.battles b where b.id = v_battle));
end
$body$;
$f$;

  execute $f$
create function public.attack_close(p_battle uuid, p_fight jsonb, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0327: WHAT AN ATTACK'S END DOES beyond the hulls (docs/WORLD_POWERS.md 3.4, 4.3). Called by public.battle_resolve alone, under the battle's lock, once: gold, then the hands, then the sink. Gold comes before the wreck, because a wreck sends all
-- that is left home (public.npc_wreck). Answers what the report adds to the battle's result: {loot, crew_lost}.
declare
  v_a       record;
  c         public.cargo_ships%rowtype;
  v_d       uuid;
  v_out     text := p_fight->>'outcome';
  v_broke   boolean := coalesce((p_fight->>'broke_off')::boolean, false);
  v_rates   jsonb := public.wc('attack_crew_lost');
  v_gold    bigint := 0;
  v_voyage  public.voyages%rowtype;
  v_before  bigint;
  v_lost    bigint := 0;
begin
  select bs.fleet_id, f.player_id into v_a
    from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
   where bs.battle_id = p_battle and bs.side = 'ATTACKER';
  select bs.fleet_id into v_d from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER';
  perform 1 from public.fleets f where f.id = v_d for update;
  select * into c from public.cargo_ships x where x.fleet_id = v_d;

  if v_out in ('PLUNDERED', 'RANSOM') then
    v_gold := public.loot_take(v_d, v_a.player_id, v_out, p_now);
  end if;

  if v_out = 'DRIVEN_OFF' or v_broke then
    select coalesce(sum(s.crew), 0) into v_before from public.ships s where s.fleet_id = v_a.fleet_id;
    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_a.fleet_id, s.crew, (v_rates->>'beaten')::numeric)) where s.fleet_id = v_a.fleet_id;
    v_lost := v_before - (select coalesce(sum(s.crew), 0) from public.ships s where s.fleet_id = v_a.fleet_id);
    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_d, s.crew, (v_rates->>'drove_off')::numeric)) where s.fleet_id = v_d;
  elsif v_out = 'PLUNDERED' then
    update public.ships s set crew = greatest(0, s.crew - public.raid_crew_lost(v_d, s.crew, (v_rates->>'boarded')::numeric)) where s.fleet_id = v_d;
  end if;

  if exists (select 1 from public.ships s where s.fleet_id = v_d)
     and not exists (select 1 from public.ships s where s.fleet_id = v_d and s.durability > 0) then
    perform public.regard_add(v_a.player_id, c.nation_id, public.wc_num('regard_sink'), 'SINK_CARGO');
    if public.npc_wrecked(v_d) then
      select * into v_voyage from public.voyages v where v.fleet_id = v_d and v.status = 'SAILING';
      perform voyage.npc_wreck(v_d, v_voyage.id, v_voyage.last_settled_day + 1);
    end if;
  end if;
  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);
end
$body$;
$f$;

  -- ── 6. THE DOORS ──
  execute $f$
create function cmd.attack(p_fleet uuid, p_target uuid, p_expected_version integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0327: the caller's fleet attacks p_target, now, wherever she is. A helm order, not a queued one: see the file's header. The core is public.attack_for.
declare
  v_player uuid := public.current_player_id();
  v_out    jsonb;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    v_out := public.attack_for(v_player, p_fleet, p_target, p_expected_version, now());
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
  return jsonb_build_object('ok', true, 'version', (select f.version from public.fleets f where f.id = p_fleet)) || v_out;
end
$body$;
$f$;

  execute $f$
create function cmd.preview_attack(p_fleet uuid, p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0327: cmd.attack's dry run: the real attack, rolled back. {ok, estimate} or the refusal it would give, so the two cannot disagree.
declare
  v_player uuid := public.current_player_id();
  v_out    jsonb;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    v_out := jsonb_build_object('ok', true, 'estimate', public.attack_for(v_player, p_fleet, p_target, null, now()) - 'battle_id');
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;
$f$;

  revoke all on function public.attack_word(numeric, numeric) from public, anon, authenticated;
  revoke all on function public.funds_band(bigint) from public, anon, authenticated;
  revoke all on function public.loot_due(text, bigint, bigint) from public, anon, authenticated;
  revoke all on function public.loot_today(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.loot_take(uuid, uuid, text, timestamptz) from public, anon, authenticated;
  revoke all on function voyage.fleet_point(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.attack_for(uuid, uuid, uuid, integer, timestamptz) from public, anon, authenticated;
  revoke all on function public.attack_close(uuid, jsonb, timestamptz) from public, anon, authenticated;
  revoke all on function cmd.attack(uuid, uuid, integer) from public, anon;
  grant execute on function cmd.attack(uuid, uuid, integer) to authenticated;
  revoke all on function cmd.preview_attack(uuid, uuid) from public, anon;
  grant execute on function cmd.preview_attack(uuid, uuid) to authenticated;

  -- ── 7. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0327 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0327 values
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1,
$h$  if p_kind is distinct from 'PROBE' then$h$,
$h$  if p_kind is null or p_kind not in ('PROBE', 'ATTACK') then   -- 0327: ATTACK comes from public.attack_for alone$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$h$  v_rep   jsonb;
begin$h$,
$h$  v_rep   jsonb;
  v_spoils jsonb := '{}'::jsonb;   -- 0327: what an attack's end adds to the report; a probe adds nothing
begin$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 2,
$h$  update public.battles set status = 'RESOLVED', result = v_f where id = p_battle;
$h$,
$h$  update public.battles set status = 'RESOLVED', result = v_f where id = p_battle;
  if b.kind = 'ATTACK' then   -- 0327: gold, hands and the sink, once, under this row's lock
    v_spoils := public.attack_close(p_battle, v_f, p_now);
    update public.battles set result = result || v_spoils where id = p_battle;
  end if;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 3,
$h$'outcome', v_f->>'outcome') || v_rep);$h$,
$h$'outcome', v_f->>'outcome') || v_rep || v_spoils);$h$),
  ('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)', 1,
$h$  perform public.treasury_post(p_port,
    case p_stage when 'LOADED' then 'CONVOY_LOAD' when 'DELIVERED' then 'CONVOY_DELIVER' when 'RETURNED' then 'CONVOY_RETURN' end,
    case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');$h$,
$h$  if p_stage <> 'LOOTED' then   -- 0327: looted gold goes to a player, not to a purse: public.loot_take credits her, and no city moves
    perform public.treasury_post(p_port,
      case p_stage when 'LOADED' then 'CONVOY_LOAD' when 'DELIVERED' then 'CONVOY_DELIVER' when 'RETURNED' then 'CONVOY_RETURN' end,
      case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');
  end if;$h$),
  ('world.cargo_ship_card(uuid)', 1,
$h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet));$h$,
$h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet))
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0327: the key is served only while attacks are lit, and the card's button reads it$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'preview_tow',           'uuid'),$h$,
$h$      ('cmd',         'preview_tow',           'uuid'),
      -- 0327: a fleet attacks a cargo ship, and its dry run. Dark: E_NOT_IN_USE.
      ('cmd',         'attack',                'uuid, uuid, int'),
      ('cmd',         'preview_attack',        'uuid, uuid'),$h$);

  for v_h in select h.fn from hunks_0327 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0327 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0327 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0327 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0327 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0327 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 8. SELF-ASSERT: the catalog and one pure reading ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0327 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0327 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> 'LOOT') <> v_words_before then
    raise exception '0327 self-assert FAIL: a money word moved';
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'LOOT') is distinct from 'moved' then
    raise exception '0327 self-assert FAIL: LOOT is not a moved kind';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0327 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if public.attack_on() then
    raise exception '0327 self-assert FAIL: attacks are not dark';
  end if;
  if exists (select 1 from public.battles b where b.kind = 'ATTACK') or exists (select 1 from public.convoy_cargo c where c.stage = 'LOOTED')
     or exists (select 1 from public.cargo_ships c where c.last_attacked_lap is not null) then
    raise exception '0327 self-assert FAIL: an attack is written in this world';
  end if;
  if public.loot_due('PLUNDERED', 380000, 0) <> 57000 or public.loot_due('PLUNDERED', 1000000, 0) <> 60000 or public.loot_due('PLUNDERED', 1000000, 230000) <> 10000
     or public.loot_due('PLUNDERED', 1000000, 240000) <> 0 or public.loot_due('PLUNDERED', 1000000, 999999) <> 0 or public.loot_due('RANSOM', 380000, 0) <> 30400
     or public.loot_due('RANSOM', 10000000, 0) <> 60000 or public.loot_due('DRIVEN_OFF', 1000000, 0) <> 0 or public.loot_due('EVADED', 1000000, 0) <> 0 or public.loot_due('PLUNDERED', null, 0) <> 0 then
    raise exception '0327 self-assert FAIL: public.loot_due is not under its caps';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where f not like 'cmd.%' and (has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))) then
    raise exception '0327 self-assert FAIL: a server-only function of this file is open to clients';
  end if;
  if has_function_privilege('anon', 'cmd.attack(uuid,uuid,integer)'::regprocedure, 'execute') or has_function_privilege('anon', 'cmd.preview_attack(uuid,uuid)'::regprocedure, 'execute')
     or not has_function_privilege('authenticated', 'cmd.attack(uuid,uuid,integer)'::regprocedure, 'execute') or not has_function_privilege('authenticated', 'cmd.preview_attack(uuid,uuid)'::regprocedure, 'execute') then
    raise exception '0327 self-assert FAIL: a door is wrongly granted';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('attack', 'preview_attack') and e.fn is not null) <> 2 then
    raise exception '0327 self-assert FAIL: the two doors are not in the client registry';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0327 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0327 self-assert ok: A PLAYER ATTACKS, dark. % hunks once each and reversing; no other function, no existing knob or word, no attack written; no game step ran (proof 34 runs them in CI). % ms.',
    (select count(*) from hunks_0327), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0327;
end
$m$;

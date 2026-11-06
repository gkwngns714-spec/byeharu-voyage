-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0334 — WANTED: what no ship could reach is answered later. A navy may meet a Hostile or WANTED company at sea, frozen at departure. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner rows 285, 286, slice W14 of docs/WORLD_POWERS.md (section 5.3): *"the navy of that country may attack your merchant fleet"*; *"if a fight is made in pacifics, it would need a longer time for the navy to defend"*.
--
-- DARK: `navy_hunt_per_day` is 0, read by voyage.hostile_freeze alone. No side row and no mark on a voyage's path can be written, so voyage.hazard_roll and voyage.settle run what they ran. attack_enabled, navy_enabled and regard_enabled are
-- also dark and this file touches none of them. Parity is proved, not argued: scripts/ops/harness/wanted/dark-scene.sql, before and after this file, every line equal.
--
-- WANTED: public.wanted, one row a battle whose nation came too late or not at all, or whose attacker won. `until` = since + wanted_hours, or a paid fine. One writer: public.wanted_mark, which W13 calls for a late ship and public.attack_close calls
-- at a battle's end. Marking one battle twice writes one row. One reader: public.wanted_nations. WANTED is regard plus memory: no second rule of who is hunted, only twice the chance.
--
-- FROZEN AT DEPARTURE. voyage.depart, for a human company alone, calls voyage.hostile_freeze, which writes a side row public.voyage_hostile for each country that has a Hostile regard or a WANTED mark on her, and has a ship to send.
-- The row holds the chance, the ship and her sheet as she stood. The waters she covers (the seas of the harbours within navy_reach_nm sailed of her station, public.sea_reaches) are marked on the voyage's frozen segments as `navy`.
-- Nothing is read after that but those two frozen things, so a voyage that left before she was Hostile never meets a navy, and one that left Hostile still may after she has paid. As PIRATES: settled late, it rolls the same.
--
-- NO READ FOR A MERCHANT. voyage.depart's first statement reads is_npc from the row it already joins; a merchant stops there. voyage.hazard_roll tests a key of the leg it already holds. Neither names public.wanted, public.voyage_hostile or public.house_regard
-- on a merchant's path. Proof 41 renames all three away and sails a merchant through. No foreign key on voyage_hostile.voyage_id: it would cost every merchant voyage public.npc_compact deletes a read.
--
-- THE ROLL. voyage.hazard_roll draws its three streams as ever, so no other day moves. On a marked leg, a fourth stream, 'navy', against the frozen chance (voyage.navy_finds): a hit makes the day NAVY, at most once a voyage. p_hazard stays the sea's, so the
-- premium (voyage.risk_quote) learns nothing of it.
--
-- THE MEETING. voyage.settle's NAVY arm hands the day to voyage.navy_meets: public.fight_sides, her fleet as she is, the navy's ship as frozen, seed (voyage, day). No sizing up: the navy always closes.
--   Her hull by the fight, no hull below navy_hull_floor of its size. The navy's real ship takes her hurt, and the frozen sheet is never re-read, so her later state cannot move the day.
--   PLUNDERED: DESIGN B.6's table: voyage.raid_takes (25-50 %, its own stream), navy_crew_lost through public.raid_crew_lost, goods moved to the capital's stock (public.stock_seized), never minted, insurance through public.insurance_claim, and the fine.
--   RANSOM: the fine alone. DRIVEN_OFF, EVADED: nothing but the shot.
--   THE FINE: public.navy_fine_due: navy_fine_share of her cargo at goods.base_value, a pure figure, at most navy_fine_cap. Kind FINE, moved, her purse to the capital, through public.pay_city. The figure is the day's and stands in its payload; a purse that cannot cover it
--   pays what it holds, no debt, and FINE_PAID says what moved. It buys back bad regard at the fine's own price, never above what is owed, and clears WANTED when nothing is left owed, as a fine paid at the capital does.
--   Sinking her: regard_sink, through public.regard_add, the one writer.
--
-- THE RE-CUTS (hunks of the live bodies, read at head 0331; each occurs once and reverses to its pre-image; these supersede the same lines of 0330's voyage.depart, voyage.hazard_roll and voyage.settle, 0327's public.attack_close, and 0319's public.fine_for and public.regard_line):
--   voyage.depart (2):         reads is_npc in its first statement; a human's voyage goes through voyage.hostile_freeze.
--   voyage.hazard_roll (1):    the NAVY day, on a marked leg only.
--   voyage.settle (1):         the NAVY arm.
--   public.attack_close (1):   the mark, at a battle's end.
--   public.fine_for (1):       a fine that leaves nothing owed ends WANTED.
--   public.regard_line (1):    `wanted_hours`, served only while she is wanted by that country.
--
-- NEW: public.wanted, public.voyage_hostile, the kind NAVY in voyage_event_kinds. Event WANTED. Knobs below.
--
-- SELF-ASSERT: the catalog, one row of the empty side table rolled back by a raised error, and arithmetic. No game step (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 41, scripts/db/proofs/41_wanted.sql. Mutation controls: scripts/ops/harness/wanted/proof-0334.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, owner only): `navy_hunt_per_day` 0: no new voyage is hunted. Voyages already frozen keep their rows to their end: that is the law of the slice. Marks already written fade by `until`.
-- VERSION: 0334 - follows W13, 0333. It calls nothing of 0333. W13 calls public.wanted_mark; a plpgsql body binds late, so 0333 applies before this file and its call may first run after it. The hunks must be re-read on 0333: scripts/ops/harness/wanted/before.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_n    int;
  v_fn_before    text;
  v_cfg_before   text;
  v_meta_before  text;
  v_kinds_before text;
  v_nat  uuid;
  v_ok   boolean;
  c_keys constant text[] := array['wanted_hours', 'navy_hunt_per_day', 'navy_hunt_wanted_mult', 'navy_fine_share', 'navy_fine_cap', 'navy_hull_floor', 'navy_crew_lost'];
  c_new_fns constant text[] := array[
    'public.wanted_mark(uuid,uuid,uuid,timestamp with time zone)', 'public.wanted_nations(uuid,timestamp with time zone)', 'public.wanted_clear(uuid,uuid,timestamp with time zone)',
    'public.navy_arrived(uuid,uuid,uuid)', 'public.navy_fine_due(numeric)', 'public.navy_fine(uuid,uuid,bigint,timestamp with time zone)', 'public.stock_seized(uuid,jsonb)',
    'voyage.navy_waters(uuid)', 'voyage.hostile_freeze(uuid,uuid,timestamp with time zone)', 'voyage.navy_finds(uuid,integer,uuid)',
    'voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)'];
  c_hunked constant text[] := array[
    'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'voyage.hazard_roll(uuid,integer)', 'voyage.settle(uuid,timestamp with time zone)',
    'public.attack_close(uuid,jsonb,timestamp with time zone)', 'public.fine_for(uuid,uuid,bigint)', 'public.regard_line(uuid,uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.wanted') is not null or to_regclass('public.voyage_hostile') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from public.voyage_event_kinds k where k.code = 'NAVY') then
    raise exception '0334 refuses: something of it is already in this world';
  end if;
  if to_regclass('public.navy_ships') is null or to_regprocedure('public.attack_close(uuid,jsonb,timestamp with time zone)') is null or to_regprocedure('public.regard_add(uuid,uuid,numeric,text)') is null then
    raise exception '0334 refuses: 0319, 0327 or 0331 is not in this world';
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'FINE') is distinct from 'moved' then
    raise exception '0334 refuses: FINE is not a moved kind';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(k.code || ':' || k.ordinal || ':' || k.prose, ',' order by k.code)) into v_kinds_before from public.voyage_event_kinds k;

  -- ── 1. THE TABLES ──
  create table public.wanted (
    player_id uuid        not null references public.players(id) on delete cascade,
    nation_id uuid        not null references public.nations(id),
    battle_id uuid        not null references public.battles(id),
    since     timestamptz not null,
    until     timestamptz not null check (until >= since),
    primary key (battle_id, nation_id)
  );
  create index wanted_player_until on public.wanted (player_id, until desc);
  comment on table public.wanted is
    '0334 (docs/WORLD_POWERS.md section 5.3): a country remembers a battle it did not answer, or lost. One writer: public.wanted_mark. public.wanted_clear ends it early. One reader: public.wanted_nations. A merchant has no row.';
  alter table public.wanted enable row level security;
  revoke all on table public.wanted from public, anon, authenticated;

  create table public.voyage_hostile (
    voyage_id uuid        not null,
    nation_id uuid        not null references public.nations(id),
    chance    numeric     not null check (chance > 0 and chance <= 1),
    fleet_id  uuid        not null,
    sheet     jsonb       not null,
    primary key (voyage_id, nation_id)
  );
  comment on table public.voyage_hostile is
    '0334 (docs/WORLD_POWERS.md section 5.3): a human voyage''s hunters, frozen at departure: the day''s chance, the navy ship, and her sheet as she stood, so a late settle fights the same fight. One writer: voyage.hostile_freeze. A merchant has no row and pays no read: voyage_id has no foreign key, or public.npc_compact would read here for every voyage it deletes.';
  alter table public.voyage_hostile enable row level security;
  revoke all on table public.voyage_hostile from public, anon, authenticated;

  -- ── 2. THE KNOBS AND THE KIND (all new; no existing key is touched) ──
  insert into public.world_config (key, value, description) values
    ('wanted_hours', to_jsonb(48), '0334: real hours a WANTED mark lasts (docs/WORLD_POWERS.md section 5.3). Read when a mark is written, so a change never moves one.'),
    ('navy_hunt_per_day', to_jsonb(0), '0334: THE switch of the hunt, and its size: the chance a day in a hunter''s waters that a navy meets a Hostile company. 0: no voyage is hunted. Owner only. Frozen at departure, so a change moves no voyage at sea.'),
    ('navy_hunt_wanted_mult', to_jsonb(2), '0334: a WANTED mark multiplies navy_hunt_per_day by this. WANTED is twice as likely, and no second rule.'),
    ('navy_fine_share', to_jsonb(0.05), '0334: the fine for a meeting that ends boarded or paid off, as a share of her cargo at goods.base_value. Read by public.navy_fine_due.'),
    ('navy_fine_cap', to_jsonb(100000), '0334: the most one meeting fines. Read by public.navy_fine_due.'),
    ('navy_hull_floor', to_jsonb(0.25), '0334: a navy''s shot leaves each hull at least this share of her size. A hull already below it loses nothing more.'),
    ('navy_crew_lost', to_jsonb(0.10), '0334: the share of her hands a boarding costs, through public.raid_crew_lost, so a Surgeon saves hands here too.');
  insert into public.voyage_event_kinds (code, ordinal, prose, prose_keys, prose_fallbacks, is_rolled, in_sea_mix, note)
  select 'NAVY', max(k.ordinal) + 1, '%s', array['prose'], array['A navy ship stopped us.'], false, false,
         '0334. A CONDITION, never of the sea mix: voyage.hazard_roll answers it on a leg voyage.hostile_freeze marked, at most once a voyage, from its own stream.'
    from public.voyage_event_kinds k;

  -- ── 3. WANTED ──
  execute $f$
create function public.wanted_mark(p_player uuid, p_nation uuid, p_battle uuid, p_at timestamptz default now())
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0334: THE one writer of public.wanted (docs/WORLD_POWERS.md section 5.3). W13 calls it for a ship that came too late, public.attack_close at a battle's end. One row a battle and a nation: a second call writes nothing and says nothing.
-- A merchant, no nation: nothing. Answers whether a row was written. Server-only.
declare
  v_until timestamptz := p_at + make_interval(hours => public.wc_int('wanted_hours'));
  v_n     int;
begin
  if p_player is null or p_nation is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return false;
  end if;
  insert into public.wanted (player_id, nation_id, battle_id, since, until)
  values (p_player, p_nation, p_battle, p_at, v_until)
  on conflict (battle_id, nation_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return false;
  end if;
  perform public.emit_event(p_player, 'WANTED', jsonb_build_object(
    'nation', (select n.code from public.nations n where n.id = p_nation), 'battle_id', p_battle, 'until', v_until, 'hours', public.wc_int('wanted_hours')));
  return true;
end
$body$;
$f$;
  comment on function public.wanted_mark(uuid, uuid, uuid, timestamptz) is
    '0334: THE one writer of public.wanted. W13 calls this for a late ship. Idempotent on (battle, nation). Answers whether it wrote.';

  execute $f$
create function public.wanted_nations(p_player uuid, p_at timestamptz)
returns table (nation_id uuid, until timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0334: THE one reader of public.wanted: each country whose mark on this company stands at p_at, with its last hour.
  select w.nation_id, max(w.until) from public.wanted w where w.player_id = p_player and w.until > p_at group by w.nation_id
$body$;
$f$;

  execute $f$
create function public.wanted_clear(p_player uuid, p_nation uuid, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0334: a paid fine ends the marks of that country, when it leaves nothing owed (public.fine_owed). The one early end of `until`.
begin
  if public.fine_owed(p_player, p_nation) > 0 then
    return;
  end if;
  update public.wanted w set until = greatest(w.since, p_at) where w.player_id = p_player and w.nation_id = p_nation and w.until > p_at;
end
$body$;
$f$;

  execute $f$
create function public.navy_arrived(p_battle uuid, p_nation uuid, p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0334: did a ship of this country reach the battle before it ended? The ship set upon is no answer to her own attack. public.battle_sides is W13's to fill.
  select exists (select 1 from public.battle_sides bs
                   join public.battles b on b.id = bs.battle_id
                   join public.navy_ships n on n.fleet_id = bs.fleet_id
                  where bs.battle_id = p_battle and n.nation_id = p_nation and bs.fleet_id is distinct from p_target
                    and bs.arrives_at <= b.resolves_at)
$body$;
$f$;

  -- ── 4. THE WATERS AND THE FREEZE ──
  execute $f$
create function voyage.navy_waters(p_station uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0334: the waters of a station: its own sea and the sea of each harbour within navy_reach_nm SAILED (public.sea_reaches), so a capital across an isthmus does not count as near. Read at departure only.
  select coalesce(array_agg(distinct p.sea_id), '{}'::uuid[])
    from public.ports p
    join public.sea_reaches r on r.port_id = p_station
   where p.sea_id is not null and (p.id = p_station or (r.reaches ->> p.code)::numeric <= public.wc_num('navy_reach_nm'))
$body$;
$f$;

  execute $f$
create function voyage.hostile_freeze(p_voyage uuid, p_player uuid, p_at timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0334: WHO MAY MEET THIS VOYAGE, frozen as she leaves (docs/WORLD_POWERS.md section 5.3). Called by voyage.depart for a human company alone. Dark: one knob read, nothing else. Each country with a mark on her, or a Hostile regard, sends the ship of its station
-- that covers the most of her course, lowest ord on a tie; its waters are marked on her segments, a leg to one country, a WANTED country first. Any country with no ship to send, or no water on her course, writes nothing. Answers the rows written.
declare
  v_p     numeric := public.wc_num('navy_hunt_per_day');
  v_path  jsonb;
  v_rows  int := 0;
  r       record;
  s       record;
  v_seas  uuid[];
  v_w     uuid[];
  v_best  numeric;
  v_nm    numeric;
  v_ord   int;
  v_fleet uuid;
begin
  if v_p <= 0 or not public.navy_on() then
    return 0;
  end if;
  select v.path into v_path from public.voyages v where v.id = p_voyage;
  for r in
    select x.nation_id, bool_or(x.wanted) as wanted
      from (select w.nation_id, true as wanted from public.wanted_nations(p_player, p_at) w
            union all
            select h.nation_id, false from public.house_regard h
             where h.player_id = p_player and public.regard_on() and public.regard_band(public.regard_of(p_player, h.nation_id)) ->> 'band' = 'hostile') x
     group by x.nation_id
     order by bool_or(x.wanted) desc, x.nation_id
  loop
    v_best := 0;
    v_seas := null;
    for s in select y.station_port, min(y.ord) as ord
               from public.navy_ships_in_service y
              where y.nation_id = r.nation_id and exists (select 1 from public.ships x where x.fleet_id = y.fleet_id and x.durability > 0)
              group by y.station_port
              order by min(y.ord) loop
      v_w := voyage.navy_waters(s.station_port);
      select coalesce(sum((e.seg ->> 'nm')::numeric), 0) into v_nm
        from jsonb_array_elements(v_path) e(seg)
       where not e.seg ? 'navy' and (e.seg ->> 'sea_id')::uuid = any (v_w);
      if v_nm > v_best then
        v_best := v_nm;
        v_seas := v_w;
        v_ord  := s.ord;
      end if;
    end loop;
    continue when v_seas is null;
    select y.fleet_id into v_fleet from public.navy_ships_in_service y where y.nation_id = r.nation_id and y.ord = v_ord;
    select jsonb_agg(case when not e.seg ? 'navy' and (e.seg ->> 'sea_id')::uuid = any (v_seas)
                          then e.seg || jsonb_build_object('navy', r.nation_id) else e.seg end order by e.n)
      into v_path
      from jsonb_array_elements(v_path) with ordinality e(seg, n);
    insert into public.voyage_hostile (voyage_id, nation_id, chance, fleet_id, sheet)
    values (p_voyage, r.nation_id, least(1, v_p * case when r.wanted then public.wc_num('navy_hunt_wanted_mult') else 1 end), v_fleet, voyage.fleet_hulls(v_fleet));
    v_rows := v_rows + 1;
  end loop;
  if v_rows > 0 then
    update public.voyages v set path = v_path where v.id = p_voyage;
  end if;
  return v_rows;
end
$body$;
$f$;

  execute $f$
create function voyage.navy_finds(p_voyage uuid, p_day integer, p_nation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0334: does this country's ship find her on this marked day? Stream 'navy', against the frozen chance, once a voyage. Called only for a leg that carries the mark, so a merchant never reaches it. The earlier days' rows are themselves a pure function of the voyage.
  select coalesce((select voyage.rng(p_voyage, p_day, 'navy') < h.chance
                     from public.voyage_hostile h
                    where h.voyage_id = p_voyage and h.nation_id = p_nation), false)
     and not exists (select 1 from public.voyage_events e where e.voyage_id = p_voyage and e.day_index < p_day and e.kind = 'NAVY')
$body$;
$f$;

  -- ── 5. THE MEETING ──
  execute $f$
create function public.navy_fine_due(p_value numeric)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0334: the fine, from her cargo's value: navy_fine_share, at most navy_fine_cap. Never negative. Read by voyage.navy_meets.
  select least(public.wc_num('navy_fine_cap'), round(greatest(coalesce(p_value, 0), 0) * public.wc_num('navy_fine_share')))::bigint
$body$;
$f$;

  execute $f$
create function public.navy_fine(p_player uuid, p_nation uuid, p_fine bigint, p_at timestamptz)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0334: A NAVY TAKES ITS FINE AT SEA. Moved, kind FINE, her purse to the capital, through public.pay_city, the road public.fine_for takes. She pays what her purse holds, and no debt is left. It buys back bad regard at the fine's own price, never above what is
-- owed, through public.regard_add, and public.wanted_clear decides what it ends. No money can leave for a country with no capital. Answers the ducats moved.
declare
  v_cap   uuid := public.realm_capital(p_nation);
  v_have  bigint;
  v_pay   bigint;
  v_owed  bigint;
  v_event uuid;
begin
  if p_fine <= 0 or v_cap is null then
    return 0;
  end if;
  select pl.ducats into v_have from public.players pl where pl.id = p_player for update;   -- 0122's one lock order: the house, then the city
  v_pay := least(p_fine, greatest(coalesce(v_have, 0), 0));
  if v_pay <= 0 then
    return 0;
  end if;
  v_owed := public.fine_owed(p_player, p_nation);
  v_event := public.emit_event(p_player, 'FINE_PAID', jsonb_build_object(
               'port', (select c.code from public.ports c where c.id = v_cap), 'port_name', (select c.name from public.ports c where c.id = v_cap), 'amount', v_pay,
               'nation', (select n.code from public.nations n where n.id = p_nation), 'at_sea', true));
  perform public.pay_city(p_player, v_cap, 'FINE', v_pay, v_event);
  if v_owed > 0 then
    perform public.regard_add(p_player, p_nation, least(v_pay, v_owed)::numeric / public.wc_int('regard_fine_per_point'), 'FINE');
  end if;
  perform public.wanted_clear(p_player, p_nation, p_at);
  return v_pay;
end
$body$;
$f$;

  execute $f$
create function public.stock_seized(p_port uuid, p_taken jsonb)
returns void
language sql
security definer
set search_path = public, pg_temp
as $body$
  -- 0334: WHAT THE NAVY TOOK GOES TO THE CAPITAL'S STOCK: every unit that left her hold, to the unit, moved and never minted. Every capital lists every good (proof 41).
  update public.port_goods pg set stock = pg.stock + x.q, updated_at = now()
    from (select g.id, (e.value)::text::numeric as q from jsonb_each(coalesce(p_taken, '{}'::jsonb)) e join public.goods g on g.code = e.key) x
   where pg.port_id = p_port and pg.good_id = x.id
$body$;
$f$;

  execute $f$
create function voyage.navy_meets(p_voyage uuid, p_day integer, p_fleet uuid, p_player uuid, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0334: voyage.settle's NAVY arm (docs/WORLD_POWERS.md section 5.3). Her fleet as she is, the ship as frozen, through public.fight_sides, seed (voyage, day), no sizing up. Answers the day's payload, every figure a pure function of the voyage, the day and the frozen row,
-- so a day settled late reads byte for byte as one settled on time. What moved is the ledger's: the fine stands here as the figure levied, and FINE_PAID says what her purse paid.
declare
  h         public.voyage_hostile%rowtype;
  v_ships   jsonb := voyage.fleet_hulls(p_fleet);
  v_f       jsonb;
  v_out     text;
  v_first   text;
  v_country text;
  v_code    text;
  v_cap     uuid;
  v_ship    jsonb;
  v_hull0   numeric;
  v_hull1   numeric;
  v_crew0   numeric;
  v_crew1   numeric;
  v_base    numeric := 0;
  v_value   numeric;
  v_fine    bigint := 0;
  v_taken   jsonb;
  v_prose   text;
  v_lines   text[] := '{}';
  g         int;
begin
  select * into h from public.voyage_hostile x where x.voyage_id = p_voyage and x.nation_id = (voyage.leg_at_day(p_voyage, p_day) ->> 'navy')::uuid;
  if h.voyage_id is null then
    raise exception 'E_KIND_ARM: voyage % met a navy on day % with no frozen row', p_voyage, p_day using errcode = 'P0001';
  end if;
  v_ship := h.sheet -> 0;
  select n.name, n.code into v_country, v_code from public.nations n where n.id = h.nation_id;
  v_cap := public.realm_capital(h.nation_id);
  v_f := public.fight_sides(p_voyage, p_day, v_ships, h.sheet);
  v_out := v_f ->> 'outcome';
  v_first := case v_f ->> 'first' when 'A' then 'YOU' when 'B' then 'THEY' else 'BOTH' end;

  -- THE HULLS: the fight's, and a floor under each of hers. A hull already below it is left as she is.
  select coalesce(sum(s.durability), 0), coalesce(sum(s.crew), 0) into v_hull0, v_crew0 from public.ships s where s.fleet_id = p_fleet;
  update public.ships sh
     set durability = greatest(least(sh.durability, (select b.durability from public.ship_base(sh.id) b) * public.wc_num('navy_hull_floor')), sh.durability - l.lost)
    from (select x.key::uuid as id, x.value::numeric as lost from jsonb_each_text(coalesce(v_f -> 'hull_lost' -> 'a', '{}'::jsonb)) x) l
   where sh.id = l.id and sh.fleet_id = p_fleet;
  select coalesce(sum(s.durability), 0) into v_hull1 from public.ships s where s.fleet_id = p_fleet;
  update public.ships sh set durability = greatest(0, sh.durability - l.lost)
    from (select x.key::uuid as id, x.value::numeric as lost from jsonb_each_text(coalesce(v_f -> 'hull_lost' -> 'b', '{}'::jsonb)) x) l
   where sh.id = l.id and sh.fleet_id = h.fleet_id;
  if coalesce((v_f -> 'hull' ->> 'b')::numeric, 1) <= 0 then
    perform public.regard_add(p_player, h.nation_id, public.wc_num('regard_sink'), 'SINK_NAVY');
  end if;

  -- THE TABLE
  if v_out in ('PLUNDERED', 'RANSOM') then
    select coalesce(sum((e.value)::text::numeric * g2.base_value), 0) into v_value
      from public.ships s cross join lateral jsonb_each(s.cargo) e join public.goods g2 on g2.code = e.key
     where s.fleet_id = p_fleet and jsonb_typeof(e.value) = 'number';
    v_fine := public.navy_fine_due(v_value);
  end if;
  if v_out = 'PLUNDERED' then
    v_base := public.wc_num('navy_crew_lost');
    update public.ships sh set crew = greatest(0, sh.crew - public.raid_crew_lost(p_fleet, sh.crew, v_base)) where sh.fleet_id = p_fleet;
    v_taken := voyage.raid_takes(p_voyage, p_day, p_fleet, 'PLUNDERED');
    perform public.stock_seized(v_cap, v_taken);
    perform public.insurance_claim(p_voyage, p_day, v_taken, 'NAVY');
  end if;
  select coalesce(sum(s.crew), 0) into v_crew1 from public.ships s where s.fleet_id = p_fleet;
  perform public.navy_fine(p_player, h.nation_id, v_fine, p_at);

  -- THE WORDS
  v_prose := case when coalesce((v_f ->> 'slipped')::boolean, false) then format('We saw a navy ship of %s first and slipped away.', v_country)
                  when v_out = 'EVADED' then format('A navy ship of %s came for us, and broke off.', v_country)
                  when v_out = 'DRIVEN_OFF' then format('A navy ship of %s came for us, and we threw her back.', v_country)
                  when v_out = 'RANSOM' then format('A navy ship of %s stopped us, and we paid.', v_country)
                  else format('A navy ship of %s boarded us and took what she could carry.', v_country) end
             || case when v_fine > 0 then format(' She fined us %s d.', v_fine) else '' end;
  v_lines := v_lines || format('Navy: one %s, %s crew.', v_ship ->> 'name', round((v_ship ->> 'crew')::numeric));
  for g in 1 .. coalesce((v_f ->> 'rounds_fought')::int, 0) loop
    v_lines := v_lines || voyage.fight_round_line(v_f -> 'rounds' -> (g - 1), g, v_first, v_ships, greatest(1, (v_f -> 'hull' ->> 'b_start')::numeric), 'enemy');
  end loop;

  return jsonb_build_object('outcome', v_out, 'prose', v_prose, 'nation', v_code, 'fine', v_fine,
                            'crew_before', v_crew0, 'crew_lost', v_crew0 - v_crew1, 'base_loss', v_base,
                            'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2),
                            'rounds', to_jsonb(v_lines),
                            'fight', jsonb_build_object('first', v_first, 'rounds_fought', (v_f ->> 'rounds_fought')::int, 'hull_lost', v_hull0 - v_hull1))
         || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('cargo_lost', v_taken) end;
end
$body$;
$f$;

  revoke all on function public.wanted_mark(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.wanted_nations(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.wanted_clear(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_arrived(uuid, uuid, uuid) from public, anon, authenticated;
  revoke all on function public.navy_fine_due(numeric) from public, anon, authenticated;
  revoke all on function public.navy_fine(uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
  revoke all on function public.stock_seized(uuid, jsonb) from public, anon, authenticated;
  revoke all on function voyage.navy_waters(uuid) from public, anon, authenticated;
  revoke all on function voyage.hostile_freeze(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function voyage.navy_finds(uuid, integer, uuid) from public, anon, authenticated;
  revoke all on function voyage.navy_meets(uuid, integer, uuid, uuid, timestamptz) from public, anon, authenticated;

  -- ── 6. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0334 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0334 values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$h$  e         jsonb;
begin
  select player_id into v_player from public.fleets where id = p_fleet;
$h$,
$h$  e         jsonb;
  v_npc     boolean;   -- 0334: read with the owner, so a merchant stops here and costs no statement
begin
  select f.player_id, p.is_npc into v_player, v_npc from public.fleets f join public.players p on p.id = f.player_id where f.id = p_fleet;
$h$),
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 2,
$h$  returning id into v_voyage;
$h$,
$h$  returning id into v_voyage;

  if not v_npc then   -- 0334: who may meet her is frozen as she leaves
    perform voyage.hostile_freeze(v_voyage, v_player, p_at);
  end if;
$h$),
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$  if not occurred then
    kind := null;
$h$,
$h$  -- 0334: on a leg voyage.hostile_freeze marked, and only there, a navy may find her. The three streams above are drawn as ever and p_hazard stays the sea's, so no other day and no quote moves.
  if v_leg ? 'navy' and voyage.navy_finds(p_voyage, p_day, (v_leg->>'navy')::uuid) then
    occurred := true;
    kind := 'NAVY';
    return next;
    return;
  end if;

  if not occurred then
    kind := null;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$    elsif h.occurred and h.kind = 'FAIR_WIND' then
$h$,
$h$    elsif h.occurred and h.kind = 'NAVY' then
      -- 0334: a country's ship, frozen at departure (voyage.navy_meets). No delay: she sails on.
      v_kind := 'NAVY';
      v_payload := v_payload || voyage.navy_meets(v.id, d, p_fleet, f.player_id, v_bound);

    elsif h.occurred and h.kind = 'FAIR_WIND' then
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 1,
$h$  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);
$h$,
$h$  -- 0334: her country remembers what it did not answer (docs/WORLD_POWERS.md section 5.3): she won, or no ship of it came in time.
  if v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d) then
    perform public.wanted_mark(v_a.player_id, c.nation_id, p_battle, p_now);
  end if;
  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);
$h$),
  ('public.fine_for(uuid,uuid,bigint)', 1,
$h$  v_score := public.regard_add(p_player, v_nat, v_pay::numeric / v_per, 'FINE');
$h$,
$h$  v_score := public.regard_add(p_player, v_nat, v_pay::numeric / v_per, 'FINE');
  perform public.wanted_clear(p_player, v_nat, now());   -- 0334
$h$),
  ('public.regard_line(uuid,uuid)', 1,
$h$    'fine', case when public.city_capital(p_port) = p_port then public.fine_owed(p_player, v_nation) else 0 end));
$h$,
$h$    'fine', case when public.city_capital(p_port) = p_port then public.fine_owed(p_player, v_nation) else 0 end)
    -- 0334: served only while this country's mark stands, so the line is what it was without one
    || coalesce((select jsonb_build_object('wanted_hours', ceil(extract(epoch from w.until - now()) / 3600)::int)
                   from public.wanted_nations(p_player, now()) w where w.nation_id = v_nation), '{}'::jsonb));
$h$);

  for v_h in select h.fn from hunks_0334 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0334 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0334 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0334 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0334 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0334 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 7. SELF-ASSERT: the catalog, arithmetic, and one row of the empty side table, rolled back ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0334 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0334 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0334 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if (select md5(string_agg(k.code || ':' || k.ordinal || ':' || k.prose, ',' order by k.code)) from public.voyage_event_kinds k where k.code <> 'NAVY') <> v_kinds_before then
    raise exception '0334 self-assert FAIL: a voyage event kind moved';
  end if;
  if (select k.in_sea_mix from public.voyage_event_kinds k where k.code = 'NAVY') then
    raise exception '0334 self-assert FAIL: NAVY is in the sea mix: every voyage''s draw would move';
  end if;
  if public.wc_num('navy_hunt_per_day') <> 0 then
    raise exception '0334 self-assert FAIL: the hunt is not dark';
  end if;
  if exists (select 1 from public.wanted) or exists (select 1 from public.voyage_hostile) then
    raise exception '0334 self-assert FAIL: a row is written in this world';
  end if;
  if public.navy_fine_due(0) <> 0 or public.navy_fine_due(null) <> 0 or public.navy_fine_due(-5) <> 0 or public.navy_fine_due(1000) <> 50 or public.navy_fine_due(2000000) <> 100000 or public.navy_fine_due(9000000) <> 100000 then
    raise exception '0334 self-assert FAIL: public.navy_fine_due is not the share under its cap';
  end if;
  select n.id into v_nat from public.nations n order by n.code limit 1;
  begin
    insert into public.voyage_hostile (voyage_id, nation_id, chance, fleet_id, sheet) values ('00000000-0334-4000-8000-000000000001', v_nat, 1, '00000000-0334-4000-8000-000000000002', '[]'::jsonb);
    v_ok := voyage.navy_finds('00000000-0334-4000-8000-000000000001', 1, v_nat)
            and not voyage.navy_finds('00000000-0334-4000-8000-000000000001', 1, null);
    raise exception 'PROBE_0334' using errcode = 'P0334';
  exception when sqlstate 'P0334' then
    null;
  end;
  if not coalesce(v_ok, false) then
    raise exception '0334 self-assert FAIL: a frozen chance of 1 did not find her, or a null nation did';
  end if;
  if exists (select 1 from public.voyage_hostile) then
    raise exception '0334 self-assert FAIL: the probe row was not rolled back';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0334 self-assert FAIL: a server-only function of this file is open to clients';
  end if;
  if has_table_privilege('anon', 'public.wanted', 'select') or has_table_privilege('authenticated', 'public.wanted', 'select')
     or has_table_privilege('anon', 'public.voyage_hostile', 'select') or has_table_privilege('authenticated', 'public.voyage_hostile', 'select') then
    raise exception '0334 self-assert FAIL: a table of this file is open to clients';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0334 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0334 self-assert ok: WANTED, dark. % hunks once each and reversing; no other function, no existing knob or kind moved; one probe row rolled back; no game step ran (proof 41 runs them in CI). % ms.',
    (select count(*) from hunks_0334), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0334;
end
$m$;

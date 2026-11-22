-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0471 - BOUNTIES ON NAMED PIRATES  (dark: the owner's switch pirate_bounties_enabled, false; lit, a few pirate captains are NAMED
--        ("Black Ruy of Port Royal"), each with a bounty posted at a harbour, and a company that beats one in a fight collects it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/playable-2026-11-22.md P2 ("bounties on named pirates"), rule 2 ("something can go wrong, and the player can
--   prepare for it") and rule 3 ("money always has the next thing"). docs/dev-log/2026-11-22-pirate-bounties.md.
--
-- THE RAILS (one authority per concept; nothing here is a second spelling of a rule that exists):
--   * WHO A NAMED PIRATE IS: one of the Brethren's ships (public.pirate_ships, 0339), at work (public.pirate_ships_at_work). Her name is
--     a row of public.pirate_bounties; her ship, her cruise, her raids and her rebirth are 0339/0414/0427/0445's, unchanged.
--   * THE FIGHT: the one battle (public.battle_resolve, 0323), kind RAID (she struck: 0427) or ATTACK (a company struck her: 0327/0375).
--     Its result is the engine's, unchanged. What counts as BEATEN is one function, public.bounty_beaten:
--       RAID   (she attacked a company's ship): she was thrown back (DRIVEN_OFF), or she broke off or ran (broke_off), and the company
--              neither ran nor slipped away (not fled, slipped, stood_off); or every hull of hers is at 0.
--       ATTACK (a company attacked her): boarded (PLUNDERED) or paid off (RANSOM), or every hull of hers is at 0 -- the same test 0340's
--              regard_pirate_beaten makes in public.attack_close.
--     What counts as A SHIP TAKEN: a RAID of hers that ended PLUNDERED or RANSOM, on anybody's ship.
--   * THE MONEY: moved, never made. The bounty is posted by one harbour, the nearest harbour to her home that the pirates do not hold
--     (it has a purse, public.port_treasury), and it is paid from that harbour's purse to the company by public.city_pays (0122,
--     the one rail of a city paying a house), kind PIRATE_BOUNTY (a new MOVED word; 'BOUNTY' is the requests' escrow, 0122/0311).
--     A purse that cannot pay pays what it holds above its reserve (public.city_surplus), as a ransom does. Lit only while the
--     pirates are lit (public.pirates_on, which needs the city purses lit): with the purses dark nothing is named and nothing is paid.
--   * THE SIZE (decided by default, the owner may move every knob): bounty = least(cap, base + per_hour x whole real hours since
--     she was named + per_ship x ships taken), in whole hundreds: base 15,000; +500 an hour free; +2,000 a ship taken; cap 60,000.
--     Production read 2026-11-22 (scripts/ops/harness/pirate-bounties/before-0471.sql): 2,828 raids in 24 h, 930 won by the pirates,
--     116 hunting: a pirate takes about 8 ships a day, so a named one stands near 15,000 + 12,000 + 16,000 = 43,000 after a day free
--     and at the cap within two.
--     Against the play-test's figures (docs/design/content-plan-2026-11.md 5.1: "a trip paid 800 to 13,400, about 4,700 on
--     average") a fresh bounty is about one good trip, a day-old one with a handful of ships taken about three (~40,000), and the
--     cap four and a half. At most bounty_named (4) stand at once, one claim each per bounty_respawn_hours (6): the WORST CASE is
--     4 x 60,000 every 6 hours = 960,000 a day out of the harbours' purses into companies' (moved, not made).
--
-- WHAT THIS FILE DOES:
--   1. THE SWITCH pirate_bounties_enabled (false, DARK) and seven knobs. Dark nothing below writes, pays or serves anything; every
--      hunked body behaves to the byte as before (its `|| '{}'` terms are empty).
--   2. public.pirate_bounties: one row a named pirate, open while she is free, CLAIMED (by whom, how much, which battle) or LAPSED
--      (her ship is gone). `took`: the last 8 ships she took (when, ship, house). Written only by the three functions below.
--   3. public.bounty_on() (the switch's one reader), public.bounty_value(named_at, taken, now) (the one spelling of the size),
--      public.bounty_beaten(kind, fight, pirate) (the one rule of "beaten"), public.bounty_name(epithet, given, home) (the English
--      name the server writes into a report; the client composes its own in each language from the same three parts).
--   4. public.bounty_close(battle, fight, now): THE ONE WRITER of a take or a claim. Dark: '{}' at once. Lit: her RAID won adds a
--      ship to her record; her defeat by a company closes her bounty and pays it (public.city_pays), and answers
--      {bounty: {name, epithet, given, home, paid, value}} for the report. It never raises (a fault is a warning and '{}'), so no
--      battle is ever held by it.
--   5. public.bounty_step(now): THE ONE WRITER of a name. Dark: null at once. Lit, each run of byeharu-voyage:pirates: a named pirate
--      whose ship is gone is LAPSED; closed rows older than bounty_keep_days are deleted (at most 20 a run); and for the first slot
--      (1..bounty_named) with no open bounty and none closed in the last bounty_respawn_hours, ONE pirate at work with a hull afloat,
--      not named and not claimed in the last day, preferring one out at sea, is named: an epithet and a given name not already
--      standing, her home, the posting harbour. At most one named a run. Never raises.
--   6. world.pirate_bounties(): the client's one read (registered). Stable. Dark {"on": false}. Lit: the rates, every standing bounty
--      (her fleet, name parts, home, poster, her sea now, value, ships taken, the last 5 she took), the last 8 claims, and YOUR last
--      8 claims by battle (the fight and arrival cards read "Bounty claimed +N" from the battle's own report; this list is the Rank
--      face's).
--   7. HUNKS (each once, each reverses):
--        public.battle_resolve (2): the ATTACK and RAID arms add public.bounty_close's answer to the battle's spoils, so the
--          attacker's BATTLE_REPORT and battles.result carry it;
--        public.raid_close (1): the raided company's BATTLE_REPORT carries p_fight's bounty when there is one;
--        public.tick_pirates (1): lit, after the strikes, public.bounty_step;
--        public.client_rpc_entry_points (1, at its pirate_ship_card line; 0469 cuts it at houses_week, 0467 at land_repeat).
-- NOT CHANGED: the fight engine, who a pirate strikes (public.raid_target), ransom, loot, regard, the wanted list, a wreck's rebirth,
--   the navy, any price, any purse rule. 0468, 0469 and 0470 (open, deploying first) change none of the bodies cut here but the
--   registry, at another line.
-- ROWS: none while dark. Lit: naming, at most bounty_named (4) rows a bounty_respawn_hours (6) -- 4 inserts in the first 4 minutes,
--   then at most 16 a day; a ship taken by a named pirate, one UPDATE (prod 2026-11-22: 930 raids won a day over 116 hunting pirates,
--   so 4 named pirates take ~32 ships a day); a claim, one UPDATE + one ledger row + one treasury_flows row (rare: a company must beat her);
--   lapse/trim at most 20 deletes a run, ~16 a day in total. ABOUT 0.05 ROWS A MINUTE (under 0.1 at the worst). Reads: one index probe a battle closed
--   (~1-2 a minute), one ~16-row scan a pirates run, and world.pirate_bounties on a Rank or pirate-sheet open (~250 rows, at most).
--   -- budget: none (no cron, no reschedule, no fillfactor, no autovacuum setting; the step rides byeharu-voyage:pirates, the claim the battle's close).
-- LOCKS: CREATE OR REPLACE x4 by hunks (battle_resolve, raid_close, tick_pirates, client_rpc_entry_points); one table, eight new
--   functions, one word, eight knobs. TIME: a second. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, pirate_bounties_enabled false (nothing is named, taken, claimed or served; standing rows
--   lie inert). Full: a new migration reversing the five hunks (OLD texts below verbatim), dropping world.pirate_bounties, the
--   eight functions and public.pirate_bounties, deleting the knobs; PIRATE_BOUNTY stays a word (the ledger keeps its rows).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked functions' grants, volatility, definer, search path
--   and owner unmoved; the knobs; PIRATE_BOUNTY a moved word; world.pirate_bounties registered for authenticated alone, stable; the
--   table and every writer unreachable by a client. THE PROBE (rolled back): the size's arithmetic and cap; the beaten rule on
--   fourteen fight shapes; dark the step, the close and the read are empty; lit (purses and pirates lit in the probe) a probe
--   pirate ship is named with a poster harbour the pirates do not hold, a raid she wins adds a ship, a company's win pays the bounty
--   from the poster's purse to the company once (moved: the purse falls by what the company gains), and the slot is not refilled before the
--   respawn. Proof 174 plays a real raid through tick_pirates and battle_resolve, the attack arm, the respawn and the read.
-- VERSION: 0471 = prod head 0467 + 4 (0468 #787, 0469 #786 and 0470 #784 are open and deploy first; this file touches none of their
--   bodies: 0469 cuts client_rpc_entry_points at its houses_week line, this file at pirate_ship_card).
-- news: none (dark: nothing changes for a player until the owner lights pirate_bounties_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.battle_resolve(uuid,timestamp with time zone)', 'public.raid_close(uuid,jsonb,timestamp with time zone)',
                                    'public.tick_pirates(timestamp with time zone)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.bounty_on()', 'public.bounty_value(timestamp with time zone,integer,timestamp with time zone)',
                                    'public.bounty_beaten(text,jsonb,uuid)', 'public.bounty_name(text,text,uuid)',
                                    'public.bounty_poster(uuid)', 'public.bounty_close(uuid,jsonb,timestamp with time zone)',
                                    'public.bounty_step(timestamp with time zone)', 'world.pirate_bounties()'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_nat       uuid;
  v_pnat      uuid;
  v_home      uuid;
  v_pp        uuid;
  v_pf        uuid;
  v_cp        uuid;
  v_cf        uuid;
  v_b         uuid;
  v_r         jsonb;
  v_row       record;
  v_purse     bigint;
  v_now       timestamptz := date_trunc('minute', now()) + interval '2 days';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'pirate_bounties_enabled') or to_regclass('public.pirate_bounties') is not null then
    raise exception '0471 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) f where to_regprocedure(f) is null)
     or to_regclass('public.pirate_ships') is null or to_regclass('public.pirate_ships_at_work') is null or to_regclass('public.battles') is null
     or to_regprocedure('public.city_pays(uuid,uuid,text,bigint,uuid)') is null or to_regprocedure('public.pirates_on()') is null
     or to_regprocedure('public.city_surplus(uuid)') is null or to_regprocedure('public.port_nation(uuid)') is null then
    raise exception '0471 refuses: 0122 (the purses), 0323 (the battle), 0339 (the pirate ships) or 0427 (the raid) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS, THE WORD, THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('pirate_bounties_enabled', 'false'::jsonb, '0471: THE SWITCH (the owner''s). true, and the pirates lit (public.pirates_on): a few pirate captains are named (public.bounty_step, each run of byeharu-voyage:pirates), each with a bounty posted at the harbour nearest her home that the pirates do not hold; a company that beats one in a fight collects it from that harbour''s purse (public.bounty_close, kind PIRATE_BOUNTY). false: nothing is named, taken, claimed or served; world.pirate_bounties answers {"on": false}.'),
    ('bounty_named',          to_jsonb(4),     '0471: how many named pirates stand at once (slots 1..this). 0 names none.'),
    ('bounty_base',           to_jsonb(15000), '0471: a bounty when she is named, in coin.'),
    ('bounty_per_hour',       to_jsonb(500),   '0471: added to a bounty for each whole real hour she is free.'),
    ('bounty_per_ship',       to_jsonb(2000),  '0471: added to a bounty for each ship she takes (a RAID of hers ending PLUNDERED or RANSOM).'),
    ('bounty_cap',            to_jsonb(60000), '0471: a bounty never grows past this.'),
    ('bounty_respawn_hours',  to_jsonb(6),     '0471: a slot whose pirate was beaten (or lapsed) is filled again after this many real hours.'),
    ('bounty_keep_days',      to_jsonb(14),    '0471: a closed bounty (claimed or lapsed) is kept this many days for the board, then deleted by public.bounty_step.');
  insert into public.stats_flow_words (kind, side, word, ord)
    values ('PIRATE_BOUNTY', 'moved', 'Pirate bounty', (select coalesce(max(w.ord), 0) + 1 from public.stats_flow_words w));

  -- retention: bounty_keep_days (14) after a bounty closes (public.bounty_step deletes, at most 20 a run); open rows at most bounty_named (4); ~16 closed a day at most
  create table public.pirate_bounties (
    id          uuid        primary key default gen_random_uuid(),
    slot        int         not null check (slot between 1 and 50),
    fleet_id    uuid        not null,
    epithet     text        not null,
    given       text        not null,
    home_port   uuid        not null,
    poster_port uuid,
    named_at    timestamptz not null,
    taken       int         not null default 0 check (taken >= 0),
    took        jsonb       not null default '[]'::jsonb,
    closed_at   timestamptz,
    closed      text        check (closed in ('CLAIMED', 'LAPSED')),
    claimed_by  uuid,
    paid        bigint,
    battle_id   uuid,
    check ((closed is null) = (closed_at is null))
  );
  create unique index pirate_bounties_open_slot on public.pirate_bounties (slot) where closed_at is null;
  create unique index pirate_bounties_open_fleet on public.pirate_bounties (fleet_id) where closed_at is null;
  create index pirate_bounties_closed on public.pirate_bounties (closed_at) where closed_at is not null;
  comment on table public.pirate_bounties is
    '0471: NAMED PIRATES. One row a named pirate (a public.pirate_ships fleet): open (closed_at null) while she is free, then CLAIMED (claimed_by, '
    'paid, battle_id) or LAPSED (her ship is gone). taken/took: the ships she took (took: the last 8, {at, ship, house}). Written only by '
    'public.bounty_step (names, lapses, trims), public.bounty_close (takes, claims); read only by world.pirate_bounties. No foreign key: a '
    'claim outlives its pirate and its company, and a key would lock the fleet per row.';
  alter table public.pirate_bounties enable row level security;
  revoke all on table public.pirate_bounties from public, anon, authenticated;

  -- ── 3. THE RULES ──
  execute $f$
create function public.bounty_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0471: THE one reader of the bounties' switch: pirate_bounties_enabled, and the pirates lit (public.pirates_on: pirates_bite and the city purses).
  select coalesce(public.wc('pirate_bounties_enabled') = 'true'::jsonb, false) and public.pirates_on()
$body$
  $f$;

  execute $f$
create function public.bounty_value(p_named_at timestamptz, p_taken integer, p_now timestamptz)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0471: THE size of a bounty: least(bounty_cap, bounty_base + bounty_per_hour x whole real hours free + bounty_per_ship x ships taken), in whole hundreds.
  select (floor(greatest(0, least(public.wc_num('bounty_cap'),
            public.wc_num('bounty_base')
          + public.wc_num('bounty_per_hour') * floor(greatest(0, extract(epoch from (p_now - p_named_at))) / 3600)
          + public.wc_num('bounty_per_ship') * greatest(0, coalesce(p_taken, 0)))) / 100) * 100)::bigint
$body$
  $f$;

  execute $f$
create function public.bounty_beaten(p_kind text, p_fight jsonb, p_pirate uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0471: THE rule of "a company beat the pirate in this fight". RAID (she attacked): thrown back, or she broke off or ran, and the company
  -- did not run, slip away or stand off; ATTACK (the company attacked her): boarded or paid off. Either: every hull of hers at 0.
  select case
    when exists (select 1 from public.ships s where s.fleet_id = p_pirate)
         and not exists (select 1 from public.ships s where s.fleet_id = p_pirate and s.durability > 0) then true
    when p_kind = 'RAID' then
         (p_fight ->> 'outcome' = 'DRIVEN_OFF' or coalesce((p_fight ->> 'broke_off')::boolean, false) or coalesce((p_fight ->> 'b_fled')::boolean, false))
         and not coalesce((p_fight ->> 'fled')::boolean, false)
         and not coalesce((p_fight ->> 'slipped')::boolean, false)
         and not coalesce((p_fight ->> 'stood_off')::boolean, false)
    when p_kind = 'ATTACK' then coalesce(p_fight ->> 'outcome' in ('PLUNDERED', 'RANSOM'), false)
    else false end
$body$
  $f$;

  execute $f$
create function public.bounty_name(p_epithet text, p_given text, p_home uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0471: her name in English, as a report writes it: "Black Ruy of Port Royal". The client composes its own from the same three parts.
  select format('%s %s of %s',
           case p_epithet when 'BLACK' then 'Black' when 'RED' then 'Red' when 'GREY' then 'Grey' when 'ONE_EYED' then 'One-Eyed'
                          when 'IRON' then 'Iron' when 'SILENT' then 'Silent' when 'LUCKY' then 'Lucky' when 'MAD' then 'Mad' else p_epithet end,
           p_given, coalesce((select p.name from public.ports p where p.id = p_home), '?'))
$body$
  $f$;

  execute $f$
create function public.bounty_poster(p_home uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0471: the harbour that posts (and pays) a bounty on a pirate of this home: the nearest harbour with a purse that the pirates do not hold,
  -- one that holds the whole bounty_cap above its reserve first (production, 2026-11-22: the poorest such harbour stood at -116,748).
  select h.id
    from public.ports h join public.port_treasury t on t.port_id = h.id
    cross join (select p.lat, p.lon from public.ports p where p.id = p_home) o
   where h.kind = 'HARBOUR' and h.id <> p_home and not public.pirate_power(public.port_nation(h.id))
   order by public.city_surplus(h.id) < public.wc_num('bounty_cap'), power(h.lat - o.lat, 2) + power((h.lon - o.lon) * cos(radians(o.lat)), 2), h.code
   limit 1
$body$
  $f$;

  -- ── 4. THE CLOSE: a take or a claim, once a battle, under the battle's lock (public.battle_resolve) ──
  execute $f$
create function public.bounty_close(p_battle uuid, p_fight jsonb, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0471: WHAT A BATTLE DOES TO A BOUNTY. Called by public.battle_resolve for kind ATTACK and RAID, under the battle's lock, once. Dark: '{}'
-- at once. RAID, the attacker a named pirate: won (PLUNDERED or RANSOM), one ship more on her record; beaten by a company
-- (public.bounty_beaten), her bounty is CLAIMED and paid. ATTACK, the defender a named pirate, the attacker a company: beaten, the same.
-- The pay: public.bounty_value at p_now, from the poster's purse (public.city_pays, kind PIRATE_BOUNTY), what it holds above its reserve
-- at most. Answers {bounty: {name, epithet, given, home, paid, value}} on a claim, else '{}'. Never raises: a fault is a warning and '{}'.
declare
  v_kind   text;
  v_pir    uuid;
  v_co     uuid;
  v_cof    uuid;
  v_npc    boolean;
  b        public.pirate_bounties%rowtype;
  v_out    text := p_fight ->> 'outcome';
  v_val    bigint;
  v_pay    bigint;
begin
  if not public.bounty_on() then
    return '{}'::jsonb;
  end if;
  begin
    select bt.kind into v_kind from public.battles bt where bt.id = p_battle;
    if v_kind = 'RAID' then
      select bs.fleet_id into v_pir from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';
      select bs.fleet_id, f.player_id, pl.is_npc into v_cof, v_co, v_npc
        from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id join public.players pl on pl.id = f.player_id
       where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';
    elsif v_kind = 'ATTACK' then
      select bs.fleet_id into v_pir from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';
      select bs.fleet_id, f.player_id, pl.is_npc into v_cof, v_co, v_npc
        from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id join public.players pl on pl.id = f.player_id
       where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';
    else
      return '{}'::jsonb;
    end if;
    select * into b from public.pirate_bounties x where x.fleet_id = v_pir and x.closed_at is null for update;
    if b.id is null then
      return '{}'::jsonb;
    end if;

    -- HER RECORD: a raid of hers won, on anybody's ship
    if v_kind = 'RAID' and v_out in ('PLUNDERED', 'RANSOM') then
      update public.pirate_bounties x
         set taken = x.taken + 1,
             took = (jsonb_build_array(jsonb_build_object(
                       'at', p_now, 'battle', p_battle,
                       'ship', (select f.name from public.fleets f where f.id = v_cof),
                       'house', (select pl.company_name from public.fleets f join public.players pl on pl.id = f.player_id where f.id = v_cof)))
                     || x.took) - 8
       where x.id = b.id;
      return '{}'::jsonb;
    end if;

    -- HER DEFEAT, by a company
    if v_co is null or v_npc or not public.bounty_beaten(v_kind, p_fight, v_pir) then
      return '{}'::jsonb;
    end if;
    v_val := public.bounty_value(b.named_at, b.taken, p_now);
    v_pay := case when b.poster_port is null then 0 else least(v_val, greatest(0, public.city_surplus(b.poster_port))) end;
    if v_pay > 0 then
      perform public.city_pays(b.poster_port, v_co, 'PIRATE_BOUNTY', v_pay, null);
    end if;
    update public.pirate_bounties x
       set closed_at = p_now, closed = 'CLAIMED', claimed_by = v_co, paid = v_pay, battle_id = p_battle
     where x.id = b.id;
    return jsonb_build_object('bounty', jsonb_build_object(
      'name', public.bounty_name(b.epithet, b.given, b.home_port), 'epithet', b.epithet, 'given', b.given,
      'home', (select p.code from public.ports p where p.id = b.home_port),
      'poster', (select p.code from public.ports p where p.id = b.poster_port),
      'paid', v_pay, 'value', v_val));
  exception when others then
    raise warning 'bounty_close: battle % left as it was (SQLSTATE %: %)', p_battle, sqlstate, sqlerrm;
    return '{}'::jsonb;
  end;
end
$body$
  $f$;

  -- ── 5. THE STEP: a name, once a run of byeharu-voyage:pirates ──
  execute $f$
create function public.bounty_step(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0471: THE one writer of a NAME. Called by public.tick_pirates (lit, after the strikes). Dark: null at once. Lit: a named pirate whose
-- ship is gone is LAPSED; closed rows older than bounty_keep_days go (at most 20 a run); then the first slot (1..bounty_named) with no
-- open bounty and none closed in the last bounty_respawn_hours names ONE pirate at work with a hull afloat, not named and not claimed in
-- the last day, one out at sea first: an epithet and a given name not standing now, her home, the posting harbour (public.bounty_poster).
-- At most one a run. Answers {lapsed, trimmed, named: slot or null}. Never raises.
declare
  c_given constant text[] := array['Ruy', 'Hayreddin', 'Anne', 'Jack', 'Ching', 'Turgut', 'Grace', 'Henry', 'Murat', 'Edward', 'Piet', 'Diego'];
  c_epith constant text[] := array['BLACK', 'RED', 'GREY', 'ONE_EYED', 'IRON', 'SILENT', 'LUCKY', 'MAD'];
  v_lapsed  int := 0;
  v_trim    int := 0;
  v_slot    int;
  v_fleet   uuid;
  v_home    uuid;
  v_h       int;
  v_given   text;
  v_epith   text;
  i         int;
begin
  if not public.bounty_on() then
    return null;
  end if;
  begin
    update public.pirate_bounties x set closed_at = p_now, closed = 'LAPSED'
     where x.closed_at is null and not exists (select 1 from public.pirate_ships n where n.fleet_id = x.fleet_id);
    get diagnostics v_lapsed = row_count;
    delete from public.pirate_bounties x
     where x.id in (select y.id from public.pirate_bounties y
                     where y.closed_at < p_now - make_interval(days => greatest(1, public.wc_int('bounty_keep_days'))) order by y.closed_at limit 20);
    get diagnostics v_trim = row_count;

    select s into v_slot
      from generate_series(1, greatest(0, least(50, coalesce(public.wc_int('bounty_named'), 0)))) s
     where not exists (select 1 from public.pirate_bounties x where x.slot = s
                         and (x.closed_at is null or x.closed_at > p_now - make_interval(hours => greatest(0, public.wc_int('bounty_respawn_hours')))))
     order by s limit 1;
    if v_slot is null then
      return jsonb_build_object('lapsed', v_lapsed, 'trimmed', v_trim, 'named', null);
    end if;
    select n.fleet_id, n.home_port into v_fleet, v_home
      from public.pirate_ships_at_work n join public.pirate_ships x on x.fleet_id = n.fleet_id
     where x.wrecked_at is null
       and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)
       and not exists (select 1 from public.pirate_bounties y where y.fleet_id = n.fleet_id
                         and (y.closed_at is null or y.closed_at > p_now - interval '1 day'))
     order by (n.sea_id is null), md5(n.fleet_id::text || ':' || v_slot || ':' || (p_now at time zone 'UTC')::date::text)
     limit 1;
    if v_fleet is null then
      return jsonb_build_object('lapsed', v_lapsed, 'trimmed', v_trim, 'named', null);
    end if;
    v_h := abs(hashtext(v_fleet::text || ':' || v_slot || ':' || p_now::text));
    for i in 0 .. array_length(c_given, 1) - 1 loop
      v_given := c_given[1 + (v_h + i) % array_length(c_given, 1)];
      exit when not exists (select 1 from public.pirate_bounties y where y.closed_at is null and y.given = v_given);
    end loop;
    v_epith := c_epith[1 + (v_h / 13) % array_length(c_epith, 1)];
    insert into public.pirate_bounties (slot, fleet_id, epithet, given, home_port, poster_port, named_at)
    values (v_slot, v_fleet, v_epith, v_given, v_home, public.bounty_poster(v_home), p_now);
    return jsonb_build_object('lapsed', v_lapsed, 'trimmed', v_trim, 'named', v_slot);
  exception when others then
    raise warning 'bounty_step: nobody was named (SQLSTATE %: %)', sqlstate, sqlerrm;
    return jsonb_build_object('error', sqlstate);
  end;
end
$body$
  $f$;

  -- ── 6. THE READ ──
  execute $f$
create function world.pirate_bounties()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0471: THE BOUNTIES, served. Dark: {"on": false}. Lit: the rates; every standing bounty (her fleet, the three parts of her name and the English
-- name, home and poster harbours by code, the sea she is in now (null on her way home or in port), whether she is laid up, the bounty now,
-- the ships taken and the last 5 she took); the last 8 claims anywhere (whose, how much); and YOUR last 8 claims, by battle.
declare
  v_me  uuid := public.current_player_id();
  v_now timestamptz := now();
begin
  if not public.bounty_on() then
    return jsonb_build_object('on', false);
  end if;
  return jsonb_build_object(
    'on', true,
    'rates', jsonb_build_object('base', public.wc_num('bounty_base'), 'per_hour', public.wc_num('bounty_per_hour'), 'per_ship', public.wc_num('bounty_per_ship'),
                                'cap', public.wc_num('bounty_cap'), 'respawn_hours', public.wc_num('bounty_respawn_hours')),
    'bounties', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slot', x.slot, 'fleet', x.fleet_id, 'epithet', x.epithet, 'given', x.given,
               'name', public.bounty_name(x.epithet, x.given, x.home_port),
               'home', hp.code, 'poster', pp.code, 'sea', se.name, 'laid_up', n.laid_up_at is not null,
               'named_at', x.named_at, 'value', public.bounty_value(x.named_at, x.taken, v_now), 'taken', x.taken,
               'took', coalesce((select jsonb_agg(t.e order by t.o) from jsonb_array_elements(x.took) with ordinality t(e, o) where t.o <= 5), '[]'::jsonb))
             order by public.bounty_value(x.named_at, x.taken, v_now) desc, x.slot), '[]'::jsonb)
        from public.pirate_bounties x
        join public.ports hp on hp.id = x.home_port
        left join public.ports pp on pp.id = x.poster_port
        left join public.pirate_ships n on n.fleet_id = x.fleet_id
        left join public.seas se on se.id = n.sea_id
       where x.closed_at is null),
    'claims', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'epithet', c.epithet, 'given', c.given, 'name', public.bounty_name(c.epithet, c.given, c.home_port),
               'home', (select p.code from public.ports p where p.id = c.home_port),
               'house', (select pl.company_name from public.players pl where pl.id = c.claimed_by),
               'is_you', c.claimed_by is not distinct from v_me, 'paid', c.paid, 'at', c.closed_at) order by c.closed_at desc), '[]'::jsonb)
        from (select * from public.pirate_bounties y where y.closed = 'CLAIMED' order by y.closed_at desc limit 8) c),
    'mine', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'battle', c.battle_id, 'epithet', c.epithet, 'given', c.given, 'name', public.bounty_name(c.epithet, c.given, c.home_port),
               'home', (select p.code from public.ports p where p.id = c.home_port), 'paid', c.paid, 'at', c.closed_at) order by c.closed_at desc), '[]'::jsonb)
        from (select * from public.pirate_bounties y where y.closed = 'CLAIMED' and v_me is not null and y.claimed_by = v_me order by y.closed_at desc limit 8) c));
end
$body$
  $f$;

  revoke all on function public.bounty_on() from public, anon, authenticated;
  revoke all on function public.bounty_value(timestamptz, integer, timestamptz) from public, anon, authenticated;
  revoke all on function public.bounty_beaten(text, jsonb, uuid) from public, anon, authenticated;
  revoke all on function public.bounty_name(text, text, uuid) from public, anon, authenticated;
  revoke all on function public.bounty_poster(uuid) from public, anon, authenticated;
  revoke all on function public.bounty_close(uuid, jsonb, timestamptz) from public, anon, authenticated;
  revoke all on function public.bounty_step(timestamptz) from public, anon, authenticated;
  revoke all on function world.pirate_bounties() from public, anon;
  grant execute on function world.pirate_bounties() to authenticated;

  -- ── 7. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0471 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0471 values
  ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$h$    v_spoils := public.attack_close(p_battle, v_f, p_now) || public.navy_close(p_battle, p_now);   -- 0333: the ships called are freed, and the report says who came$h$,
$h$    v_spoils := public.attack_close(p_battle, v_f, p_now) || public.navy_close(p_battle, p_now);   -- 0333: the ships called are freed, and the report says who came
    v_spoils := v_spoils || public.bounty_close(p_battle, v_f, p_now);   -- 0471: a named pirate beaten by the company that attacked her: her bounty, paid ('{}' dark)$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 2,
$h$    v_spoils := public.navy_close(p_battle, p_now);$h$,
$h$    v_spoils := public.navy_close(p_battle, p_now);
    v_spoils := v_spoils || public.bounty_close(p_battle, v_f, p_now);   -- 0471: a named pirate's raid: a ship taken on her record, or her bounty paid to the company that beat her ('{}' dark)$h$),
  ('public.raid_close(uuid,jsonb,timestamp with time zone)', 1,
$h$      'fights', '[]'::jsonb));$h$,
$h$      'fights', '[]'::jsonb) || case when p_fight ? 'bounty' then jsonb_build_object('bounty', p_fight -> 'bounty') else '{}'::jsonb end);   -- 0471: the bounty she collected, said on her report$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         -- 0445: LAST, the one ship of this run that may trade takes her step (its `steps` replaces the one above, with her answer counted)$h$,
$h$         -- 0471: the named pirates (public.bounty_step, which never raises): a free slot named, a lapsed one closed, after the strikes, as they are
         || case when v_lit and public.bounty_on() and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('bounties', public.bounty_step(p_now)) else '{}'::jsonb end
         -- 0445: LAST, the one ship of this run that may trade takes her step (its `steps` replaces the one above, with her answer counted)$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'pirate_ship_card',      'uuid'),$h$,
$h$      ('world',       'pirate_ship_card',      'uuid'),
      -- 0471: the named pirates and their bounties (dark: {"on": false})
      ('world',       'pirate_bounties',       ''),$h$);

  for v_h in select h.fn from hunks_0471 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0471 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0471 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0471 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0471 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0471 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 8. SELF-ASSERT: the catalog, the knobs, the word, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0471 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0471 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if public.wc('pirate_bounties_enabled') <> 'false'::jsonb or public.wc_int('bounty_named') <> 4 or public.wc_num('bounty_base') <> 15000
     or public.wc_num('bounty_per_hour') <> 500 or public.wc_num('bounty_per_ship') <> 2000 or public.wc_num('bounty_cap') <> 60000
     or public.wc_int('bounty_respawn_hours') <> 6 or public.wc_int('bounty_keep_days') <> 14
     or not exists (select 1 from public.stats_flow_words w where w.kind = 'PIRATE_BOUNTY' and w.side = 'moved') then
    raise exception '0471 self-assert FAIL: the knobs are not as written, or PIRATE_BOUNTY is not a moved word';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'pirate_bounties', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or exists (select 1 from unnest(c_new) u(q) where u.q <> 'world.pirate_bounties()' and has_function_privilege('authenticated', u.q::regprocedure, 'execute'))
     or has_table_privilege('authenticated', 'public.pirate_bounties', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.pirate_bounties', 'select')
     or (select p.provolatile from pg_proc p where p.oid = 'world.pirate_bounties()'::regprocedure) <> 's'
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0471 self-assert FAIL: world.pirate_bounties is not registered for authenticated alone and stable, or a client reaches a writer or the table';
  end if;

  -- ── 9. THE PROBE, rolled back by a raised sentinel ──
  begin
    -- (a) THE SIZE: base, an hour, a ship, the cap, whole hundreds
    if public.bounty_value(v_now, 0, v_now) <> 15000 or public.bounty_value(v_now, 0, v_now + interval '59 minutes') <> 15000
       or public.bounty_value(v_now, 0, v_now + interval '10 hours') <> 20000 or public.bounty_value(v_now, 3, v_now + interval '1 hour') <> 21500
       or public.bounty_value(v_now, 100, v_now) <> 60000 or public.bounty_value(v_now, 0, v_now - interval '1 hour') <> 15000 then
      raise exception '0471 self-assert FAIL: the size is not base + hours + ships under the cap: % % % % %', public.bounty_value(v_now, 0, v_now),
        public.bounty_value(v_now, 0, v_now + interval '10 hours'), public.bounty_value(v_now, 3, v_now + interval '1 hour'), public.bounty_value(v_now, 100, v_now),
        public.bounty_value(v_now, 0, v_now - interval '1 hour');
    end if;
    -- (b) THE BEATEN RULE on fight shapes (a fleet id with no ships: the hull clause is out)
    for v_row in select * from (values
        ('RAID',   '{"outcome":"DRIVEN_OFF"}',                                  true),
        ('RAID',   '{"outcome":"DRIVEN_OFF","broke_off":true}',                 true),
        ('RAID',   '{"outcome":"EVADED","broke_off":true}',                     true),
        ('RAID',   '{"outcome":"EVADED","b_fled":true,"broke_off":true}',       true),
        ('RAID',   '{"outcome":"EVADED","fled":true}',                          false),
        ('RAID',   '{"outcome":"EVADED","slipped":true}',                       false),
        ('RAID',   '{"outcome":"EVADED","stood_off":true}',                     false),
        ('RAID',   '{"outcome":"PLUNDERED"}',                                   false),
        ('RAID',   '{"outcome":"RANSOM"}',                                      false),
        ('RAID',   '{"outcome":"NO_FIGHT"}',                                    false),
        ('ATTACK', '{"outcome":"PLUNDERED"}',                                   true),
        ('ATTACK', '{"outcome":"RANSOM"}',                                      true),
        ('ATTACK', '{"outcome":"DRIVEN_OFF"}',                                  false),
        ('ATTACK', '{"outcome":"EVADED","fled":true}',                          false)) v(k, f, want) loop
      if public.bounty_beaten(v_row.k, v_row.f::jsonb, gen_random_uuid()) is distinct from v_row.want then
        raise exception '0471 self-assert FAIL: bounty_beaten(%, %) is not %', v_row.k, v_row.f, v_row.want;
      end if;
    end loop;

    -- (c) THE SCENE: a probe pirate home's ship and a company's, lying at one point; a RAID of hers on the company
    v_pnat := public.pirate_nation();
    select n.id into v_nat from public.nations n where n.code = 'PRT';
    select p.id into v_home from public.ports p where p.kind = 'HARBOUR' and public.pirate_home(p.id) order by p.code limit 1;
    if v_home is null then
      select p.id into v_home from public.ports p where p.code = 'LIS';
      v_note := '; no pirate home in this world (Lisbon stood in)';
    end if;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
      values (null, 'Brethren 0471', coalesce(v_pnat, v_nat), 0, true) returning id into v_pp;
    insert into public.fleets (player_id, name, status, port_id) values (v_pp, 'Probe raider 0471', 'DOCKED', v_home) returning id into v_pf;
    insert into public.ships (fleet_id, player_id, class_id, name, is_flagship, durability)
      select v_pf, v_pp, (select c.id from public.ship_classes c order by c.id limit 1), 'Probe raider 0471', true, 100 where not exists (select 1 from public.ships s where s.fleet_id = v_pf);
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, mission, last_port)
      values (v_pf, v_pp, (select coalesce(max(n.ord), 0) + 1000 from public.pirate_ships n), v_home, 'HOME', v_home);
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
      values ('00000000-0471-4000-8000-0000000000c1', 'Casa Prova 0471', v_nat, 1000, false) returning id into v_cp;
    insert into public.fleets (player_id, name, status, port_id) values (v_cp, 'Prova 0471', 'DOCKED', v_home) returning id into v_cf;
    insert into public.battles (kind, site, started_at, resolves_at, status) values ('RAID', '{}'::jsonb, v_now, v_now + interval '10 minutes', 'FIGHTING') returning id into v_b;
    insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values
      (v_b, v_pf, 'ATTACKER', v_now, v_now, 'OPENED'), (v_b, v_cf, 'DEFENDER', v_now, v_now, 'OPENED');   -- re-pointed below to whichever pirate the step names

    -- (d) DARK: nothing named, taken, claimed or served
    if public.bounty_step(v_now) is not null or public.bounty_close(v_b, '{"outcome":"DRIVEN_OFF"}'::jsonb, v_now) <> '{}'::jsonb
       or world.pirate_bounties() <> '{"on": false}'::jsonb or exists (select 1 from public.pirate_bounties) then
      raise exception '0471 self-assert FAIL: dark, the bounties wrote or served something';
    end if;

    -- (e) LIT, in the probe: the purses and the pirates lit, every harbour a purse
    update public.world_config set value = 'true'::jsonb where key in ('pirate_bounties_enabled', 'pirates_bite', 'city_treasury_enabled');
    insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;   -- a world whose purses were never seeded (production's all are: nothing is written there)
    update public.world_config set value = to_jsonb(1) where key = 'bounty_named';
    v_r := public.bounty_step(v_now);
    select * into v_row from public.pirate_bounties pb where pb.closed_at is null;
    if (v_r ->> 'named')::int is distinct from 1 or v_row.fleet_id is null or v_row.poster_port is null
       or public.pirate_power(public.port_nation(v_row.poster_port))
       or v_row.home_port is distinct from (select n.home_port from public.pirate_ships n where n.fleet_id = v_row.fleet_id) then
      raise exception '0471 self-assert FAIL: lit, the step did not name the probe pirate with a poster the pirates do not hold: %', v_r;
    end if;
    if public.city_surplus(v_row.poster_port) < 60000 then   -- only a world whose poster cannot pay (the local one): production's purses are not touched
      update public.port_treasury t set ducats = t.ducats + 5000000 where t.port_id = v_row.poster_port;
    end if;
    if (public.bounty_step(v_now) ->> 'named') is not null or (select count(*) from public.pirate_bounties) <> 1 then
      raise exception '0471 self-assert FAIL: lit, a second step named a second pirate into one slot';
    end if;
    -- the raid is hers (on a world with pirates at sea the step may name one of them rather than the probe's ship: the probe never lays a real one up)
    update public.battle_sides bs set fleet_id = v_row.fleet_id where bs.battle_id = v_b and bs.side = 'ATTACKER';
    -- her raid won: a ship on her record, no money
    v_r := public.bounty_close(v_b, '{"outcome":"PLUNDERED"}'::jsonb, v_now);   -- its own statement: a later statement sees what it wrote
    if v_r <> '{}'::jsonb
       or (select pb.taken from public.pirate_bounties pb where pb.id = v_row.id) <> 1
       or (select pb.took -> 0 ->> 'ship' from public.pirate_bounties pb where pb.id = v_row.id) <> 'Prova 0471' then
      raise exception '0471 self-assert FAIL: lit, a raid she won is not on her record';
    end if;
    -- the company beats her: the bounty, base + one ship, from the poster's purse to the company, once
    select pl.ducats into v_purse from public.players pl where pl.id = v_cp;
    v_r := public.bounty_close(v_b, '{"outcome":"DRIVEN_OFF"}'::jsonb, v_now);
    if (v_r #>> '{bounty,paid}')::bigint is distinct from 17000 or (select pl.ducats from public.players pl where pl.id = v_cp) <> v_purse + 17000
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_row.poster_port and tf.kind = 'PIRATE_BOUNTY' and tf.ducats = -17000 and tf.player_id = v_cp)   -- the poster's own flow (a live harbour's balance moves with its trades)
       or not exists (select 1 from public.ledger l where l.player_id = v_cp and l.kind = 'PIRATE_BOUNTY' and l.ducats_delta = 17000)
       or (select pb.closed from public.pirate_bounties pb where pb.id = v_row.id) is distinct from 'CLAIMED' then
      raise exception '0471 self-assert FAIL: lit, the company''s win did not pay 17,000 from the poster to the company: %', v_r;
    end if;
    v_r := public.bounty_close(v_b, '{"outcome":"DRIVEN_OFF"}'::jsonb, v_now);
    if v_r <> '{}'::jsonb
       or (select pl.ducats from public.players pl where pl.id = v_cp) <> v_purse + 17000 then
      raise exception '0471 self-assert FAIL: lit, a bounty paid twice';
    end if;
    -- the slot waits for the respawn; a lit read serves the claim
    if (public.bounty_step(v_now + interval '5 hours') ->> 'named') is not null then
      raise exception '0471 self-assert FAIL: lit, the slot was named again before bounty_respawn_hours';
    end if;
    v_r := world.pirate_bounties();
    if (v_r ->> 'on')::boolean is not true or jsonb_array_length(v_r -> 'bounties') <> 0 or (v_r #>> '{claims,0,paid}')::bigint is distinct from 17000 then
      raise exception '0471 self-assert FAIL: lit, the read did not serve the claim: %', v_r;
    end if;
    raise exception sqlstate 'BV471';
  exception when sqlstate 'BV471' then null;
  end;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0471 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0471 self-assert ok: BOUNTIES ON NAMED PIRATES (dark). % hunks once each and reversing; grants and volatility unmoved; no other function moved; pirate_bounties_enabled false and seven knobs; PIRATE_BOUNTY moved; world.pirate_bounties registered for authenticated alone; probe: the size, the beaten rule on 14 shapes, dark nothing written or served, lit a pirate named with a poster, a raid on her record, a company paid 17,000 once from the poster''s purse (moved: the purse down by what the company gained), the slot held to the respawn%; % ms.',
    (select count(*) from hunks_0471), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0471;
end $m$;

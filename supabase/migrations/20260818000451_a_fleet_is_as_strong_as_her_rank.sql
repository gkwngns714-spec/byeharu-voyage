-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0451 - A FLEET IS AS STRONG AS HER RANK  (the NPC ladder: pirate, navy and cargo fleets differ in class, size and number of hulls by a rule
--        that is data; the fleets that sail are re-rated in harbour, a few a minute)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-16: "every pirate ship's graphic is same. the one with stronger ships, multiple fleets should have different graphics. this
--   goes to every kinds of ship too". The pictures are #748 (client: a fleet is drawn from her served `hulls`, by the size of each class:
--   1 sloop, 2 brig, 3-4 frigate, 5-6 flagship, and her count). This file is the server half: the fleets themselves differ.
--
-- WHAT WAS THERE (prod 2026-11-15 17:26 UTC, head 0448, scripts/ops/harness/npc-ladder/dist.sql; docs/dev-log/2026-11-16-npc-ladder.md):
--   NAVY   48 fleets, every one ONE `galion` (size 4), whatever her country or her station (public.navy_commission: knob navy_ship_class).
--   CARGO  112 in service (265 retired), every one ONE `navire` (size 3) (public.cargo_class: knob convoy_armed_class).
--   PIRATE 121 fleets, 193 hulls. 0414's roster already differs (36 brigantin, 18 fusta, 18 xebec, 18 pairs of xebec, 14 galeoncete + 3 xebec,
--          4 korsan + 3 xebec), but nothing is a flagship (no hull above size 3), and 0339's 13 ships are every one ONE `xebec`
--          (public.pirate_commission: knob pirate_ship_class). Those 13 fight 29 of the last 100 raids.
--   Every hull is level 5 (0372). The pay is by the FLEET (navy_upkeep_day / 24 an hour, public.navy_pay / public.pirate_pay_hour), not by the hull.
--
-- WHAT THIS FILE DOES
--   S1. THE LADDER, AS DATA. public.npc_ladder: a kind's rungs (name EN / KO). public.npc_ladder_hulls: the hulls of a rung for a ship line
--       (public.ship_lines; '*' = any country), n ships of a class. Only classes that exist; no new class, no new art. A country's navy and
--       cargo ships are its OWN line's hulls (the cheapest hull of the line at the rung's size and role that is not a famous ship, tech 'F';
--       where the line has none, the '*' hull), resolved here once and written as rows the owner can read and change.
--         PIRATE  1 Raider    1 brigantin (sloop)            NAVY  1 Cutters           2 hulls of size 1
--                 2 Corsair   1 xebec (brig)                       2 Brigs             2 hulls of size 2
--                 3 Consorts  2 xebec                              3 Frigate           1 hull of size 4 (the galion, or her country's)
--                 4 Squadron  galeoncete + 3 xebec (frigate)       4 Ship of the line  1 hull of size 5-6 + 1 frigate (flagship)
--                 5 Dread     kalyon + 3 xebec (flagship)    CARGO 1 Small  1 trader of size 2;  2 Medium  size 3 (the navire, or her
--                                                                  country's);  3 Large  size 5-6 (an Indiaman)
--   S2. THE RULE (public.npc_rung_rule, pure; public.npc_rung_of reads a fleet's facts into it). Strength follows something that means
--       something in the world, and nothing that moves by the minute:
--         NAVY    by her STATION: ord 1 serves rank 1, the capital (public.navy_station_of). Of a navy of S ships: the capital's is the
--                 Ship of the line when S >= 4 (a small navy keeps a Frigate there); then by quarters of the navy: the first half Frigates,
--                 the third quarter Brigs, the last Cutters (S = 6: Line, Frigate, Frigate, Brigs, Brigs, Cutters). A rich country keeps more
--                 ships (public.navy_size_for), so it alone has a Ship of the line.
--         CARGO   by her country's SHARE of the hundred (public.convoy_ships_of: its harbours) and her seniority (ord): the first quarter
--                 Large, to 65 % Medium, the rest Small (a share of 16: 4 / 7 / 5).
--         PIRATE  a roster fleet is what her roster row says (public.pirate_roster_hulls, 0414's authority, unmoved but for S3); 0339's ships
--                 by ord, a pattern of six: Corsair, Raider, Corsair, Raider, Consorts, Corsair.
--   S3. THE DREAD PIRATES: eight of the eighteen roster squadrons (the first of every three in each hub: ord % 1000 % 18 = 6) are led by a
--       `kalyon` (size 5, 39 guns) in place of the galeoncete / korsan: 8 of 121 fleets, 6.6 %. Rows of public.pirate_roster_hulls; each hub's
--       ship count (public.pirate_hubs.ships, the owner's order) is unmoved.
--   S4. ONE WAY A FLEET IS RE-RATED (public.npc_ladder_refit): in a harbour (DOCKED, or a pirate wreck being reborn), never at sea, never on a
--       side of a battle being fought, never busy, never with goods in a hold, never a navy ship called to a fight or escorting. Her hulls
--       are replaced by her rung's (public.commission_ship, the one place a hull is made), the lead ship under the fleet's name and the others
--       numbered as 0414 names them; her hands go over to the new hulls by their complement (the rest back on the quay she lies at); her
--       hulls keep the share of health she had (a wreck stays a wreck: public.pirate_reborn mends her after, paid as before); her level is
--       written at once (public.crown_hull_level_fix). NO GOLD MOVES (0328's law for a cargo ship's refit, public.cargo_hull: "Free, as a
--       cargo ship's hull always was"), decided by default: a re-rating is the crown's or the Brethren's own order, not a purchase; a NEW
--       hull is still paid for by the door that lays it (public.navy_commission, public.pirate_commission, public.pirate_commission_fleet,
--       unmoved) and is re-rated at her first minute in harbour.
--   S5. WHO CALLS IT, AND THE PACE. At most npc_ladder_per_minute (2) re-ratings of a kind a minute (public.npc_ladder_take, one row a kind).
--         * public.npc_ladder_pass, from public.tick_pirates (the minute job that is there; 1 hunk): the navy and pirate fleets lying DOCKED
--           whose hulls are not their rung's, at most npc_ladder_looks_per_run (40) looked at a run. It never raises.
--         * public.pirate_reborn (1 hunk): a wreck is reborn as her rung (before the mend; the refit she pays is her old hulls').
--         * public.cargo_hull (1 hunk): lit, and the cargo ships armed (convoy_armed_enabled, 0328's switch: every ladder hull has guns), the
--           cargo ship's own refit moment (idle at home, no load; public.cargo_ship_step, unmoved) is the ladder's. Dark, or unarmed, it is
--           0328's body, so the switch off turns every cargo ship back to public.cargo_class() as she idles.
--       public.npc_fleet_rungs: one row a fleet, the rung and hulls she was last rated to (the pass skips her while it stands).
--   KNOBS (new): npc_ladder_enabled true (the switch; false is the quick stop), npc_ladder_per_minute 2, npc_ladder_looks_per_run 40.
--
-- THE BALANCE (docs/dev-log/2026-11-16-npc-ladder.md has the tables). By the raider figure (voyage.pirate_strength's: attack / 10 + hands x 0.02
--   + tier x 3 a hull): NAVY 1,901 -> 1,894 (-0.4 %: ten navies of 2 to 6 ships, 48 fleets, 48 -> 79 hulls); PIRATE 2,345 -> 2,585 (+10 %, all
--   of it the eight Dread fleets, who lost no raid and were never wrecked as squadrons; 0339's 13 ships 165 -> 161); CARGO 2,320 -> 2,149
--   (-7 %; no cargo ship was the target of any of the last 100 raids: raids take the merchants first). The 100 newest frozen raids re-fought
--   with the new hulls (scripts/ops/harness/npc-ladder/replay.mjs): the pirates won 33 with the old hulls and 32 with the new; 9 outcomes moved.
--   PAY: unmoved, it is by the fleet. A WRECK'S REFIT (npc_refit_share 25 % of her hulls' build cost) follows her class: a Raider 20,000
--   (a xebec 40,000), a Dread 595,000 (a squadron 354,000), a Ship of the line with her frigate 750,000 to 1,260,000 (a galion 289,000),
--   Cutters 40,000; a navy's mean 289,000 -> 286,000, a cargo ship's 157,500 -> 191,000. A Dread's house, when broke, is given half her
--   hulls' cost by the hoard (public.pirate_house_capital, 0415): 1,190,000, was 708,000. The hoard (895 M, floor 100 M) pays a pirate's
--   hour and a wreck's refit whatever the day's room says (0429): no pirate is laid up by this.
-- budget: no job, no cron. Rows: a re-rating writes about 20 rows (her old hulls and their level rows out, the new in, her fleet, her rung
--   row, the kind's clock row, at most one quay), at most 2 a kind a minute: under 120 rows a minute while the world is re-rated (about
--   155 fleets: one to three hours, as they come into harbour), then only a new, woken or reborn fleet. In the first quarter of an hour the
--   pass also writes the rung row of each fleet that is already her rung (most pirates), once a fleet, at most npc_ladder_looks_per_run (40)
--   rows a minute: under 160 rows a minute then. The pass reads the docked navy and pirate fleets a minute (about 30 rows by key) and
--   writes nothing when none is due.
-- LOCKS: CREATE TABLE x4, CREATE FUNCTION x10, CREATE OR REPLACE x3 (3 hunks), 8 rows of public.pirate_roster_hulls. The pass takes a
--   fleet's row only if it is free (FOR UPDATE SKIP LOCKED). TIME: under 2 s. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/npc-ladder/rollback-0451.sql (a draft). The quick stop is the switch.
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the re-cut functions unmoved; no other
--   function moved; the new functions server-only; the ladder's rows whole (every rung of every kind has its '*' hulls, every hull a class
--   with guns, no famous ship); the rule's table; eight Dread fleets and every hub's ship count unmoved. THE PROBE, rolled back, on ANY world
--   (its own fleets at ords no world uses; the CI world has no pirate, navy or cargo ship): a pirate re-rated to Consorts (two hulls, one
--   flagship, her hands and the quay's conserved, her rung row), refused while busy, the pace (a second refused that minute, taken the next,
--   her hull's health share kept), a navy ship to Cutters of her country's line, a cargo ship through public.cargo_hull lit and dark;
--   no gold moves.
-- VERSION: 0451 = prod head 0450 + 1 (0449 is unused). Each hunk occurs once in prod's live bodies (dist.sql, 17:56 UTC, head 0450); 0445
--   moved other lines of public.tick_pirates, and 0448 and 0450 touch none of the three.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_meta      text;
  v_h         record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_bad       text;
  v_hubs      text;
  v_note      text;
  v_pir       uuid;
  v_port      uuid;
  v_nat       uuid;
  v_cap       uuid;
  v_pl        uuid;
  v_fl        uuid;
  v_fl2       uuid;
  v_fl3       uuid;
  v_fl4       uuid;
  v_ok        boolean;
  v_w         numeric;
  v_hands     bigint;
  v_want      text;
  v_have      text;
  v_knob      jsonb;
  c_hunked    constant text[] := array['public.tick_pirates(timestamp with time zone)', 'public.pirate_reborn(uuid,timestamp with time zone)', 'public.cargo_hull(uuid)'];
  c_new       constant text[] := array['public.npc_ladder_on()', 'public.npc_ladder_kind(uuid)', 'public.npc_ladder_line(uuid)', 'public.npc_rung_rule(text,integer,integer)',
                                       'public.npc_rung_of(uuid)', 'public.npc_hulls_wanted(uuid)', 'public.npc_hulls_sig(uuid)', 'public.npc_ladder_take(text,timestamp with time zone)',
                                       'public.npc_ladder_refit(uuid,timestamp with time zone)', 'public.npc_ladder_pass(timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_hunked || array['public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)', 'public.crown_hull_level_fix(uuid)', 'public.fleet_kind(uuid)',
                                                    'public.navy_size_of(uuid)', 'public.convoy_ships_of(uuid)', 'public.ship_base(uuid)', 'public.news_update(text,text,text)',
                                                    'public.fleet_book_refit(uuid,bigint,timestamp with time zone)']) f where to_regprocedure(f) is null)
     or to_regclass('public.pirate_roster_hulls') is null or to_regclass('public.class_profile') is null or to_regclass('public.ship_lines') is null then
    raise exception '0451 refuses: the pirates'' roster (0414), the fleet book (0431), the navy (0331), the cargo ships (0328, 0430) or the ship lines (0130) are not all in this world';
  end if;
  if to_regprocedure('public.npc_ladder_on()') is not null or to_regclass('public.npc_ladder') is not null then
    raise exception '0451 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  select string_agg(hb.port_id::text || ':' || coalesce((select sum(x.n) from public.pirate_roster r join public.pirate_roster_hulls x on x.ord = r.ord where r.hub_port = hb.port_id), 0), ',' order by hb.port_id)
    into v_hubs from public.pirate_hubs hb;

  -- ── 2. THE TABLES AND THE KNOBS ──
  -- retention: none, bounded by construction: one row a rung of a kind (twelve rows)
  create table public.npc_ladder (
    kind    text not null check (kind in ('PIRATE', 'NAVY', 'CARGO')),
    rung    integer not null check (rung between 1 and 9),
    code    text not null,
    name    text not null,
    name_ko text not null,
    primary key (kind, rung),
    unique (kind, code)
  );
  comment on table public.npc_ladder is '0451: THE RANKS OF THE WORLD''S OWN FLEETS: one row a rung of a kind (PIRATE, NAVY, CARGO), 1 the weakest. Which rung a fleet is: public.npc_rung_of. What hulls a rung is: public.npc_ladder_hulls. Server-only.';
  alter table public.npc_ladder enable row level security;
  revoke all on table public.npc_ladder from public, anon, authenticated;

  -- retention: none, bounded by construction: the hulls of a rung for a ship line (about 130 rows: 12 rungs x 12 lines at most, one or two classes each)
  create table public.npc_ladder_hulls (
    kind  text not null,
    rung  integer not null,
    line  text not null,
    class text not null references public.ship_classes(code),
    n     integer not null check (n between 1 and 9),
    primary key (kind, rung, line, class),
    foreign key (kind, rung) references public.npc_ladder(kind, rung)
  );
  comment on table public.npc_ladder_hulls is '0451: the hulls of a rung: n ships of a class, for a ship line (public.ship_lines.code; ''*'' = a country with no line of its own, and the pirates). The dearest class is the lead ship. Read by public.npc_hulls_wanted (a pirate ROSTER fleet reads public.pirate_roster_hulls instead). Change a row and the fleets of that rung are re-rated in harbour, a few a minute. Server-only.';
  alter table public.npc_ladder_hulls enable row level security;
  revoke all on table public.npc_ladder_hulls from public, anon, authenticated;

  -- retention: none, bounded by construction: one row a pirate, navy or cargo fleet (a fleet's row is never deleted; about 550 rows)
  create table public.npc_fleet_rungs (
    fleet_id uuid primary key,
    kind     text not null,
    rung     integer not null,
    hulls    text not null,
    rated_at timestamptz not null
  );
  comment on table public.npc_fleet_rungs is '0451: the rung and the hulls each pirate, navy or cargo fleet was last rated to (public.npc_ladder_refit, its one writer). `hulls` is public.npc_hulls_sig''s text; while it is what the rule wants, public.npc_ladder_pass skips her. No foreign key on purpose (0431''s reason: a key share lock on fleets would wait behind the beat). Server-only.';
  alter table public.npc_fleet_rungs enable row level security;
  revoke all on table public.npc_fleet_rungs from public, anon, authenticated;

  -- retention: none, bounded by construction: three rows, one a kind
  create table public.npc_ladder_clock (
    kind   text primary key check (kind in ('PIRATE', 'NAVY', 'CARGO')),
    minute timestamptz,
    done   integer not null default 0
  );
  comment on table public.npc_ladder_clock is '0451: the pace of the re-rating: how many fleets of a kind were re-rated in the minute `minute` (public.npc_ladder_take, its one writer; at most npc_ladder_per_minute). One row a kind, so the cargo job and the pirates'' job never wait on each other. Server-only.';
  alter table public.npc_ladder_clock enable row level security;
  revoke all on table public.npc_ladder_clock from public, anon, authenticated;
  insert into public.npc_ladder_clock (kind) values ('PIRATE'), ('NAVY'), ('CARGO');

  insert into public.world_config (key, value, description) values
    ('npc_ladder_enabled', 'true'::jsonb, '0451: THE switch of the NPC ladder. True: pirate, navy and cargo fleets are re-rated in harbour to the hulls of their rung (public.npc_ladder_refit). False: nobody is re-rated, a fleet stays as she is, and a cargo ship''s refit is 0328''s again (public.cargo_class).'),
    ('npc_ladder_per_minute', to_jsonb(2), '0451: at most this many fleets of ONE kind (pirate, navy, cargo) are re-rated in a minute (public.npc_ladder_take). A re-rating writes about 20 rows.'),
    ('npc_ladder_looks_per_run', to_jsonb(40), '0451: at most this many docked navy and pirate fleets are looked at by one run of public.npc_ladder_pass (turned by the minute, so none starves).');

  -- ── 3. THE LADDER'S ROWS ──
  insert into public.npc_ladder (kind, rung, code, name, name_ko) values
    ('PIRATE', 1, 'RAIDER', 'Raider', '약탈선'),
    ('PIRATE', 2, 'CORSAIR', 'Corsair', '해적선'),
    ('PIRATE', 3, 'CONSORTS', 'Consorts', '해적 편대'),
    ('PIRATE', 4, 'SQUADRON', 'Squadron', '해적 전대'),
    ('PIRATE', 5, 'DREAD', 'Dread', '공포의 함대'),
    ('NAVY', 1, 'CUTTERS', 'Cutters', '경비정'),
    ('NAVY', 2, 'BRIGS', 'Brigs', '브리그'),
    ('NAVY', 3, 'FRIGATE', 'Frigate', '프리깃'),
    ('NAVY', 4, 'LINE', 'Ship of the line', '전열함'),
    ('CARGO', 1, 'SMALL', 'Small', '소형'),
    ('CARGO', 2, 'MEDIUM', 'Medium', '중형'),
    ('CARGO', 3, 'LARGE', 'Large', '대형');
  -- the pirates: 0414's classes, and the kalyon
  insert into public.npc_ladder_hulls (kind, rung, line, class, n) values
    ('PIRATE', 1, '*', 'brigantin', 1),
    ('PIRATE', 2, '*', 'xebec', 1),
    ('PIRATE', 3, '*', 'xebec', 2),
    ('PIRATE', 4, '*', 'galeoncete', 1), ('PIRATE', 4, '*', 'xebec', 3),
    ('PIRATE', 5, '*', 'kalyon', 1), ('PIRATE', 5, '*', 'xebec', 3);
  -- the navy and the cargo ships: each part of a rung is a role and a size; a line's hull is its cheapest of that role and size that has guns and is
  -- no famous ship (tech 'F', 0165: one to a house), else the '*' hull, which is also the row of a country with no line
  create temp table parts_0451 (kind text, rung int, part int, roles text[], lo int, hi int, n int, fallback text) on commit drop;
  insert into parts_0451 values
    ('NAVY', 1, 1, array['combat'], 1, 1, 2, 'brigantin'),
    ('NAVY', 2, 1, array['combat'], 2, 2, 2, 'fregcourse'),
    ('NAVY', 3, 1, array['combat'], 4, 4, 1, 'galion'),
    ('NAVY', 4, 1, array['combat'], 5, 6, 1, 'grandnav'),
    ('NAVY', 4, 2, array['combat'], 4, 4, 1, 'galion'),
    ('CARGO', 1, 1, array['trade', 'explorer', 'support'], 2, 2, 1, 'caravelao'),
    ('CARGO', 2, 1, array['trade'], 3, 3, 1, 'navire'),
    ('CARGO', 3, 1, array['trade'], 5, 6, 1, 'indiaman');
  insert into public.npc_ladder_hulls (kind, rung, line, class, n)
  select z.kind, z.rung, z.line, z.class, sum(z.n)
    from (select p.kind, p.rung, l.code as line, p.n,
                 coalesce((select c.code from public.class_profile cp join public.ship_classes c on c.code = cp.class_code
                            where cp.line_code = l.code and cp.role = any (p.roles) and cp.size between p.lo and p.hi and cp.tech <> 'F' and c.guns > 0
                            order by array_position(p.roles, cp.role), cp.size, c.build_cost, c.code limit 1), p.fallback) as class
            from parts_0451 p cross join public.ship_lines l
          union all
          select p.kind, p.rung, '*', p.n, p.fallback from parts_0451 p) z
   group by z.kind, z.rung, z.line, z.class;
  drop table parts_0451;

  -- S3. THE DREAD PIRATES: the first of every three squadrons of a hub is led by a kalyon
  update public.pirate_roster_hulls h set class = 'kalyon'
   where h.class in ('galeoncete', 'korsan') and h.ord % 1000 % 18 = 6
     and exists (select 1 from public.pirate_roster_hulls x where x.ord = h.ord and x.class = 'xebec' and x.n = 3);
  get diagnostics v_n = row_count;
  if v_n <> 8 then
    raise exception '0451 refuses: % roster squadron(s) would be made Dread, not the 8 this file was written for (public.pirate_roster_hulls is not 0414''s)', v_n;
  end if;

  -- ── 4. THE NEW FUNCTIONS ──
  execute $f$
create function public.npc_ladder_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0451: THE switch of the NPC ladder (npc_ladder_enabled).
  select coalesce(public.wc('npc_ladder_enabled') = 'true'::jsonb, false)
$body$
  $f$;

  execute $f$
create function public.npc_ladder_kind(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0451: the ladder a fleet climbs: PIRATE, NAVY or CARGO, by public.fleet_kind (the one answer to what a fleet is). Null: a merchant, a company, no fleet.
  select case public.fleet_kind(p_fleet) when 'PIRATE' then 'PIRATE' when 'NAVY' then 'NAVY' when 'CARGO_SHIP' then 'CARGO' end
$body$
  $f$;

  execute $f$
create function public.npc_ladder_line(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0451: the ship line a navy or cargo fleet's hulls are of: her country's (public.ship_lines.builder_nations). The Mughal crown, which no line
  -- names, builds the Indian Ocean's hulls (its yards are Gujarat's; decided by default). The pirates and a country with no line: '*'.
  select coalesce((select sl.code
                     from (select coalesce((select n.nation_id from public.navy_ships n where n.fleet_id = p_fleet),
                                           (select c.nation_id from public.cargo_ships c where c.fleet_id = p_fleet)) as nation_id) q
                     join public.nations na on na.id = q.nation_id
                     join public.ship_lines sl on na.code = any (sl.builder_nations) or (na.code = 'MUG' and sl.code = 'IND')
                    order by (na.code = any (sl.builder_nations)) desc, sl.code limit 1), '*')
$body$
  $f$;

  execute $f$
create function public.npc_rung_rule(p_kind text, p_ord integer, p_size integer)
returns integer
language sql
immutable
as $body$
  -- 0451: THE RULE, pure: the rung of the fleet of this ord in a body of p_size (a navy's ships, public.navy_size_of; a country's cargo share,
  -- public.convoy_ships_of; nothing for a pirate). Change a rank's share HERE and nowhere else; what a rung IS is public.npc_ladder_hulls.
  --   NAVY   ord 1 serves the capital (public.navy_station_of: ord n, rank n): the Ship of the line (4) in a navy of four or more, a Frigate (3)
  --          in a smaller one. Then by quarters of the navy: the first half Frigates (3), the third quarter Brigs (2), the last Cutters (1).
  --   CARGO  the first quarter of her country's share Large (3), to 65 % Medium (2), the rest Small (1): her seniority.
  --   PIRATE one of 0339's ships (a roster fleet is her roster row: public.npc_rung_of): a pattern of six by ord:
  --          Corsair, Raider, Corsair, Raider, Consorts, Corsair.
  select case p_kind
    when 'NAVY' then case when p_ord = 1 and greatest(coalesce(p_size, 0), 1) >= 4 then 4
                          when ((p_ord - 1) * 4) / greatest(coalesce(p_size, 0), 1) <= 1 then 3
                          when ((p_ord - 1) * 4) / greatest(coalesce(p_size, 0), 1) = 2 then 2
                          else 1 end
    when 'CARGO' then case when p_ord <= ceil(greatest(coalesce(p_size, 0), 1) * 0.25) then 3
                           when p_ord <= ceil(greatest(coalesce(p_size, 0), 1) * 0.65) then 2
                           else 1 end
    when 'PIRATE' then (array[2, 1, 2, 1, 3, 2])[1 + (greatest(p_ord, 1) - 1) % 6]
  end
$body$
  $f$;

  execute $f$
create function public.npc_rung_of(p_fleet uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0451: THE one answer to which rung of her kind's ladder (public.npc_ladder) a pirate, navy or cargo fleet is. A pirate ROSTER fleet is what her
  -- roster row says (public.pirate_roster_hulls, 0414): a lead of size 5 or more Dread (5), three hulls or more a Squadron (4), two Consorts (3),
  -- one of size 2 a Corsair (2), else a Raider (1). Every other fleet: public.npc_rung_rule on her ord and her body's size. Null: no such fleet.
  select coalesce(
    (select case when max(cp.size) >= 5 then 5 when sum(h.n) >= 3 then 4 when sum(h.n) = 2 then 3 when max(cp.size) >= 2 then 2 else 1 end
       from public.pirate_ships pn join public.pirate_roster_hulls h on h.ord = pn.ord join public.class_profile cp on cp.class_code = h.class
      where pn.fleet_id = p_fleet having count(*) > 0),
    (select public.npc_rung_rule('PIRATE', pn.ord, null) from public.pirate_ships pn where pn.fleet_id = p_fleet),
    (select public.npc_rung_rule('NAVY', n.ord, public.navy_size_of(n.nation_id)) from public.navy_ships n where n.fleet_id = p_fleet),
    (select public.npc_rung_rule('CARGO', c.ord, public.convoy_ships_of(c.nation_id)) from public.cargo_ships c where c.fleet_id = p_fleet))
$body$
  $f$;

  execute $f$
create function public.npc_hulls_wanted(p_fleet uuid)
returns table (class text, n integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0451: THE one answer to which hulls a pirate, navy or cargo fleet should have. A pirate ROSTER fleet: her roster rows (public.pirate_roster_hulls,
  -- 0414's authority). Every other: the hulls of her rung (public.npc_rung_of) for her country's line (public.npc_ladder_line), or the '*' rows
  -- where the line has none. The dearest class is her lead ship. No row: not such a fleet.
  with r as (select h.class, h.n from public.pirate_ships pn join public.pirate_roster_hulls h on h.ord = pn.ord where pn.fleet_id = p_fleet),
       k as (select public.npc_ladder_kind(p_fleet) as kind, public.npc_rung_of(p_fleet) as rung, public.npc_ladder_line(p_fleet) as line)
  select r.class, r.n from r
  union all
  select l.class, l.n
    from k join public.npc_ladder_hulls l
      on l.kind = k.kind and l.rung = k.rung
     and l.line = case when exists (select 1 from public.npc_ladder_hulls x where x.kind = k.kind and x.rung = k.rung and x.line = k.line) then k.line else '*' end
   where not exists (select 1 from r)
$body$
  $f$;

  execute $f$
create function public.npc_hulls_sig(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0451: public.npc_hulls_wanted as one text ('kalyon*1+xebec*3'), the form public.npc_fleet_rungs.hulls keeps and a fleet's own hulls are compared in.
  select string_agg(w.class || '*' || w.n, '+' order by w.class) from public.npc_hulls_wanted(p_fleet) w
$body$
  $f$;

  execute $f$
create function public.npc_ladder_take(p_kind text, p_now timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0451: THE PACE: one re-rating of this kind taken from this minute's room (npc_ladder_per_minute a kind a minute), or false. One row a kind.
declare
  v_max int := coalesce(public.wc_int('npc_ladder_per_minute'), 0);
  v_min timestamptz := date_trunc('minute', p_now);
begin
  if v_max <= 0 then
    return false;
  end if;
  update public.npc_ladder_clock c
     set done = case when c.minute is not distinct from v_min then c.done + 1 else 1 end, minute = v_min
   where c.kind = p_kind and (c.minute is distinct from v_min or c.done < v_max);
  return found;
end
$body$
  $f$;

  execute $f$
create function public.npc_ladder_refit(p_fleet uuid, p_now timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0451: THE ONE WAY A PIRATE, NAVY OR CARGO FLEET IS RE-RATED to the hulls of her rung (public.npc_hulls_wanted). Only in a harbour (DOCKED, or a
-- wreck lying: public.pirate_reborn calls it before the mend), never busy, never on a side of a battle being fought, never a navy ship called to a
-- fight or escorting, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). Her old hulls go and
-- public.commission_ship, the one place a hull is put into `ships`, lays the new: the lead ship (the dearest class) under the old flagship's name,
-- the others numbered as 0414 numbers them. Her hands go over to the new hulls in proportion to their complement, the rest back on the quay she
-- lies at (none is made: a bigger fleet sails short until a quay mans her, public.fleet_hands at every departure). Her hulls keep the share of
-- health she had, so a wreck stays a wreck and a re-rating mends nothing. Her level is written at once (public.crown_hull_level_fix).
-- NO GOLD MOVES (0328's law of a cargo ship's refit). Answers whether she was re-rated; a fleet already her rung's has her row in
-- public.npc_fleet_rungs brought up to date and answers false. Callers: public.npc_ladder_pass, public.pirate_reborn, public.cargo_hull.
declare
  f       public.fleets%rowtype;
  v_kind  text := public.npc_ladder_kind(p_fleet);
  v_rung  int;
  v_want  text;
  v_have  text;
  v_name  text;
  v_crew  int;
  v_need  int;
  v_share numeric;
  v_ship  uuid;
  v_give  int;
  v_left  int;
  v_k     int := 0;
  v_old   uuid[];
  x       record;
begin
  if v_kind is null or not public.npc_ladder_on() then
    return false;
  end if;
  select * into f from public.fleets z where z.id = p_fleet for update;
  if f.id is null or f.port_id is null or f.status not in ('DOCKED', 'UNABLE_TO_SAIL') or (f.busy_until is not null and f.busy_until > p_now)
     or exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id where bs.fleet_id = p_fleet and b.status = 'FIGHTING')
     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null or n.escort_of is not null)) then
    return false;
  end if;
  v_want := public.npc_hulls_sig(p_fleet);
  select string_agg(h.code || '*' || h.n, '+' order by h.code) into v_have
    from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = p_fleet group by k.code) h;
  if v_want is null or v_have is null then
    return false;
  end if;
  v_rung := public.npc_rung_of(p_fleet);
  if v_want = v_have then
    insert into public.npc_fleet_rungs as g (fleet_id, kind, rung, hulls, rated_at) values (p_fleet, v_kind, v_rung, v_want, p_now)
    on conflict (fleet_id) do update set kind = excluded.kind, rung = excluded.rung, hulls = excluded.hulls, rated_at = excluded.rated_at
     where g.rung is distinct from excluded.rung or g.hulls is distinct from excluded.hulls;
    return false;
  end if;
  if exists (select 1 from public.ships s where s.fleet_id = p_fleet and coalesce(s.cargo, '{}'::jsonb) <> '{}'::jsonb) then
    return false;   -- goods in a hold: she is asked again when she has sold them (a wreck's hold is lost, so a reborn fleet is always taken)
  end if;
  if not public.npc_ladder_take(v_kind, p_now) then
    return false;
  end if;
  select array_agg(s.id), coalesce(sum(s.crew), 0)::int, least(1, coalesce(sum(s.durability) / nullif(sum((select b.durability from public.ship_base(s.id) b)), 0), 1)),
         coalesce(max(s.name) filter (where s.is_flagship), f.name)
    into v_old, v_crew, v_share, v_name
    from public.ships s where s.fleet_id = p_fleet;
  delete from public.ship_xp q where q.ship_id = any (v_old);
  delete from public.fitted_units q where q.ship_id = any (v_old);
  delete from public.ships s where s.id = any (v_old);
  select sum(w.n * c.crew_required)::int into v_need from public.npc_hulls_wanted(p_fleet) w join public.ship_classes c on c.code = w.class;
  v_left := v_crew;
  for x in select w.class, c.crew_required
             from public.npc_hulls_wanted(p_fleet) w join public.ship_classes c on c.code = w.class cross join lateral generate_series(1, w.n) g(i)
            order by c.build_cost desc, w.class, g.i loop
    v_k := v_k + 1;
    v_ship := public.commission_ship(f.player_id, p_fleet, x.class, case when v_k = 1 then v_name else format('%s %s', v_name, v_k) end, v_k = 1, false);
    v_give := least(v_left, x.crew_required, floor(v_crew::numeric * x.crew_required / greatest(v_need, 1))::int);
    update public.ships s set crew = v_give, durability = floor((select b.durability from public.ship_base(s.id) b) * v_share) where s.id = v_ship;
    v_left := v_left - v_give;
  end loop;
  if v_left > 0 then
    update public.ports p set crew_pool = p.crew_pool + v_left where p.id = f.port_id;
  end if;
  perform public.crown_hull_level_fix(f.player_id);
  update public.fleets set version = version + 1 where id = p_fleet;
  insert into public.npc_fleet_rungs as g (fleet_id, kind, rung, hulls, rated_at) values (p_fleet, v_kind, v_rung, v_want, p_now)
  on conflict (fleet_id) do update set kind = excluded.kind, rung = excluded.rung, hulls = excluded.hulls, rated_at = excluded.rated_at;
  return true;
end
$body$
  $f$;

  execute $f$
create function public.npc_ladder_pass(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0451: THE MINUTE'S RE-RATING of the navy and the pirates (a cargo ship's is her own refit moment, public.cargo_hull). Called by public.tick_pirates.
-- The fleets at work lying DOCKED whose rung row (public.npc_fleet_rungs) is not what the rule wants now, at most npc_ladder_looks_per_run looked
-- at, turned by the minute so none starves; a fleet whose row another job holds is passed over (SKIP LOCKED), never waited for. Each is
-- public.npc_ladder_refit's, in a block of her own. It never raises. Dark: {} and one knob read. Answers {rated: n} when any was re-rated.
declare
  r       record;
  v_n     int := 0;
  v_looks int := coalesce(public.wc_int('npc_ladder_looks_per_run'), 0);
  v_turn  bigint := floor(extract(epoch from p_now) / 60)::bigint;
begin
  if not public.npc_ladder_on() or v_looks <= 0 then
    return '{}'::jsonb;
  end if;
  for r in select x.fleet_id
             from (select n.fleet_id, n.ord from public.pirate_ships n where n.laid_up_at is null
                   union all
                   select n.fleet_id, n.ord from public.navy_ships n where n.laid_up_at is null) x
             join public.fleets f on f.id = x.fleet_id
            where f.status = 'DOCKED'
              and not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = x.fleet_id and g.hulls = public.npc_hulls_sig(x.fleet_id))
            order by (x.ord + v_turn) % 7, x.fleet_id
            limit v_looks
            for update of f skip locked loop
    begin
      if public.npc_ladder_refit(r.fleet_id, p_now) then
        v_n := v_n + 1;
      end if;
    exception when others then
      raise warning 'npc_ladder_pass: fleet % stayed as she is (SQLSTATE %: %)', r.fleet_id, sqlstate, sqlerrm;
    end;
  end loop;
  return case when v_n > 0 then jsonb_build_object('rated', v_n) else '{}'::jsonb end;
exception when others then
  raise warning 'npc_ladder_pass: nobody was re-rated (SQLSTATE %: %)', sqlstate, sqlerrm;
  return '{}'::jsonb;
end
$body$
  $f$;

  revoke all on function public.npc_ladder_on() from public, anon, authenticated;
  revoke all on function public.npc_ladder_kind(uuid) from public, anon, authenticated;
  revoke all on function public.npc_ladder_line(uuid) from public, anon, authenticated;
  revoke all on function public.npc_rung_rule(text, integer, integer) from public, anon, authenticated;
  revoke all on function public.npc_rung_of(uuid) from public, anon, authenticated;
  revoke all on function public.npc_hulls_wanted(uuid) from public, anon, authenticated;
  revoke all on function public.npc_hulls_sig(uuid) from public, anon, authenticated;
  revoke all on function public.npc_ladder_take(text, timestamptz) from public, anon, authenticated;
  revoke all on function public.npc_ladder_refit(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.npc_ladder_pass(timestamptz) from public, anon, authenticated;

  -- ── 5. THE HUNKS ──
  create temp table hunks_0451 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0451 values
  -- S5. the minute's re-rating of the navy and the pirates
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end
$h$,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end
         -- 0451: the navy and pirate fleets in harbour are re-rated to their rung, a few a minute (public.npc_ladder_pass, which never raises and has its own switch), never behind a trade's locks, as they are
         || case when current_setting('byeharu.pirate_traded', true) is distinct from 'on' then public.npc_ladder_pass(p_now) else '{}'::jsonb end
$h$),
  -- S5. a wreck is reborn as her rung
  ('public.pirate_reborn(uuid,timestamp with time zone)', 1,
$h$  perform public.fleet_mend(p_fleet);
  perform public.fleet_book_refit(p_fleet, $h$,
$h$  perform public.npc_ladder_refit(p_fleet, p_now);   -- 0451: she is reborn as her rung (public.npc_hulls_wanted): her hold is lost and every hull is at 0, so this is the moment; the refit paid above was her old hulls'
  perform public.fleet_mend(p_fleet);
  perform public.fleet_book_refit(p_fleet, $h$),
  -- S5. a cargo ship's refit moment is the ladder's
  ('public.cargo_hull(uuid)', 1,
$h$begin
  select x.* into s from public.ships x where x.fleet_id = p_fleet and x.is_flagship;
$h$,
$h$begin
  if public.npc_ladder_on() and public.cargo_armed_on() then
    return public.npc_ladder_refit(p_fleet, now());   -- 0451: lit (and the cargo ships armed, 0328's switch), her hull is her rung's (public.npc_hulls_wanted: Small, Medium or Large of her country's line), by the one re-rating; else 0328's body below
  end if;
  select x.* into s from public.ships x where x.fleet_id = p_fleet and x.is_flagship;
$h$);

  for v_h in select h.fn from hunks_0451 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0451 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0451 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0451 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0451 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0451 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new) x))) <> v_fn_before then
    raise exception '0451 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta then
    raise exception '0451 self-assert FAIL: the grants, volatility, definer, search path or owner of a re-cut function moved';
  end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_new) x))
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
          or (p.proname <> 'npc_rung_rule' and (not p.prosecdef or p.proconfig is null)));
  if v_bad is not null or (select count(*) from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_new) x))) <> cardinality(c_new) then
    raise exception '0451 self-assert FAIL: not server-only, definer and with its search path: %', v_bad;
  end if;

  -- ── 7. THE SELF-ASSERT: the ladder's rows, the rule, the roster ──
  select string_agg(l.kind || ' ' || l.rung, ', ') into v_bad
    from public.npc_ladder l where not exists (select 1 from public.npc_ladder_hulls h where h.kind = l.kind and h.rung = l.rung and h.line = '*');
  if v_bad is not null then
    raise exception '0451 self-assert FAIL: a rung with no hull for a country without a line: %', v_bad;
  end if;
  select string_agg(distinct h.class, ', ') into v_bad
    from public.npc_ladder_hulls h join public.ship_classes c on c.code = h.class left join public.class_profile cp on cp.class_code = h.class
   where c.guns <= 0 or c.crew_required <= 0 or cp.tech = 'F' or cp.class_code is null;
  if v_bad is not null then
    raise exception '0451 self-assert FAIL: a ladder hull with no guns, no hands, no profile, or a famous ship: %', v_bad;
  end if;
  -- a rung above is never a smaller lead ship, and every line's rows are whole (a line has every rung of the navy and the cargo ships)
  select string_agg(a.kind || ' ' || a.line || ' ' || a.rung, ', ') into v_bad
    from (select h.kind, h.line, h.rung, max(cp.size) as lead, sum(h.n) as hulls
            from public.npc_ladder_hulls h join public.class_profile cp on cp.class_code = h.class group by 1, 2, 3) a
    join (select h.kind, h.line, h.rung, max(cp.size) as lead, sum(h.n) as hulls
            from public.npc_ladder_hulls h join public.class_profile cp on cp.class_code = h.class group by 1, 2, 3) b
      on b.kind = a.kind and b.line = a.line and b.rung = a.rung + 1
   where b.lead < a.lead or (b.lead = a.lead and b.hulls <= a.hulls);
  if v_bad is not null then
    raise exception '0451 self-assert FAIL: a rung that is not above the one below it (lead ship''s size, then hulls): %', v_bad;
  end if;
  if (select count(*) from (select h.kind, h.line from public.npc_ladder_hulls h where h.kind <> 'PIRATE' group by 1, 2
                            having count(distinct h.rung) <> (select count(*) from public.npc_ladder l where l.kind = h.kind)) z) <> 0 then
    raise exception '0451 self-assert FAIL: a line without every rung';
  end if;
  if (select array_agg(public.npc_rung_rule('NAVY', o, 6) order by o) from generate_series(1, 6) o) <> array[4, 3, 3, 2, 2, 1]
     or (select array_agg(public.npc_rung_rule('NAVY', o, 5) order by o) from generate_series(1, 5) o) <> array[4, 3, 3, 2, 1]
     or (select array_agg(public.npc_rung_rule('NAVY', o, 4) order by o) from generate_series(1, 4) o) <> array[4, 3, 2, 1]
     or (select array_agg(public.npc_rung_rule('NAVY', o, 3) order by o) from generate_series(1, 3) o) <> array[3, 3, 2]
     or (select array_agg(public.npc_rung_rule('NAVY', o, 2) order by o) from generate_series(1, 2) o) <> array[3, 2]
     or public.npc_rung_rule('NAVY', 9, 6) <> 1 or public.npc_rung_rule('NAVY', 1, 0) <> 3 then
    raise exception '0451 self-assert FAIL: the navy''s rule is not the table of this file''s header';
  end if;
  if (select array_agg(public.npc_rung_rule('CARGO', o, 16) order by o) from generate_series(1, 16) o) <> array[3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1]
     or (select array_agg(public.npc_rung_rule('CARGO', o, 5) order by o) from generate_series(1, 5) o) <> array[3, 3, 2, 2, 1]
     or public.npc_rung_rule('CARGO', 1, 1) <> 3 or public.npc_rung_rule('CARGO', 40, 8) <> 1
     or (select array_agg(public.npc_rung_rule('PIRATE', o, null) order by o) from generate_series(1, 13) o) <> array[2, 1, 2, 1, 3, 2, 2, 1, 2, 1, 3, 2, 2] then
    raise exception '0451 self-assert FAIL: the cargo ships'' or the pirates'' rule is not the table of this file''s header';
  end if;
  if (select count(*) from (select h.ord from public.pirate_roster_hulls h group by h.ord
                            having bool_or(h.class = 'kalyon' and h.n = 1) and bool_or(h.class = 'xebec' and h.n = 3) and count(*) = 2) z) <> 8
     or (select string_agg(hb.port_id::text || ':' || coalesce((select sum(x.n) from public.pirate_roster r join public.pirate_roster_hulls x on x.ord = r.ord where r.hub_port = hb.port_id), 0), ',' order by hb.port_id)
           from public.pirate_hubs hb) is distinct from v_hubs then
    raise exception '0451 self-assert FAIL: not eight Dread fleets (kalyon + 3 xebec), or a hub''s ship count moved';
  end if;

  -- ── 8. THE NEWS (0347's law) ──
  perform public.news_update('0451', 'Pirate, navy and cargo fleets now differ: sloops to flagships, by rank', '해적·해군·화물선 함대가 달라진다: 등급에 따라 소형선부터 기함까지');

  -- ── 9. THE PROBE, rolled back by a raised sentinel. On any world: its own fleets, at ords no world uses (900 and up; 0339's are 1 to pirate_max,
  --   the roster's above 1000, a navy's and a cargo share's under 100). Knobs are written only by UPDATE and never read by a wc_* in a WHERE here.
  begin
    select w.value into v_knob from public.world_config w where w.key = 'npc_ladder_per_minute';
    v_pir := public.pirate_nation();
    select r.hub_port into v_port from public.pirate_roster r order by r.ord limit 1;
    select g.nation_id into v_nat from public.great_powers g join public.nations n on n.id = g.nation_id
     where not g.pirate and public.realm_capital(g.nation_id) is not null order by (n.code = 'ESP') desc, n.code limit 1;
    v_cap := public.realm_capital(v_nat);
    if v_pir is null or v_port is null or v_nat is null or v_cap is null then
      raise exception '0451 self-assert FAIL: no pirate nation, no hub or no crown with a capital in this world';
    end if;
    v_w := (select coalesce(sum(t.ducats), 0) from public.port_treasury t) + (select coalesce(sum(p.ducats), 0) from public.players p);

    -- (a) a pirate of 0339's kind, ord 905 (the rule: Consorts, two xebec), one xebec with 30 hands, docked
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0451 a', v_pir, 0, true) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Probe 0451 a', v_port);
    perform public.commission_ship(v_pl, v_fl, 'xebec', 'Probe 0451 a', true, false);
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port, created_at) values (v_fl, v_pl, 905, v_port, v_port, now());
    update public.ships s set crew = 30 where s.fleet_id = v_fl;
    v_hands := (select p.crew_pool from public.ports p where p.id = v_port) + 30;
    if public.npc_rung_of(v_fl) <> 3 or public.npc_hulls_sig(v_fl) <> 'xebec*2' or public.npc_ladder_kind(v_fl) <> 'PIRATE' or public.npc_ladder_line(v_fl) <> '*' then
      raise exception '0451 self-assert FAIL: the probe pirate (ord 905) is rung %, hulls %', public.npc_rung_of(v_fl), public.npc_hulls_sig(v_fl);
    end if;
    update public.fleets set busy_until = now() + interval '1 hour' where id = v_fl;
    v_ok := public.npc_ladder_refit(v_fl, now());
    if v_ok or (select count(*) from public.ships s where s.fleet_id = v_fl) <> 1 then
      raise exception '0451 self-assert FAIL: a busy fleet was re-rated';
    end if;
    update public.fleets set busy_until = null where id = v_fl;
    v_ok := public.npc_ladder_refit(v_fl, now());
    if not v_ok
       or (select count(*) from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl and k.code = 'xebec') <> 2
       or (select count(*) from public.ships s where s.fleet_id = v_fl) <> 2
       or (select count(*) from public.ships s where s.fleet_id = v_fl and s.is_flagship and s.name = 'Probe 0451 a') <> 1
       or (select count(*) from public.ships s where s.fleet_id = v_fl and not s.is_flagship and s.name = 'Probe 0451 a 2') <> 1
       or (select sum(s.crew) from public.ships s where s.fleet_id = v_fl) + (select p.crew_pool from public.ports p where p.id = v_port) <> v_hands
       or (select max(s.crew) from public.ships s where s.fleet_id = v_fl) > 35
       or not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = v_fl and g.kind = 'PIRATE' and g.rung = 3 and g.hulls = 'xebec*2') then
      raise exception '0451 self-assert FAIL: the probe pirate was not re-rated to two xebec, one flagship under her name, her hands conserved (answer %, % hulls, hands % of %)',
        v_ok, (select count(*) from public.ships s where s.fleet_id = v_fl),
        (select sum(s.crew) from public.ships s where s.fleet_id = v_fl) + (select p.crew_pool from public.ports p where p.id = v_port), v_hands;
    end if;
    if public.npc_ladder_refit(v_fl, now()) then
      raise exception '0451 self-assert FAIL: a fleet of her rung was re-rated again';
    end if;

    -- (b) THE PACE: one a minute here; a second pirate (ord 902: a Raider, one brigantin) is refused in this minute and taken in the next, at half health
    update public.world_config set value = to_jsonb(1) where key = 'npc_ladder_per_minute';
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0451 b', v_pir, 0, true) returning id into v_pl;
    v_fl2 := public.form_fleet(v_pl, 'Probe 0451 b', v_port);
    perform public.commission_ship(v_pl, v_fl2, 'xebec', 'Probe 0451 b', true, false);
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port, created_at) values (v_fl2, v_pl, 902, v_port, v_port, now());
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) / 2 where s.fleet_id = v_fl2;
    v_ok := public.npc_ladder_refit(v_fl2, now());
    if v_ok then
      raise exception '0451 self-assert FAIL: a second re-rating of a kind was taken in a minute that allows one';
    end if;
    v_ok := public.npc_ladder_refit(v_fl2, now() + interval '1 minute');
    if not v_ok or (select string_agg(k.code, '+') from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl2) <> 'brigantin'
       or (select s.durability / (select b.durability from public.ship_base(s.id) b) from public.ships s where s.fleet_id = v_fl2) not between 0.49 and 0.5 then
      raise exception '0451 self-assert FAIL: the next minute did not take her, or she is not one brigantin at half health (answer %)', v_ok;
    end if;
    update public.world_config set value = v_knob where key = 'npc_ladder_per_minute';

    -- (c) a navy ship of a crown, ord 900 (the rule: Cutters), a galion at her capital: two hulls of her country's line (or the '*' hulls)
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0451 c', v_nat, 0, true) returning id into v_pl;
    v_fl3 := public.form_fleet(v_pl, 'Probe 0451 c', v_cap);
    perform public.commission_ship(v_pl, v_fl3, public.wc_text('navy_ship_class'), 'Probe 0451 c', true, false);
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, created_at) values (v_fl3, v_pl, v_nat, 900, v_cap, v_cap, now());
    v_want := public.npc_hulls_sig(v_fl3);
    v_ok := public.npc_ladder_refit(v_fl3, now() + interval '2 minutes');
    select string_agg(h.code || '*' || h.n, '+' order by h.code) into v_have
      from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl3 group by k.code) h;
    if not v_ok or public.npc_rung_of(v_fl3) <> 1 or v_want is null or v_have is distinct from v_want
       or (select count(*) from public.ships s where s.fleet_id = v_fl3) <> 2
       or (select count(*) from public.ships s where s.fleet_id = v_fl3 and s.is_flagship) <> 1 then
      raise exception '0451 self-assert FAIL: the probe navy ship (ord 900) is not her country''s Cutters: answer %, wanted %, has %', v_ok, v_want, v_have;
    end if;

    -- (d) a cargo ship, ord 900 (the rule: Small), through her own refit (public.cargo_hull): lit, her country's small trader; dark, 0328's class again
    update public.world_config set value = 'true'::jsonb where key in ('convoys_enabled', 'convoy_armed_enabled');   -- armed, as prod is (the CI world has both dark)
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0451 d', v_nat, 0, true) returning id into v_pl;
    v_fl4 := public.form_fleet(v_pl, 'Probe 0451 d', v_cap);
    perform public.commission_ship(v_pl, v_fl4, public.cargo_class(), 'Probe 0451 d', true, false);
    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord) values (v_fl4, v_pl, v_nat, v_cap, 900);
    v_want := public.npc_hulls_sig(v_fl4);
    v_ok := public.cargo_hull(v_fl4);
    select string_agg(k.code || '*1', '+' order by k.code) into v_have from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl4;
    if not v_ok or public.npc_rung_of(v_fl4) <> 1 or v_have is distinct from v_want or v_want = public.cargo_class() || '*1'
       or (select count(*) from public.ships s where s.fleet_id = v_fl4 and s.is_flagship and s.name = 'Probe 0451 d') <> 1 then
      raise exception '0451 self-assert FAIL: lit, the probe cargo ship''s refit did not make her her country''s Small: answer %, wanted %, has %', v_ok, v_want, v_have;
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'npc_ladder_enabled';
    v_ok := public.cargo_hull(v_fl4);
    if not v_ok or (select k.code from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl4) <> public.cargo_class()
       or public.npc_ladder_refit(v_fl, now() + interval '5 minutes') or public.npc_ladder_pass(now() + interval '5 minutes') <> '{}'::jsonb then
      raise exception '0451 self-assert FAIL: dark, a cargo ship''s refit is not 0328''s, or somebody was re-rated';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'npc_ladder_enabled';

    if (select coalesce(sum(t.ducats), 0) from public.port_treasury t) + (select coalesce(sum(p.ducats), 0) from public.players p) <> v_w then
      raise exception '0451 self-assert FAIL: the probe moved gold';
    end if;
    v_note := 'a pirate (ord 905) xebec -> 2 xebec, hands conserved, refused while busy; the pace (1 a minute: refused, then taken: a brigantin at half health); a navy ship (ord 900) '
              || (select n.code from public.nations n where n.id = v_nat) || ' galion -> ' || public.npc_hulls_sig(v_fl3) || '; a cargo ship (ord 900) -> ' || v_want || ' lit and back to ' || public.cargo_class() || ' dark; no gold moved';
    raise exception sqlstate 'BV451' using message = v_note;
  exception when sqlstate 'BV451' then
    get stacked diagnostics v_note = message_text;
  end;
  if exists (select 1 from public.npc_fleet_rungs) or exists (select 1 from public.pirate_ships n where n.ord in (902, 905))
     or (select w.value from public.world_config w where w.key = 'npc_ladder_enabled') is distinct from 'true'::jsonb
     or exists (select 1 from public.npc_ladder_clock c where c.minute is not null) then
    raise exception '0451 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0451 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0451 self-assert ok: A FLEET IS AS STRONG AS HER RANK. % ladder rungs, % hull rows; 8 Dread fleets; % hunks once each and reversing; grants and volatility unmoved; no other function moved; % new functions server-only. Probe: %. % ms.',
    (select count(*) from public.npc_ladder), (select count(*) from public.npc_ladder_hulls), (select count(*) from hunks_0451), cardinality(c_new), v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0451;
end $m$;

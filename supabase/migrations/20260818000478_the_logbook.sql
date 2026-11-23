-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0478 - THE LOGBOOK: DISCOVERY AND COLLECTIONS  (dark: the owner's switch logbook_enabled, false; lit, a company keeps a page of firsts:
--        harbours by region, goods sold by kind, seas, hulls, captains; a first harbour is "Discovered"; a finished set pays once)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 9 ("The logbook: discovery and collections"); docs/design/content-plan-2026-11.md
--   5.3 item 6; docs/dev-log/2026-11-23-logbook.md.
--
-- WHY: 254 harbours, 629 goods, 51 seas, 157 hulls and 105 captains exist and nothing counts them (content plan 4.1, "Collections").
--   Uncharted Waters reports discoveries; RS3 and Melvor keep a collection log a player wears. It asks for nothing: it counts what she did.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE TABLE public.logbook: one row a company, a kind and a code, written THE FIRST TIME ONLY (its primary key the guard; a repeat
--     writes nothing). Kinds: harbour (ports.code, HARBOUR only), good (goods.code), hull (ship_classes.code), captain (officers.code), and
--     the finished sets: region (regions.code, every harbour of it) and kind (goods.category, every good of it). At most about 1,200 rows
--     a company in her whole life (254 + 629 + 157 + 105, and 42 sets). SEAS are not rows: a sea is counted when she has made a harbour of
--     it (every one of the 51 seas has one). MERCHANTS (players.is_npc) keep no logbook: nothing is written or read for them.
--   THE WRITERS, at the two existing points, never a scan of the companies:
--     ARRIVAL (voyage.settle, one hunk in its VOYAGE_REPORT payload -> public.logbook_arrival): dark '{}' after one knob read; a merchant
--       '{}' after one players probe. Lit: the harbour she sailed from and her hulls' classes and her captains as they are (silently), then
--       the harbour she made; a first one adds `logbook.found` to the report (THE "DISCOVERED" MOMENT: the harbour, its region n / of, the
--       sea and whether it is new, and its specialty: up to three goods of public.port_specialties, the most valuable first); then her
--       finished sets are settled (public.logbook_sets_settle) and any newly finished rides the report as `logbook.sets`.
--     SALE (cmd.do_sell, one hunk in its SOLD payload -> public.logbook_sale): dark '{}'; a merchant '{}'. Lit: a first sale of a good adds
--       `logbook` {good, kind, n, of, goods} to the SOLD event (the arrival card's "New: Cinnamon · Spice 3 / 22"), and settles her sets.
--     Neither ever raises: a fault is a warning and '{}', so an arrival or a sale never fails here.
--   A FINISHED SET (public.logbook_sets_settle, the one writer of the set rows): every harbour of a region, or every good of a kind. Once:
--     a set row, and logbook_set_rep (100) Reputation through public.reputation_credit (kind `logbook`, keyed `logbook:<set>:<code>`, not
--     day-capped). AND A SMALL LASTING BENEFIT, in the dock fee, through THE ONE dock fee (public.port_fee, one hunk ->
--     public.logbook_fee_factor), so the card, the plans and the charge agree: a finished REGION's harbours charge her
--     logbook_region_fee_cut (25 %) less; each finished goods KIND takes logbook_kind_fee_cut (2 %) off every dock fee. 42 sets (25 regions,
--     17 kinds). Hulls, captains and seas are counts with no set.
--   THE READ, world.logbook() (the client's one door, registered): dark {"on": false}. Lit: the totals (harbours, goods, seas, hulls,
--     captains: n / of), each region with its harbours and each kind with its goods (n / of / done, the codes in order), the hull families,
--     the captains and the seas, what she has seen of each (hulls and captains also as she holds them now, harbours also where her fleets
--     lie), the sets done of 42, and the reward knobs. Writes nothing.
-- THE BACK-FILL (once, here, dark, set-based): for each company that is not a merchant (prod 2026-11-23: 19 of them; 123 VOYAGE_REPORT
--   and 33 SOLD events), the harbours of her VOYAGE_REPORT events (to and from), her first-landfall Reputation keys (0352) and where her
--   fleets lie; the goods of her SOLD events (by name, as the payload writes them, or by code); her ships' classes; the captains she
--   signed. Read by the (player_id, created_at) index per company. No set is written or paid here: her next lit arrival settles them
--   (with their Reputation), so the dark switch moves nothing a player sees. Merchants are not read.
-- ONE AUTHORITY EACH: the rows, public.logbook_arrival / public.logbook_sale (items) and public.logbook_sets_settle (sets); the benefit,
--   public.logbook_fee_factor read by public.port_fee alone; the page, world.logbook().
-- NOT CHANGED: any price, the sale, the arrival's other steps, the landfall Reputation (0352), the dock fee for a merchant, a company with
--   no finished set, or anyone while dark. No knob of another feature moves.
-- ROWS: dark none (the back-fill once: prod's read 66 harbours, 19 goods, 21 hulls, 1 captain). Lit: a row the first time only.
--   -- budget: one new table of at most ~1,200 rows a company (non-merchants only), no job, no cron, no index beyond its primary key.
-- COST: dark one knob read at an arrival, a sale and a dock fee. Lit: an arrival of a company a few key probes and inserts that conflict
--   (no write), and the sets' check (an anti-join over 254 harbours and 629 goods, about a millisecond); a sale one insert that conflicts;
--   a dock fee one key probe (merchants: no row) and, with a finished set, two more.
-- LOCKS: CREATE TABLE (new, no foreign key: one would lock public.players); CREATE FUNCTION x5; CREATE OR REPLACE x4 by a hunk each
--   (voyage.settle, cmd.do_sell, public.port_fee, public.client_rpc_entry_points); four knobs; one reputation kind. TIME: a second.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, logbook_enabled false (nothing is written, the payloads and the dock fee are their pre-images', the
--   read is {"on": false}; the rows stay, inert). Full: a new migration reversing the four hunks (OLD texts below verbatim), dropping the
--   five functions and the table, deleting the knobs and the reputation kind (its book rows stay: the book is append-only).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; the knobs; the kind; the back-fill wrote no merchant row and no set; the table and the server-only functions unreachable by a
--   client, world.logbook registered for authenticated alone. THE PROBE (rolled back; every comparison of two figures is made in ONE
--   SELECT, and nothing read is time-budgeted): DARK an arrival and a sale write nothing and add nothing to their payloads, the dock fee
--   equals its pre-image's (a copy in pg_temp) even with a finished set on her row, the read {"on": false}; LIT her first arrival at a
--   harbour is "Discovered" with its specialty and finishes the region (its harbours seeded but one): a set row and its Reputation once;
--   a first sale tells the good, a second nothing; the dock fee there is the pre-image's less the cut, elsewhere the pre-image's; the
--   read counts it; a merchant's arrival and sale write nothing. Proof 181 plays it with the purses lit and the goods' sets.
-- VERSION: 0478 = 0477 + 1 (0477, #821, hunks client_rpc_entry_points; this file's registry hunk is anchored on 0477's own new line).
-- news: none (dark: nothing changes for a player until the owner lights logbook_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['voyage.settle(uuid,timestamp with time zone)', 'cmd.do_sell(uuid,jsonb)',
                                    'public.port_fee(uuid,uuid,numeric)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.logbook_sets_settle(uuid,timestamp with time zone)',
                                    'public.logbook_arrival(uuid,uuid,uuid,timestamp with time zone)',
                                    'public.logbook_sale(uuid,uuid)', 'public.logbook_fee_factor(uuid,uuid)', 'world.logbook()'];
  c_uid    constant uuid := '00000000-0478-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_lived     boolean := false;
  v_back      jsonb;
  v_lis       uuid;
  v_set       uuid;
  v_far       uuid;
  v_reg       uuid;
  v_me        uuid;
  v_fl        uuid;
  v_segs      jsonb;
  v_voy       uuid;
  v_eta       timestamptz;
  v_good      uuid;
  v_gcode     text;
  v_npc       uuid;
  v_r         jsonb;
  v_f         record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'logbook_enabled') or to_regclass('public.logbook') is not null then
    raise exception '0478 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is null or to_regclass('public.port_specialties') is null
     or to_regclass('public.reputation_kinds') is null or to_regprocedure('world.early_sighting()') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null or to_regprocedure('public.regard_factor(uuid,uuid)') is null then
    raise exception '0478 refuses: 0477 (the registry line), 0352 (Reputation), 0319 (regard), 0280 (specialties) or 0213 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  -- the dock fee as it is, kept for the probe's comparisons (dropped at the end)
  execute replace(replace(pg_get_functiondef('public.port_fee(uuid,uuid,numeric)'::regprocedure), E'\r', ''),
                  'FUNCTION public.port_fee(', 'FUNCTION pg_temp.port_fee_pre_0478(');

  -- ── 2. THE KNOBS, THE KIND AND THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('logbook_enabled', 'false'::jsonb,
     '0478: THE SWITCH (the owner''s). true: a company''s firsts are written at her arrivals and sales (public.logbook: harbours, goods, hulls, captains; seas counted from the harbours), a first harbour is "Discovered" on the arrival card, a first sale says "New", a finished set (a region''s harbours, a kind''s goods) pays logbook_set_rep Reputation once and cuts her dock fees, and world.logbook() serves the page. false: nothing is written, the payloads and the dock fee are as before, the read is {"on": false}.'),
    ('logbook_set_rep', to_jsonb(100), '0478: the Reputation a finished logbook set pays, once (kind logbook, keyed by the set; not day-capped).'),
    ('logbook_region_fee_cut', to_jsonb(0.25), '0478: a finished region (every harbour of it made): her dock fee at its harbours is this share less (public.logbook_fee_factor, read by public.port_fee).'),
    ('logbook_kind_fee_cut', to_jsonb(0.02), '0478: each finished goods kind (every good of it sold): her dock fee everywhere is this share less, added up (never under 0).');
  insert into public.reputation_kinds (code, sign, capped, word) values ('logbook', 1, false, 'Logbook');

  -- retention: none, bounded by its primary key: one row a company, a kind and a code, at most ~1,200 a non-merchant company in her life.
  create table public.logbook (
    player_id uuid        not null,
    kind      text        not null check (kind in ('harbour', 'good', 'hull', 'captain', 'region', 'kind')),
    code      text        not null,
    first_at  timestamptz not null default now(),
    primary key (player_id, kind, code)
  );
  comment on table public.logbook is
    '0478: THE LOGBOOK, a company''s firsts: a harbour made, a good sold, a hull held, a captain signed (written the first time only, at her '
    'arrival, public.logbook_arrival, and her sale, public.logbook_sale), and a finished set (region / kind, public.logbook_sets_settle). '
    'Merchants keep none. No foreign key on purpose: one would lock public.players. Read by world.logbook() and public.logbook_fee_factor.';
  alter table public.logbook enable row level security;
  revoke all on table public.logbook from public, anon, authenticated;

  -- ── 3. THE RULES ──
  execute $f$
create function public.logbook_sets_settle(p_player uuid, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0478: HER FINISHED SETS, written once and paid once. A region is finished when every harbour of it is in her logbook, a kind when every
-- good of it is. A set not written yet: its row (kind region / kind), and logbook_set_rep Reputation (public.reputation_credit, kind
-- logbook, keyed logbook:<set>:<code>, so it books once). Answers the sets finished now, [{set, code, rep}] ('[]' when none). Called by
-- public.logbook_arrival and public.logbook_sale, lit, for a company only.
declare
  r     record;
  v_rep int;
  v_out jsonb := '[]'::jsonb;
begin
  for r in
    select 'region'::text as s, g.code, g.name from public.regions g
     where exists (select 1 from public.ports p where p.region_id = g.id and p.kind = 'HARBOUR')
       and not exists (select 1 from public.ports p where p.region_id = g.id and p.kind = 'HARBOUR'
                        and not exists (select 1 from public.logbook l where l.player_id = p_player and l.kind = 'harbour' and l.code = p.code))
       and not exists (select 1 from public.logbook l where l.player_id = p_player and l.kind = 'region' and l.code = g.code)
    union all
    select 'kind', c.category, c.category from (select distinct gg.category from public.goods gg where gg.category is not null) c
     where not exists (select 1 from public.goods gg where gg.category = c.category
                        and not exists (select 1 from public.logbook l where l.player_id = p_player and l.kind = 'good' and l.code = gg.code))
       and not exists (select 1 from public.logbook l where l.player_id = p_player and l.kind = 'kind' and l.code = c.category)
    order by 1, 2
  loop
    insert into public.logbook (player_id, kind, code, first_at) values (p_player, r.s, r.code, p_at) on conflict do nothing;
    if found then
      v_rep := public.reputation_credit(p_player, 'logbook', coalesce(public.wc_int('logbook_set_rep'), 0), 'logbook:' || r.s || ':' || r.code,
                                        jsonb_build_object('set', r.s, 'code', r.code));
      v_out := v_out || jsonb_build_array(jsonb_build_object('set', r.s, 'code', r.code, 'name', r.name, 'rep', coalesce(v_rep, 0)));
    end if;
  end loop;
  return v_out;
end
$body$
  $f$;

  execute $f$
create function public.logbook_arrival(p_player uuid, p_from uuid, p_to uuid, p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0478: AN ARRIVAL IN THE LOGBOOK, from voyage.settle's VOYAGE_REPORT payload (what this answers is added to the report). Dark: '{}'
-- after one knob read. A merchant (or nobody): '{}' after one players probe. Lit, a company: the harbour she sailed from, her hulls'
-- classes and her captains as they are (silently: no moment), then the harbour she made; a first one is THE "DISCOVERED" MOMENT,
-- logbook.found {port, region, n, of, harbours, sea, sea_new, specialty}; then her finished sets (public.logbook_sets_settle) as
-- logbook.sets. Nothing new: '{}'. Never raises: a fault is a warning and '{}', so an arrival never fails here.
declare
  v_new  boolean;
  v_out  jsonb := '{}'::jsonb;
  v_sets jsonb;
begin
  if public.wc('logbook_enabled') is distinct from 'true'::jsonb then
    return '{}'::jsonb;
  end if;
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return '{}'::jsonb;
  end if;
  begin
    insert into public.logbook (player_id, kind, code, first_at)
    select p_player, 'harbour', p.code, p_at from public.ports p where p.id = p_from and p.kind = 'HARBOUR'
    on conflict do nothing;
    insert into public.logbook (player_id, kind, code, first_at)
    select distinct p_player, 'hull', c.code, p_at from public.ships s join public.ship_classes c on c.id = s.class_id where s.player_id = p_player
    on conflict do nothing;
    insert into public.logbook (player_id, kind, code, first_at)
    select distinct p_player, 'captain', o.code, p_at from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = p_player
    on conflict do nothing;
    insert into public.logbook (player_id, kind, code, first_at)
    select p_player, 'harbour', p.code, p_at from public.ports p where p.id = p_to and p.kind = 'HARBOUR'
    on conflict do nothing;
    v_new := found;
    if v_new then
      select jsonb_build_object(
               'port', p.code,
               'region', g.code,
               'region_name', g.name,
               'n', (select count(*) from public.logbook l join public.ports q on q.code = l.code
                      where l.player_id = p_player and l.kind = 'harbour' and q.region_id = p.region_id and q.kind = 'HARBOUR'),
               'of', (select count(*) from public.ports q where q.region_id = p.region_id and q.kind = 'HARBOUR'),
               'harbours', (select count(*) from public.logbook l where l.player_id = p_player and l.kind = 'harbour'),
               'sea', s.code,
               'sea_new', not exists (select 1 from public.logbook l join public.ports q on q.code = l.code
                                       where l.player_id = p_player and l.kind = 'harbour' and q.sea_id = p.sea_id and q.id <> p.id),
               'specialty', (select coalesce(jsonb_agg(z.code order by z.base_value desc, z.code), '[]'::jsonb)
                               from (select gd.code, gd.base_value from public.port_specialties ps join public.goods gd on gd.id = ps.good_id
                                      where ps.port_id = p.id order by gd.base_value desc, gd.code limit 3) z))
        into v_out
        from public.ports p
        left join public.regions g on g.id = p.region_id
        left join public.seas s on s.id = p.sea_id
       where p.id = p_to;
      v_out := jsonb_build_object('found', v_out);
    end if;
    v_sets := public.logbook_sets_settle(p_player, p_at);
    if jsonb_array_length(v_sets) > 0 then
      v_out := v_out || jsonb_build_object('sets', v_sets);
    end if;
    return case when v_out = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('logbook', v_out) end;
  exception when others then
    raise warning 'logbook_arrival: % at % was not written (SQLSTATE %: %)', p_player, p_to, sqlstate, sqlerrm;
    return '{}'::jsonb;
  end;
end
$body$
  $f$;

  execute $f$
create function public.logbook_sale(p_player uuid, p_good uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0478: A SALE IN THE LOGBOOK, from cmd.do_sell's SOLD payload (what this answers is added to the event). Dark: '{}' after one knob read.
-- A merchant (or nobody): '{}' after one players probe. Lit, a company's first sale of this good: its row, and logbook {good, kind, n, of,
-- goods} (n / of: her goods of its kind / the kind's goods; goods: all she has sold), with any set it finished (sets). A good sold before:
-- '{}' (the insert conflicts; nothing is written). Never raises: a fault is a warning and '{}', so a sale never fails here.
declare
  g      public.goods%rowtype;
  v_sets jsonb;
  v_out  jsonb;
begin
  if public.wc('logbook_enabled') is distinct from 'true'::jsonb then
    return '{}'::jsonb;
  end if;
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return '{}'::jsonb;
  end if;
  begin
    select * into g from public.goods x where x.id = p_good;
    if g.id is null then
      return '{}'::jsonb;
    end if;
    insert into public.logbook (player_id, kind, code, first_at) values (p_player, 'good', g.code, now()) on conflict do nothing;
    if not found then
      return '{}'::jsonb;
    end if;
    v_sets := public.logbook_sets_settle(p_player, now());
    v_out := jsonb_build_object(
      'good', g.code,
      'kind', g.category,
      'n', (select count(*) from public.logbook l join public.goods gg on gg.code = l.code
             where l.player_id = p_player and l.kind = 'good' and gg.category = g.category),
      'of', (select count(*) from public.goods gg where gg.category = g.category),
      'goods', (select count(*) from public.logbook l where l.player_id = p_player and l.kind = 'good'));
    if jsonb_array_length(v_sets) > 0 then
      v_out := v_out || jsonb_build_object('sets', v_sets);
    end if;
    return jsonb_build_object('logbook', v_out);
  exception when others then
    raise warning 'logbook_sale: % selling % was not written (SQLSTATE %: %)', p_player, p_good, sqlstate, sqlerrm;
    return '{}'::jsonb;
  end;
end
$body$
  $f$;

  execute $f$
create function public.logbook_fee_factor(p_player uuid, p_port uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0478: WHAT HER FINISHED SETS TAKE OFF A DOCK FEE, as a factor (read by public.port_fee alone, so every reader of the fee agrees). Dark: 1
-- after one knob read. No finished set (every merchant): 1 after one key probe. Else (1 - logbook_region_fee_cut) when the harbour's region
-- is a finished set of hers, times (1 - logbook_kind_fee_cut x her finished goods kinds), never under 0.
declare
  v_f numeric := 1;
  v_k int;
begin
  if public.wc('logbook_enabled') is distinct from 'true'::jsonb then
    return 1;
  end if;
  if p_player is null or not exists (select 1 from public.logbook l where l.player_id = p_player and l.kind in ('region', 'kind')) then
    return 1;
  end if;
  if exists (select 1 from public.ports p join public.regions g on g.id = p.region_id
              join public.logbook l on l.player_id = p_player and l.kind = 'region' and l.code = g.code
             where p.id = p_port) then
    v_f := v_f * (1 - least(1, greatest(0, coalesce(public.wc_num('logbook_region_fee_cut'), 0))));
  end if;
  select count(*) into v_k from public.logbook l where l.player_id = p_player and l.kind = 'kind';
  return v_f * greatest(0, 1 - v_k * greatest(0, coalesce(public.wc_num('logbook_kind_fee_cut'), 0)));
end
$body$
  $f$;

  execute $f$
create function world.logbook()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0478: THE LOGBOOK PAGE, the client's one door. Dark (logbook_enabled false): {"on": false}. Lit, signed out or a merchant:
-- {"on": true, "company": false}. Lit, her company: the totals (harbours, goods, seas, hulls, captains: n / of); each region (its harbours
-- in name order) and each goods kind (its goods, the most valuable first) with n / of / done; the hull families and their classes; the
-- captains; the seas; `seen`, the codes she has of each (hulls and captains also as she holds them now, harbours also where her fleets lie
-- in port, seas those of her harbours); the sets done of all; the reward knobs. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if public.wc('logbook_enabled') is distinct from 'true'::jsonb then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return (
    with hp as (select p.id, p.code, p.name, p.region_id, p.sea_id from public.ports p where p.kind = 'HARBOUR'),
    hb as (select hp.* from hp where hp.code in (select l.code from public.logbook l where l.player_id = v_me and l.kind = 'harbour'
                                                 union select q.code from public.fleets f join public.ports q on q.id = f.port_id
                                                        where f.player_id = v_me and f.status = 'DOCKED')),
    gd as (select g.code, g.category from public.goods g
            where g.code in (select l.code from public.logbook l where l.player_id = v_me and l.kind = 'good')),
    hl as (select c.code, c.family from public.ship_classes c
            where c.code in (select l.code from public.logbook l where l.player_id = v_me and l.kind = 'hull'
                             union select c2.code from public.ships s join public.ship_classes c2 on c2.id = s.class_id where s.player_id = v_me)),
    cp as (select o.code from public.officers o
            where o.code in (select l.code from public.logbook l where l.player_id = v_me and l.kind = 'captain'
                             union select o2.code from public.player_officers po join public.officers o2 on o2.id = po.officer_id where po.player_id = v_me)),
    st as (select l.kind, l.code from public.logbook l where l.player_id = v_me and l.kind in ('region', 'kind')),
    sx as (select s.id, s.code, s.name from public.seas s where exists (select 1 from hp where hp.sea_id = s.id))
    select jsonb_build_object(
      'on', true,
      'company', true,
      'totals', jsonb_build_object(
        'harbours', jsonb_build_object('n', (select count(*) from hb), 'of', (select count(*) from hp)),
        'goods',    jsonb_build_object('n', (select count(*) from gd), 'of', (select count(*) from public.goods)),
        'seas',     jsonb_build_object('n', (select count(distinct hb.sea_id) from hb), 'of', (select count(*) from sx)),
        'hulls',    jsonb_build_object('n', (select count(*) from hl), 'of', (select count(*) from public.ship_classes)),
        'captains', jsonb_build_object('n', (select count(*) from cp), 'of', (select count(*) from public.officers))),
      'regions', (select coalesce(jsonb_agg(jsonb_build_object(
                     'code', g.code, 'name', g.name,
                     'n', (select count(*) from hb where hb.region_id = g.id),
                     'of', (select count(*) from hp where hp.region_id = g.id),
                     'done', exists (select 1 from st where st.kind = 'region' and st.code = g.code),
                     'harbours', (select jsonb_agg(hp.code order by hp.name, hp.code) from hp where hp.region_id = g.id))
                   order by g.code), '[]'::jsonb)
                    from public.regions g where exists (select 1 from hp where hp.region_id = g.id)),
      'kinds', (select coalesce(jsonb_agg(jsonb_build_object(
                   'code', k.category,
                   'n', (select count(*) from gd where gd.category = k.category),
                   'of', (select count(*) from public.goods g where g.category = k.category),
                   'done', exists (select 1 from st where st.kind = 'kind' and st.code = k.category),
                   'goods', (select jsonb_agg(g.code order by g.base_value desc, g.code) from public.goods g where g.category = k.category))
                 order by k.category), '[]'::jsonb)
                  from (select distinct g.category from public.goods g where g.category is not null) k),
      'families', (select coalesce(jsonb_agg(jsonb_build_object(
                      'code', fm.family,
                      'n', (select count(*) from hl where hl.family = fm.family),
                      'of', (select count(*) from public.ship_classes c where c.family = fm.family),
                      'hulls', (select jsonb_agg(c.code order by c.tier, c.code) from public.ship_classes c where c.family = fm.family))
                    order by fm.family), '[]'::jsonb)
                     from (select distinct c.family from public.ship_classes c where c.family is not null) fm),
      'captains', (select coalesce(jsonb_agg(jsonb_build_object('code', o.code, 'name', o.name) order by o.name, o.code), '[]'::jsonb) from public.officers o),
      'seas', (select coalesce(jsonb_agg(jsonb_build_object('code', sx.code, 'name', sx.name) order by sx.name, sx.code), '[]'::jsonb) from sx),
      'seen', jsonb_build_object(
        'harbours', (select coalesce(jsonb_agg(hb.code order by hb.code), '[]'::jsonb) from hb),
        'goods',    (select coalesce(jsonb_agg(gd.code order by gd.code), '[]'::jsonb) from gd),
        'hulls',    (select coalesce(jsonb_agg(hl.code order by hl.code), '[]'::jsonb) from hl),
        'captains', (select coalesce(jsonb_agg(cp.code order by cp.code), '[]'::jsonb) from cp),
        'seas',     (select coalesce(jsonb_agg(distinct sx.code), '[]'::jsonb) from hb join sx on sx.id = hb.sea_id)),
      'sets', jsonb_build_object(
        'done', (select count(*) from st),
        'of', (select count(*) from public.regions g where exists (select 1 from hp where hp.region_id = g.id))
              + (select count(distinct g.category) from public.goods g where g.category is not null)),
      'reward', jsonb_build_object(
        'rep', coalesce(public.wc_int('logbook_set_rep'), 0),
        'region_cut', coalesce(public.wc_num('logbook_region_fee_cut'), 0),
        'kind_cut', coalesce(public.wc_num('logbook_kind_fee_cut'), 0)))
  );
end
$body$
  $f$;
  revoke all on function public.logbook_sets_settle(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.logbook_arrival(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.logbook_sale(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.logbook_fee_factor(uuid, uuid) from public, anon, authenticated;
  revoke all on function world.logbook() from public, anon;
  grant execute on function world.logbook() to authenticated;
  comment on function world.logbook() is
    '0478: the logbook page (dark {"on": false}): her firsts by region, kind, family; the seas and captains; the sets done; the reward knobs. A read. Client door.';

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0478 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0478 values
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$           where z.payload ? 'rounds'));$h$,
$h$           where z.payload ? 'rounds')
      -- 0478: the logbook: a first harbour (logbook.found, the "Discovered" moment) and any set it finished ('{}' dark, a merchant, nothing new)
      || public.logbook_arrival(f.player_id, v.origin_port_id, v.dest_port_id, v.eta));$h$),
  ('cmd.do_sell(uuid,jsonb)', 1,
$h$      'haggle_saved', q.haggle_saved)));$h$,
$h$      'haggle_saved', q.haggle_saved)
      -- 0478: the logbook: a first sale of this good (logbook {good, kind, n, of}; '{}' dark, a merchant, a good sold before)
      || public.logbook_sale(f.player_id, g.id)));$h$),
  ('public.port_fee(uuid,uuid,numeric)', 1,
$h$* public.regard_factor(p_player, p_port)))::bigint;$h$,
$h$* public.regard_factor(p_player, p_port)
                           -- 0478: her finished logbook sets (public.logbook_fee_factor: 1 dark, for a merchant, with none finished)
                           * public.logbook_fee_factor(p_player, p_port)))::bigint;$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'early_sighting',        ''),$h$,
$h$      ('world',       'early_sighting',        ''),
      -- 0478: the logbook (dark: {"on": false})
      ('world',       'logbook',               ''),$h$);

  for v_h in select h.fn from hunks_0478 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0478 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0478 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0478 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0478 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0478 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. THE BACK-FILL (once; companies, not merchants; no set is written or paid: her next lit arrival settles them) ──
  insert into public.logbook (player_id, kind, code, first_at)
  select q.player_id, 'harbour', q.code, min(q.at)
    from (select hu.id as player_id, e.payload ->> 'to' as code, e.created_at as at
            from public.players hu cross join lateral (select ex.payload, ex.created_at from public.events ex
                                                        where ex.player_id = hu.id and ex.kind = 'VOYAGE_REPORT') e
           where not hu.is_npc
          union all
          select hu.id, e.payload ->> 'from', e.created_at
            from public.players hu cross join lateral (select ex.payload, ex.created_at from public.events ex
                                                        where ex.player_id = hu.id and ex.kind = 'VOYAGE_REPORT') e
           where not hu.is_npc
          union all
          select rb.player_id, substr(rb.key, 10), rb.created_at
            from public.players hu join public.reputation_book rb on rb.player_id = hu.id and rb.key like 'landfall:%'
           where not hu.is_npc
          union all
          select f.player_id, p.code, now()
            from public.players hu join public.fleets f on f.player_id = hu.id join public.ports p on p.id = f.port_id
           where not hu.is_npc and f.status = 'DOCKED') q
    join public.ports p on p.code = q.code and p.kind = 'HARBOUR'
   group by q.player_id, q.code;
  insert into public.logbook (player_id, kind, code, first_at)
  select hu.id, 'good', g.code, min(e.created_at)
    from public.players hu
    cross join lateral (select ex.payload, ex.created_at from public.events ex where ex.player_id = hu.id and ex.kind = 'SOLD') e
    join public.goods g on g.name = e.payload ->> 'good' or g.code = e.payload ->> 'good'
   where not hu.is_npc
   group by hu.id, g.code;
  insert into public.logbook (player_id, kind, code, first_at)
  select distinct hu.id, 'hull', c.code, now()
    from public.players hu join public.ships s on s.player_id = hu.id join public.ship_classes c on c.id = s.class_id
   where not hu.is_npc;
  insert into public.logbook (player_id, kind, code, first_at)
  select hu.id, 'captain', o.code, min(po.hired_at)
    from public.players hu join public.player_officers po on po.player_id = hu.id join public.officers o on o.id = po.officer_id
   where not hu.is_npc
   group by hu.id, o.code;
  select jsonb_object_agg(s.kind, s.n) into v_back from (select l.kind, count(*) as n from public.logbook l group by l.kind) s;

  -- ── 6. SELF-ASSERT: the catalog, the knobs, the back-fill, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0478 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0478 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if public.wc('logbook_enabled') <> 'false'::jsonb or public.wc_int('logbook_set_rep') <> 100
     or public.wc_num('logbook_region_fee_cut') <> 0.25 or public.wc_num('logbook_kind_fee_cut') <> 0.02
     or not exists (select 1 from public.reputation_kinds k where k.code = 'logbook' and k.sign = 1 and not k.capped) then
    raise exception '0478 self-assert FAIL: the knobs or the reputation kind are not as written';
  end if;
  if exists (select 1 from public.logbook l join public.players p on p.id = l.player_id where p.is_npc)
     or exists (select 1 from public.logbook l where l.kind in ('region', 'kind'))
     or exists (select 1 from public.logbook l where not exists (select 1 from public.players p where p.id = l.player_id)) then
    raise exception '0478 self-assert FAIL: the back-fill wrote a merchant''s row, a set or a row of nobody';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'logbook', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or has_function_privilege('authenticated', 'public.logbook_sets_settle(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.logbook_arrival(uuid,uuid,uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.logbook_sale(uuid,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.logbook_fee_factor(uuid,uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.logbook', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.logbook', 'select')
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0478 self-assert FAIL: world.logbook is not registered for authenticated alone, or a client reaches a server-only function or the table';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select p.id into v_set from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR';
    select p.region_id into v_reg from public.ports p where p.id = v_set;
    -- a harbour of another region, for the dock fee a finished region does not cut
    select p.id into v_far from public.ports p where p.kind = 'HARBOUR' and p.region_id is distinct from v_reg order by p.code limit 1;
    select voyage.segments_from_course(jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b2.roadstead_lat, b2.roadstead_lon)))
      into v_segs from public.sea_reaches a, public.sea_reaches b2 where a.port_id = v_lis and b2.port_id = v_set;
    -- a good the harbour of the probe trades
    select g.id, g.code into v_good, v_gcode
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_set and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
     order by g.code limit 1;
    v_me := public.new_house(c_uid, 'Casa do Diario 0478', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    select n.id into v_npc from public.players n where n.is_npc order by n.id limit 1;
    -- the purses lit and the economy closed, so a dock fee is charged (prod's switches; the image may run them dark)
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled', 'reputation_on');
    insert into public.port_treasury (port_id) select p.id from public.ports p where p.id in (v_lis, v_set, v_far) on conflict (port_id) do nothing;
    update public.port_treasury t set ducats = 5000000, reserve = 0 where t.port_id in (v_lis, v_set, v_far);

    -- (a) DARK: an arrival and a sale write nothing and add nothing; the dock fee is its pre-image's, even with a finished set on her row
    update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
    v_voy := voyage.depart(v_fl, v_segs, v_lis, v_set, now() - interval '20 seconds');
    select v.eta into v_eta from public.voyages v where v.id = v_voy;
    perform voyage.settle(v_fl, v_eta + interval '1 second');
    update public.fleets f set status = 'DOCKED', port_id = v_set, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
    update public.ships s set cargo = jsonb_build_object(v_gcode, 40), cargo_basis = jsonb_build_object(v_gcode, 1) where s.fleet_id = v_fl;
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good, 'qty', 10));
    perform cmd.assume_identity(c_uid);
    if exists (select 1 from public.logbook l where l.player_id = v_me)
       or exists (select 1 from public.events e where e.player_id = v_me and e.kind in ('VOYAGE_REPORT', 'SOLD') and e.payload ? 'logbook')
       or not exists (select 1 from public.events e where e.player_id = v_me and e.kind = 'VOYAGE_REPORT' and e.payload ->> 'to' = 'SET')
       or not exists (select 1 from public.events e where e.player_id = v_me and e.kind = 'SOLD')
       or public.logbook_arrival(v_me, v_lis, v_set, now()) <> '{}'::jsonb or public.logbook_sale(v_me, v_good) <> '{}'::jsonb
       or world.logbook() is distinct from '{"on": false}'::jsonb then
      raise exception '0478 self-assert FAIL: dark, an arrival or a sale wrote the logbook or told it, or the read is not {"on": false}';
    end if;
    insert into public.logbook (player_id, kind, code) select v_me, 'region', g.code from public.regions g where g.id = v_reg;
    insert into public.logbook (player_id, kind, code) select v_me, 'kind', gg.category from public.goods gg where gg.id = v_good;
    for v_f in select pg_temp.port_fee_pre_0478(p.id, v_me, 100000) as pre, public.port_fee(p.id, v_me, 100000) as now_fee
                 from public.ports p where p.id in (v_set, v_far) loop
      if v_f.pre is distinct from v_f.now_fee then
        raise exception '0478 self-assert FAIL: dark, a dock fee moved with a finished set on her row: % -> %', v_f.pre, v_f.now_fee;
      end if;
    end loop;
    delete from public.logbook l where l.player_id = v_me;

    -- (b) LIT: her first arrival at SET is "Discovered" and finishes its region (its other harbours seeded): one set row, its Reputation once
    update public.world_config set value = 'true'::jsonb where key = 'logbook_enabled';
    insert into public.logbook (player_id, kind, code)
    select v_me, 'harbour', p.code from public.ports p where p.region_id = v_reg and p.kind = 'HARBOUR' and p.id <> v_set;
    update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
    v_voy := voyage.depart(v_fl, v_segs, v_lis, v_set, now() - interval '20 seconds');
    select v.eta into v_eta from public.voyages v where v.id = v_voy;
    perform voyage.settle(v_fl, v_eta + interval '1 second');
    select e.payload -> 'logbook' into v_r from public.events e
     where e.player_id = v_me and e.kind = 'VOYAGE_REPORT' and e.payload ->> 'voyage_id' = v_voy::text;
    if v_r #>> '{found,port}' is distinct from 'SET'
       or (v_r #>> '{found,n}')::int <> (v_r #>> '{found,of}')::int
       or jsonb_array_length(v_r #> '{found,specialty}') not between 1 and 3
       or v_r #> '{sets,0}' is distinct from (select jsonb_build_object('set', 'region', 'code', g.code, 'name', g.name, 'rep', 100) from public.regions g where g.id = v_reg)
       or (select count(*) from public.reputation_book b where b.player_id = v_me and b.kind = 'logbook') <> 1
       or not exists (select 1 from public.logbook l join public.ships s on s.player_id = v_me join public.ship_classes c on c.id = s.class_id
                       where l.player_id = v_me and l.kind = 'hull' and l.code = c.code) then
      raise exception '0478 self-assert FAIL: lit, the first arrival was not Discovered with its region finished and paid once: %', v_r;
    end if;
    -- arriving there again tells nothing and pays nothing
    update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
    v_voy := voyage.depart(v_fl, v_segs, v_lis, v_set, now() - interval '20 seconds');
    select v.eta into v_eta from public.voyages v where v.id = v_voy;
    perform voyage.settle(v_fl, v_eta + interval '1 second');
    if exists (select 1 from public.events e where e.player_id = v_me and e.kind = 'VOYAGE_REPORT' and e.payload ->> 'voyage_id' = v_voy::text and e.payload ? 'logbook')
       or (select count(*) from public.reputation_book b where b.player_id = v_me and b.kind = 'logbook') <> 1 then
      raise exception '0478 self-assert FAIL: lit, a second arrival at a known harbour told or paid again';
    end if;

    -- (c) a first sale tells the good; a second, nothing
    update public.fleets f set status = 'DOCKED', port_id = v_set, lat = null, lon = null, busy_until = null, ready_at = null where f.id = v_fl;
    update public.ships s set cargo = jsonb_build_object(v_gcode, 40), cargo_basis = jsonb_build_object(v_gcode, 1) where s.fleet_id = v_fl;
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good, 'qty', 10));
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_good, 'qty', 10));
    if (select count(*) from public.events e where e.player_id = v_me and e.kind = 'SOLD' and e.payload #>> '{logbook,good}' = v_gcode) <> 1
       or (select count(*) from public.events e where e.player_id = v_me and e.kind = 'SOLD' and e.payload ->> 'good' = (select g.name from public.goods g where g.id = v_good)) < 3
       or (select (e.payload #>> '{logbook,n}')::int from public.events e where e.player_id = v_me and e.kind = 'SOLD' and e.payload ? 'logbook') <> 1 then
      raise exception '0478 self-assert FAIL: lit, the first sale was not told once with its kind''s count';
    end if;

    -- (d) THE BENEFIT: the dock fee in the finished region is the pre-image's less the cut; elsewhere the pre-image's (one SELECT each)
    for v_f in select p.id, pg_temp.port_fee_pre_0478(p.id, v_me, 100000) as pre, public.port_fee(p.id, v_me, 100000) as now_fee
                 from public.ports p where p.id in (v_set, v_far) loop
      if v_f.pre <= 0
         or (v_f.id = v_set and abs(v_f.now_fee - v_f.pre * 0.75) > 1)
         or (v_f.id = v_far and v_f.now_fee <> v_f.pre) then
        raise exception '0478 self-assert FAIL: lit, the dock fee is not cut in the finished region alone: % % -> %', v_f.id, v_f.pre, v_f.now_fee;
      end if;
    end loop;

    -- (e) THE READ counts it; a merchant's arrival and sale write nothing
    v_r := world.logbook();
    if (v_r ->> 'on')::boolean is not true or (v_r #>> '{totals,harbours,n}')::int <> (select count(*) from public.ports p where p.region_id = v_reg and p.kind = 'HARBOUR')
       or (v_r #>> '{totals,goods,n}')::int <> 1 or (v_r #>> '{totals,seas,n}')::int < 1 or (v_r #>> '{totals,hulls,n}')::int < 1
       or (v_r #>> '{totals,harbours,of}')::int <> (select count(*) from public.ports p where p.kind = 'HARBOUR')
       or (v_r #>> '{sets,done}')::int <> 1
       or not exists (select 1 from jsonb_array_elements(v_r -> 'regions') g where (g ->> 'done')::boolean and g ->> 'code' = (select r.code from public.regions r where r.id = v_reg))
       or public.logbook_arrival(v_npc, v_lis, v_set, now()) <> '{}'::jsonb or public.logbook_sale(v_npc, v_good) <> '{}'::jsonb
       or exists (select 1 from public.logbook l where l.player_id = v_npc) then
      raise exception '0478 self-assert FAIL: lit, the read does not count her logbook, or a merchant was written: %', left(v_r::text, 600);
    end if;
    v_note := format('found SET (region %s finished, %s harbours; specialty %s), the set paid %s, the fee there %s -> %s',
                     (select r.code from public.regions r where r.id = v_reg), (v_r #>> '{totals,harbours,n}'),
                     (select e.payload #> '{logbook,found,specialty}' from public.events e where e.player_id = v_me and e.payload #>> '{logbook,found,port}' = 'SET' limit 1),
                     (select sum(b.delta) from public.reputation_book b where b.player_id = v_me and b.kind = 'logbook'),
                     (select pg_temp.port_fee_pre_0478(v_set, v_me, 100000)), (select public.port_fee(v_set, v_me, 100000)));
    raise exception using errcode = 'ZX478', message = 'PROBE_ROLLBACK_0478';
  exception when sqlstate 'ZX478' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0478 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0478' or p.auth_uid = c_uid)
     or exists (select 1 from public.logbook l where l.kind in ('region', 'kind'))
     or public.wc('logbook_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0478 self-assert FAIL: the probe left something behind';
  end if;
  drop function pg_temp.port_fee_pre_0478(uuid, uuid, numeric);

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0478 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0478 self-assert ok: THE LOGBOOK (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; the table, five functions, four knobs (logbook_enabled false), the kind logbook. Back-filled %. Probe (rolled back): dark nothing written or told, the fee its pre-image''s; lit %; a second arrival and sale told nothing; a merchant nothing. % ms.',
    (select count(*) from hunks_0478), coalesce(v_back, '{}'::jsonb), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

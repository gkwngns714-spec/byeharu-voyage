-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0162 — A CAPTAIN IS PROMOTED FOR WHAT HER COMPANY HAS DONE  (K8 "captains V": promotion — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §4.6 and §8 row K8. The owner, row 61: *"C ranked captains will be able to promote to
-- B, A, S … Promotion will be done with requirements - levels. items that will be earned when doing activities like
-- trading, combat, exploration - like for 건조소 but different items"*. D12 approved by default; every number is data.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   THE ITEMS      three rows in the ONE item system, item_kinds (new column `kind`: 'fitting' for every row of
--       today, 'promotion' for these): Sea Chart, Trade Seal, Battle Honour — the same for every captain — and
--       public.promotion_items (item → focus → the points that earn one; data/captains.json, guard-held).
--       A promotion item is never made at a workshop nor fitted: world.workstation and cmd.resolve_item read
--       fittings only (one hunk each).
--   EARNING        public.promotion_credit(player, port, track, points) — THE ONE WRITER: a PLAYER's company
--       (a merchant returns at once) banks the points in public.promotion_progress and, at a port, turns every
--       whole `points` into one item in storage there (player_items). Called where the captains learn: the
--       arrival arm (Exploration, Combat — at the arrival port; anchored at sea, the points wait) and the trade
--       cores (Trading, at the market's port). Trading's `points` (4,850) is MEASURED, see data/captains.json.
--   THE GATES      captain_grades gains promote_level / promote_items (B 5 / 10, A 10 / 20, S 15 / 40).
--   THE VERB       cmd.promote_captain(code) → public.promote_captain_for: her ship docked (or refused
--       E_NOT_IN_PORT; ashore she has no port, E_NOT_ABOARD), her level in her job's focus at least the next
--       grade's (E_LEVEL_TOO_LOW, with figures), the items in storage THERE (E_NOT_ENOUGH_ITEMS: "Needs 10 Sea
--       Charts here: you have 6 at Lisbon"); spends them and raises captain_state.grade. The new grade's slots,
--       known traits and floor (public.crew_terms: lifted once above the birth grade) follow from the ladder.
--       world.captains serves `promote` (the next grade, what it needs, what you have there, in words).
--   THE RE-CUTS (hunks sliced from the bodies live after K7, each occurring once, each reversing, ACLs
--       unchanged): world.workstation, cmd.resolve_item, voyage.settle, cmd.do_buy, cmd.do_sell, world.captains,
--       public.client_rpc_entry_points (+1).
--
-- ── DARK ────────────────────────────────────────────────────────────────────────────────────────
-- Nothing a company holds changes: no player holds a captain above her birth grade, so every trait stands where
-- it stood; promotion items are banked from the deploy on (no back-pay — said). Every reader answer, the
-- workshop list and the grammar's item names are their pre-images (asserted).
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) the catalogue: three promotion items, kind 'promotion', every row of today 'fitting'; the gates.
-- (b) DARK = the pre-image: world.workstation at every workshop port (no player), resolve_item for every item
--     name of today, crew_pct every fleet × 4, endurance and speed.
-- (c) THE PROBE (own house, rolled back): 250 exploration points at Lisbon → 2 Sea Charts in storage there and
--     50 banked; anchored, 80 more points → no item, 130 banked; a merchant's credit writes nothing; a C
--     navigator at level 4 is refused E_LEVEL_TOO_LOW, at level 5 with 9 charts E_NOT_ENOUGH_ITEMS (the sentence
--     names the figures), ashore E_NOT_ABOARD, at sea E_NOT_IN_PORT; with 10 charts she becomes B — 3 slots,
--     6 known, the 10 charts spent, and (lit) her extras lifted to B's floor; world.captains says what the next
--     grade needs.
-- (e) the re-cuts reverse; ACL / volatility / definer / config unmoved; +1 entry point; 0 client write grants.
--
-- ROLLBACK: a forward slice restoring the bodies from the hunks' OLD text and deleting the three items only after
-- asserting no player_items row holds one (a promotion a company paid for is never taken back).
-- VERSION: 0162 (S13 0158, S15 0159, K6 0160, K7 0161). Workshop hunk re-sliced after S15 (0159).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

create or replace function pg_temp.occurs_0162(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0162 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.workstation(uuid, uuid)'), ('cmd.resolve_item(text)'), ('voyage.settle(uuid, timestamp with time zone)'),
               ('cmd.do_buy(uuid, jsonb)'), ('cmd.do_sell(uuid, jsonb)'), ('world.captains()'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table hunks_0162 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0162 (fn, n, old, new) values
  ('world.workstation(uuid, uuid)', 1, $o0$                               public.made_only_in(k.code, p_port) as made_in) kn));   -- 0135: once per item (0159: and its city)$o0$, $n0$                               public.made_only_in(k.code, p_port) as made_in) kn
     where k.kind = 'fitting'));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made)$n0$),
  ('cmd.resolve_item(text)', 1, $o1$  select array_agg(code order by code) into v_hits from public.item_kinds
   where cmd.fold(code) = v_needle or cmd.fold(name) = v_needle;$o1$, $n1$  -- 0161: a fitting's name only — a promotion item is never made, fitted or unfitted
  select array_agg(code order by code) into v_hits from public.item_kinds
   where kind = 'fitting' and (cmd.fold(code) = v_needle or cmd.fold(name) = v_needle);$n1$),
  ('cmd.resolve_item(text)', 2, $o2$  select array_agg(code order by code) into v_hits from public.item_kinds
   where cmd.fold(code) like '%' || v_needle || '%' or cmd.fold(name) like '%' || v_needle || '%';$o2$, $n2$  select array_agg(code order by code) into v_hits from public.item_kinds
   where kind = 'fitting' and (cmd.fold(code) like '%' || v_needle || '%' or cmd.fold(name) like '%' || v_needle || '%');$n2$),
  ('voyage.settle(uuid, timestamp with time zone)', 1, $o3$      perform public.captain_xp_credit(p_fleet, x.exploration, 0, x.combat, v.departed_at)
         from public.voyage_xp_tracks(v.id) x;
$o3$, $n3$      perform public.captain_xp_credit(p_fleet, x.exploration, 0, x.combat, v.departed_at)
         from public.voyage_xp_tracks(v.id) x;
      -- 0161 (K8): and the company's promotion items, at the arrival port (anchored at sea, the points wait)
      perform public.promotion_credit(f.player_id, v.dest_port_id, 'exploration', x.exploration),
              public.promotion_credit(f.player_id, v.dest_port_id, 'combat', x.combat)
         from public.voyage_xp_tracks(v.id) x;
$n3$),
  ('cmd.do_buy(uuid, jsonb)', 1, $o4$  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
$o4$, $n4$  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
  -- 0161 (K8): and the company's Trade Seals, at this market's port (a merchant earns none)
  perform public.promotion_credit(f.player_id, f.port_id, 'trading', q.total / public.wc_num('fame_ducats_per_point'));
$n4$),
  ('cmd.do_sell(uuid, jsonb)', 1, $o5$  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
$o5$, $n5$  perform public.captain_xp_credit(p_fleet, 0, q.total / public.wc_num('fame_ducats_per_point'), 0);
  -- 0161 (K8): and the company's Trade Seals, at this market's port (a merchant earns none)
  perform public.promotion_credit(f.player_id, f.port_id, 'trading', q.total / public.wc_num('fame_ducats_per_point'));
$n5$),
  ('world.captains()', 1, $o6$      'homesick', case when st.home_seen_at is not null$o6$, $n6$      -- 0161 (K8): what her next promotion needs, and what you have where her ship lies (null at the top)
      'promote', public.promotion_next(po.id),
      'homesick', case when st.home_seen_at is not null$n6$),
  ('public.client_rpc_entry_points()', 1, $o7$      ('cmd',         'captain_traits_set',    'text, text[]')
$o7$, $n7$      ('cmd',         'captain_traits_set',    'text, text[]'),
      -- 0161: promote a captain (her ship docked, her level, the items in storage there) — K8.
      ('cmd',         'promote_captain',       'text')
$n7$);

create temp table before_0162 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.item_kinds) as items;

create temp table readers_before_0162 on commit drop as
select 'ws'::text as what, p.id::text as k, world.workstation(p.id, null)::text as v
  from public.ports p where exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'workstation')
union all
select 'item', k.name, cmd.resolve_item(k.name) from public.item_kinds k
union all
select 'crew', f.id::text || '/' || e.e, public.crew_pct(f.id, null, e.e)::text
  from public.fleets f cross join (values ('speed'), ('hold'), ('spread'), ('crew_saved')) e(e)
union all
select 'endure', f.id::text, voyage.endurance_days(f.id)::text from public.fleets f;

-- ── 2. THE CATALOGUE ──────────────────────────────────────────────────────────────────────────
alter table public.captain_grades add column if not exists promote_level int check (promote_level >= 1);
alter table public.captain_grades add column if not exists promote_items int check (promote_items >= 1);
update public.captain_grades g set promote_level = w.lvl, promote_items = w.items
  from (values
  ('C', null::int, null::int),
  ('B', 5::int, 10::int),
  ('A', 10::int, 20::int),
  ('S', 15::int, 40::int)
       ) w(code, lvl, items) where w.code = g.code;
comment on column public.captain_grades.promote_level is
  '0162 (D12): the level in her job''s focus a captain needs to RISE to this grade (null: a birth grade only). data/captains.json.';
comment on column public.captain_grades.promote_items is
  '0162 (D12): how many promotion items of her focus rising to this grade spends. data/captains.json.';

do $alter$
declare
  v_try int := 0; v_msg text; v_state text;
begin
  loop
    v_try := v_try + 1;
    begin
      alter table public.item_kinds add column if not exists kind text not null default 'fitting'
        constraint item_kinds_kind_known check (kind in ('fitting', 'promotion'));
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0162 self-assert FAIL: LOCK CONTENTION, not a result — item_kinds could not be altered in 5 tries (%: %). Re-run the push.', v_state, v_msg;
      end if;
      perform pg_sleep(0.5);
    end;
  end loop;
end $alter$;
comment on column public.item_kinds.kind is
  '0162: fitting (made at a workshop, mounted on a ship) or promotion (earned by your fleets, spent to promote a captain — never made nor fitted).';

insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier, kind) values
  ('sea-chart', 'Sea Chart', 'promotion', 'a promotion', 'nothing', 'A chart of waters your fleets have sailed: what promotes an exploration captain.', 0.01, 1, 'promotion'),
  ('trade-seal', 'Trade Seal', 'promotion', 'a promotion', 'nothing', 'A seal of trade your fleets have made: what promotes a trading captain.', 0.01, 1, 'promotion'),
  ('battle-honour', 'Battle Honour', 'promotion', 'a promotion', 'nothing', 'An honour for pirates your fleets have seen off: what promotes a combat captain.', 0.01, 1, 'promotion');

create table if not exists public.promotion_items (
  item_code text primary key references public.item_kinds(code),
  focus     text not null unique references public.trait_foci(code),
  points    numeric not null check (points > 0)
);
comment on table public.promotion_items is
  '0162 (D12): the promotion item of each focus and how many of your fleets'' points in that track earn one. '
  'data/captains.json, guard-held. Server-only.';
alter table public.promotion_items enable row level security;
revoke all on table public.promotion_items from public, anon, authenticated;
insert into public.promotion_items (item_code, focus, points) values
  ('sea-chart', 'exploration', 100),
  ('trade-seal', 'trading', 4850),
  ('battle-honour', 'combat', 100);

create table if not exists public.promotion_progress (
  player_id uuid not null references public.players(id) on delete cascade,
  focus     text not null references public.trait_foci(code),
  points    numeric not null default 0 check (points >= 0),
  primary key (player_id, focus)
);
comment on table public.promotion_progress is
  '0162: the points a company has banked toward its next promotion item, per track (the remainder below one '
  'item). Written only by public.promotion_credit. Server-only.';
alter table public.promotion_progress enable row level security;
revoke all on table public.promotion_progress from public, anon, authenticated;

-- ── 3. THE ONE WRITER AND THE VERB ──────────────────────────────────────────────────────────────
create or replace function public.promotion_credit(p_player uuid, p_port uuid, p_focus text, p_points numeric)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $pc$
-- 0162: THE ONE WRITER of promotion items. A PLAYER's company banks the points of a track; at a port, every
-- whole `promotion_items.points` becomes one item in storage there. A merchant returns at once (O8).
-- Returns the items made.
declare
  v_item text;
  v_per  numeric;
  v_now  numeric;
  v_n    int := 0;
begin
  if p_points is null or p_points <= 0
     or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  select pi.item_code, pi.points into v_item, v_per from public.promotion_items pi where pi.focus = p_focus;
  if v_item is null then
    return 0;
  end if;
  insert into public.promotion_progress (player_id, focus, points) values (p_player, p_focus, p_points)
  on conflict (player_id, focus) do update set points = public.promotion_progress.points + excluded.points
  returning points into v_now;
  if p_port is not null and v_now >= v_per then
    v_n := floor(v_now / v_per)::int;
    update public.promotion_progress set points = points - v_n * v_per where player_id = p_player and focus = p_focus;
    insert into public.player_items (player_id, port_id, item_code, qty) values (p_player, p_port, v_item, v_n)
    on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;
  end if;
  return v_n;
end $pc$;

create or replace function public.promotion_next(p_signing uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $pn$
-- 0162: WHAT HER NEXT PROMOTION NEEDS — the one reading the verb refuses by and the roster prints: the next
-- grade, the level it needs in her job's focus and hers, the item, how many, and how many you keep where her
-- ship is docked (null: ashore or at sea). Null at the top of the ladder.
declare
  v_off   uuid;
  v_focus text;
  v_now   record;
  v_next  record;
  v_item  record;
  v_port  uuid;
  v_have  int;
begin
  select po.officer_id, t.focus into v_off, v_focus
    from public.player_officers po join public.officers o on o.id = po.officer_id join public.traits t on t.code = o.specialty
   where po.id = p_signing;
  select g.* into v_now from public.captain_grades g
   where g.code = coalesce((select st.grade from public.captain_state st where st.player_officer_id = p_signing),
                           (select cp.grade from public.captain_profile cp where cp.officer_id = v_off));
  select g.* into v_next from public.captain_grades g where g.ord > v_now.ord order by g.ord limit 1;
  if v_next.code is null then
    return null;
  end if;
  select pi.item_code, k.name into v_item from public.promotion_items pi join public.item_kinds k on k.code = pi.item_code
   where pi.focus = v_focus;
  select f.port_id into v_port
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id join public.fleets f on f.id = s.fleet_id
   where cs.player_officer_id = p_signing and f.status = 'DOCKED';
  select coalesce(pi.qty, 0) into v_have from public.player_officers po
    left join public.player_items pi on pi.player_id = po.player_id and pi.port_id = v_port and pi.item_code = v_item.item_code
   where po.id = p_signing;
  return jsonb_build_object(
    'to', v_next.code, 'level_needed', v_next.promote_level, 'level', public.captain_level(p_signing, v_focus),
    'item', v_item.item_code, 'item_name', v_item.name, 'items_needed', v_next.promote_items,
    'items_here', case when v_port is not null then v_have end,
    'port', (select p.name from public.ports p where p.id = v_port),
    'line', format('Promote to %s · %s %ss · %s level %s', v_next.code, v_next.promote_items, v_item.name,
                   initcap(v_focus), v_next.promote_level));
end $pn$;

create or replace function public.promote_captain_for(p_player uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $pr$
-- 0162: CORE of cmd.promote_captain. Her ship docked; her level in her job's focus at least the next grade's;
-- the items in storage at that port. Spends them and raises her grade (captain_state). Server-only.
declare
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_po   uuid;
  v_name text;
  v_n    jsonb;
  v_at   record;
begin
  select po.id, o.name into v_po, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = p_player and o.code = v_code;
  if v_po is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'You do not keep that captain.', 'fixes', jsonb_build_array('(hire her at an inn first)'));
  end if;
  v_n := public.promotion_next(v_po);
  if v_n is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_TOP_GRADE',
      'error_message', format('%s stands at the top grade.', v_name), 'fixes', '[]'::jsonb);
  end if;
  select s.name as ship, f.status, f.port_id into v_at
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id join public.fleets f on f.id = s.fleet_id
   where cs.player_officer_id = v_po;
  if v_at.ship is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_ABOARD',
      'error_message', format('%s is ashore. She is promoted aboard her ship, in port, where the items are kept.', v_name),
      'fixes', jsonb_build_array('(seat her on a ship docked where your items are)'));
  end if;
  if v_at.status <> 'DOCKED' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_PORT',
      'error_message', format('%s is at sea aboard %s. A captain is promoted in port.', v_name, v_at.ship),
      'fixes', jsonb_build_array('(wait until her ship is docked)'));
  end if;
  if (v_n->>'level')::int < (v_n->>'level_needed')::int then
    return jsonb_build_object('ok', false, 'error_code', 'E_LEVEL_TOO_LOW',
      'error_message', format('%s needs %s level %s for %s: she is level %s.', v_name,
                              (select tf.word from public.trait_foci tf join public.promotion_items pi on pi.focus = tf.code
                                where pi.item_code = v_n->>'item'), v_n->>'level_needed', v_n->>'to', v_n->>'level'),
      'fixes', jsonb_build_array('(sail, trade or fight on in her track)'));
  end if;
  if coalesce((v_n->>'items_here')::int, 0) < (v_n->>'items_needed')::int then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_ENOUGH_ITEMS',
      'error_message', format('Needs %s %ss here: you have %s at %s.', v_n->>'items_needed', v_n->>'item_name',
                              coalesce(v_n->>'items_here', '0'), v_n->>'port'),
      'fixes', jsonb_build_array('(bring her where your items are kept)', '(earn more)'));
  end if;
  update public.player_items set qty = qty - (v_n->>'items_needed')::int
   where player_id = p_player and port_id = v_at.port_id and item_code = v_n->>'item';
  update public.captain_state set grade = v_n->>'to' where player_officer_id = v_po;
  return jsonb_build_object('ok', true, 'officer', v_code, 'grade', v_n->>'to',
    'sentence', format('%s is now a %s captain.', v_name, v_n->>'to'));
end $pr$;

create or replace function cmd.promote_captain(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $cp$
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  -- 0162: the promotion is public.promote_captain_for's.
  return public.promote_captain_for(v_player, p_code);
end $cp$;

revoke all on function public.promotion_credit(uuid, uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.promotion_next(uuid) from public, anon, authenticated;
revoke all on function public.promote_captain_for(uuid, text) from public, anon, authenticated;
revoke all on function cmd.promote_captain(text) from public, anon;
grant execute on function cmd.promote_captain(text) to authenticated;

-- ── 4. THE RE-CUTS ────────────────────────────────────────────────────────────────────────────
do $recut$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0162 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0162 where fn = d.fn order by n loop
      if pg_temp.occurs_0162(v_def, h.old) <> 1 then
        raise exception '0162 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against',
          h.n, d.fn, pg_temp.occurs_0162(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $recut$;

-- ── 5. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  b        record;
  d        record;
  h        record;
  v_p      record;
  v_def    text;
  v_bad    int;
  v_r      jsonb;
  v_player uuid;
  v_fleet  uuid;
  v_ship   uuid;
  v_lis    uuid;
  v_po     uuid;
  v_m      uuid;
  v_n      int;
  v_crew   jsonb := (select value from public.world_config where key = 'crew_bite');
  c_uid constant uuid := '00000000-0162-4000-8000-000000000001';
  c_off constant text := 'BERGENNAV';   -- a C navigator, 5 % (data/officers.json)
begin
  select * into b from before_0162;

  -- (a) THE CATALOGUE
  if (select count(*) from public.item_kinds) <> b.items + 3
     or (select count(*) from public.item_kinds where kind = 'promotion') <> 3
     or (select count(*) from public.promotion_items) <> 3
     or exists (select 1 from public.captain_grades where (promote_level is null) <> (ord = 1)) then
    raise exception '0162 self-assert FAIL: the promotion catalogue did not land whole';
  end if;

  -- (b) DARK = the pre-image
  select count(*) into v_bad from readers_before_0162 r
   where r.v is distinct from case r.what
           when 'ws'     then world.workstation(r.k::uuid, null)::text
           when 'item'   then cmd.resolve_item(r.k)
           when 'crew'   then public.crew_pct(split_part(r.k, '/', 1)::uuid, null, split_part(r.k, '/', 2))::text
           when 'endure' then voyage.endurance_days(r.k::uuid)::text end;
  if v_bad <> 0 then
    raise exception '0162 self-assert FAIL: % reader answer(s) moved (workshop / item names / crew / endurance)', v_bad;
  end if;
  if exists (select 1 from public.item_kinds k where k.kind = 'promotion'
              and exists (select 1 from jsonb_array_elements(world.workstation((select p.id from public.ports p
                            where exists (select 1 from public.port_buildings b2 where b2.port_id = p.id and b2.kind = 'workstation')
                            order by p.code limit 1), null)->'items') e where e->>'code' = k.code)) then
    raise exception '0162 self-assert FAIL: a promotion item is offered at a workshop';
  end if;

  -- (c) THE PROBE — own house, rolled back
  begin
    v_player := public.new_house(c_uid, 'Casa das Cartas', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_lis from public.ports where code = 'LIS';
    select s.id into v_ship from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc limit 1;
    perform public.credit(v_player, 'PROBE_PROMOTE', 50000,
      public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0162 self-assert')));
    -- the one writer: 250 points at Lisbon → 2 charts there, 50 banked; at sea 80 more → none, 130 banked
    -- (each credit is its own statement: a subquery in the same expression would read the snapshot before it)
    v_n := public.promotion_credit(v_player, v_lis, 'exploration', 250);
    if v_n <> 2
       or coalesce((select qty from public.player_items where player_id = v_player and port_id = v_lis and item_code = 'sea-chart'), -1) <> 2
       or coalesce((select points from public.promotion_progress where player_id = v_player and focus = 'exploration'), -1) <> 50 then
      raise exception '0162 self-assert FAIL: 250 points at Lisbon did not make 2 charts and bank 50 (made %)', v_n;
    end if;
    v_n := public.promotion_credit(v_player, null, 'exploration', 80);
    if v_n <> 0
       or coalesce((select points from public.promotion_progress where player_id = v_player and focus = 'exploration'), -1) <> 130 then
      raise exception '0162 self-assert FAIL: points earned at sea did not wait in the bank (made %)', v_n;
    end if;
    -- a merchant's company earns none
    v_m := public.new_house(null, 'Casa Sem Cartas', 'PRT', p_ducats => 20000, p_is_npc => true);
    v_n := public.promotion_credit(v_m, v_lis, 'exploration', 1000);
    if v_n <> 0 or exists (select 1 from public.promotion_progress where player_id = v_m) then
      raise exception '0162 self-assert FAIL: a merchant earned promotion items';
    end if;
    -- the verb: ashore, low level, too few items, at sea — then promoted
    v_r := public.sign_officer(v_player, c_off, null);
    select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id
     where po.player_id = v_player and o.code = c_off;
    v_r := public.promote_captain_for(v_player, c_off);
    if v_r->>'error_code' is distinct from 'E_NOT_ABOARD' then
      raise exception '0162 self-assert FAIL: a captain ashore was not refused E_NOT_ABOARD: %', v_r;
    end if;
    v_r := public.post_officer_to(v_player, c_off, v_fleet);
    update public.captain_xp set exploration = public.level_points(4) where player_officer_id = v_po;
    perform public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', 'LIS', 'total_nm', 50000000));
    v_r := public.promote_captain_for(v_player, c_off);
    if v_r->>'error_code' is distinct from 'E_LEVEL_TOO_LOW' then
      raise exception '0162 self-assert FAIL: a level-4 navigator was not refused E_LEVEL_TOO_LOW: %', v_r;
    end if;
    update public.captain_xp set exploration = public.level_points(5) where player_officer_id = v_po;
    perform public.promotion_credit(v_player, v_lis, 'exploration', 700);   -- 130 + 700 = 830 → 8 more: 10 at Lisbon
    update public.player_items set qty = 9 where player_id = v_player and port_id = v_lis and item_code = 'sea-chart';
    v_r := public.promote_captain_for(v_player, c_off);
    if v_r->>'error_code' is distinct from 'E_NOT_ENOUGH_ITEMS' or v_r->>'error_message' not like 'Needs 10 Sea Charts here: you have 9 at Lisbon%' then
      raise exception '0162 self-assert FAIL: nine charts were not refused with the figures: %', v_r;
    end if;
    update public.player_items set qty = 10 where player_id = v_player and port_id = v_lis and item_code = 'sea-chart';
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -12.0 where id = v_fleet;
    v_r := public.promote_captain_for(v_player, c_off);
    if v_r->>'error_code' is distinct from 'E_NOT_IN_PORT' then
      raise exception '0162 self-assert FAIL: a captain at sea was promoted: %', v_r;
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fleet;
    v_r := public.promote_captain_for(v_player, c_off);
    if not coalesce((v_r->>'ok')::boolean, false)
       or coalesce((select grade from public.captain_state where player_officer_id = v_po), '?') <> 'B'
       or coalesce((select qty from public.player_items where player_id = v_player and port_id = v_lis and item_code = 'sea-chart'), -1) <> 0 then
      raise exception '0162 self-assert FAIL: ten charts and level 5 did not make her B: %', v_r;
    end if;
    -- lit, her extras stand at least at B's floor; her job keeps its value
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    if exists (select 1 from public.crew_terms(v_fleet) x where x.player_officer_id = v_po
                 and x.value_pct < (select floor_pct from public.captain_grades where code = 'B')
                   * (select te.mult from public.trait_effects te where te.trait = x.trait and te.effect = x.effect)
                   * (case when public.cabin_focus((select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = x.ship_id), x.seat)
                            in ('captain', (select t.focus from public.traits t where t.code = x.trait)) then 1 else public.wc_num('cabin_off_focus_pct') / 100.0 end)) then
      raise exception '0162 self-assert FAIL: a promoted captain''s trait stands below B''s floor';
    end if;
    update public.world_config set value = v_crew where key = 'crew_bite';
    perform cmd.assume_identity(c_uid);
    if not exists (select 1 from jsonb_array_elements(world.captains()->'captains') c
                    where c->>'code' = c_off and c->'promote'->>'to' = 'A' and c->'promote'->>'line' like 'Promote to A · 20 Sea Charts%') then
      raise exception '0162 self-assert FAIL: the roster does not say what A needs: %', world.captains();
    end if;
    raise exception 'PROBE_ROLLBACK_0162';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0162' then raise; end if;
  end;
  if exists (select 1 from public.players where company_name in ('Casa das Cartas', 'Casa Sem Cartas'))
     or (select value from public.world_config where key = 'crew_bite') <> v_crew then
    raise exception '0162 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (e) THE RE-CUTS reverse
  for d in select * from defs_before_0162 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0162 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0162(v_def, h.new) <> 1 then
        raise exception '0162 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0162 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0162 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points + 1 then
    raise exception '0162 self-assert FAIL: the entry points are not the old ones + cmd.promote_captain';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
               cross join unnest(array['public.promotion_items', 'public.promotion_progress']) t(tab)
              where has_table_privilege(r.role, t.tab, 'select,insert,update,delete')) then
    raise exception '0162 self-assert FAIL: a client can read or write a promotion table';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0162 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;

  raise notice '0162 self-assert ok: A CAPTAIN IS PROMOTED FOR WHAT HER COMPANY HAS DONE (K8, DARK). % promotion items in the one item system (kind promotion; every fitting of today kind fitting, never made nor fitted as one), the gates B 5/10 · A 10/20 · S 15/40. DARK: % answers (every workshop, every item name, the live crew effects, endurance) equal their pre-images. The probe (rolled back): 250 points at Lisbon made 2 Sea Charts there and banked 50; points at sea waited; a merchant earned none; the verb refused a captain ashore, a level-4 one, nine charts with the figures and a captain at sea, then made a level-5 C navigator with ten charts a B (spent, and her traits at B''s floor, lit); the roster said what A needs. +1 entry point; 0 client write grants.',
    3, (select count(*) from readers_before_0162);
end $$;

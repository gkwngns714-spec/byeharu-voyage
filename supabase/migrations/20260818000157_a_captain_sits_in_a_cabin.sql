-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0157 — A CAPTAIN SITS IN A CABIN  (K5 "captains II": cabins, seats, the one reader — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §4.3, §4.4, §6.2 and §8 row K5 (research: docs/research/
-- UWO_SKILLS_AND_CAPTAINS.md §3.4, §3.5). The owner, row 68: *"Each ship will also have cabins that can
-- have captain. for tier 1 … 3 captain slot. it will grow as the tier of the ship grows"*; 2026-10-17:
-- the captains of 대항해시대 오리진, *"apply it to the game as well"*. D9 (the cabin layout, seats changed
-- only in port, no ship needs a captain) was approved by default — the owner may reverse it; it is data.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   THE CABINS      public.cabin_kinds (Captain's / Trade / Exploration / Combat cabin) and
--       public.cabin_rotation (the typed cabins' order by hull role, data/captains.json); seat 1 of every
--       ship is the Captain's cabin (public.cabin_focus — the ONE answer to "what is seat n of this
--       hull"); the count is class_cabins' (LIVE). The knob `cabin_off_focus_pct` 50: a trait off the
--       cabin's focus works at half (Origin's figure) — only while crew_bite is on.
--   THE SEATS       public.captain_seats (signing → ship, seat), public.captain_active (the traits a
--       signing uses), public.captain_state (a player's signing: grade, home clock — K6 reads the clock).
--       Seeded from player_officers.fleet_id: every posted signing seated in her fleet by the one picker
--       (public.captain_seat_pick: her job's cabin, else the Captain's cabin, else any free seat, flagship
--       first). Every one of today's lands in a cabin where her job works at 100 % (asserted, expected 0).
--   THE ONE READER  public.crew_terms(fleet) — every term a seated captain adds, dark or lit — and
--       public.crew_pct(fleet, ship, effect, good), which sums them, caps them at crew_effects.cap_pct
--       (new column; the four live effects carry the retired knob officer_bonus_cap_pct's 25) and
--       applies Command exactly as public.fleet_officer_bonus did. DARK (crew_bite off) it is that
--       function's arithmetic to the digit, over the seats: each seated captain's JOB at her value × her
--       level. LIT: every ACTIVE trait, × its effect's mult, × her level, × the cabin's rate, lifted to her
--       grade's floor only once she is promoted above her birth grade (K8; D12 — at birth the 60 % of D15
--       stands). world.crew_bonuses(fleet) is the display reading of the same terms.
--   THE RE-CUTS (hunks sliced from the bodies live after 0156, LF-normalised, each occurring once, each
--       reversing to its pre-image, ACLs unchanged): voyage.fleet_speed, public.ship_hold_capacity,
--       public.raid_crew_lost, world.spread_effective, voyage.settle (surgeon_pct; the experience credit
--       reads the seats), world.fleets (officer_pct from crew_pct, plus `crew`), world.officers (the
--       cap from crew_effects; where she sits from the seat), world.npc_fleet_card (a merchant fleet's
--       captains by seat), world.ship_view (+ `seats`), public.post_officer_to and public.sign_officer
--       (onto the seat core), public.client_rpc_entry_points (+ cmd.seat_captain).
--       public.fleet_officer_bonus is then DROPPED — no body names it (asserted).
--   THE VERB        cmd.seat_captain(code, ship, seat) → public.seat_captain_for: seat her (a cabin you
--       name, or the picker's), move her, or put her ashore (ship null). Only while the ship she leaves
--       and the ship she boards are docked (E_NOT_IN_PORT). Hiring with a fleet seats her in it, and the
--       fleet must be docked (the same rule); posting to a fleet seats her by the picker.
--
-- ── DARK: WHAT IT DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────────
-- Change any number while crew_bite is off: every fleet × the four live effects answers its pre-image,
-- skills dark AND lit (Command); so do fleet_speed, every ship's cargo space, raid losses and 400
-- sampled spreads. Lit (rolled back), every merchant fleet answers its pre-image too — her one active
-- trait is her job, in a cabin of its focus or the Captain's. No homesickness, levels by track,
-- languages or promotion (K6-K8). No new effect is read (storm, supplies, a trader's goods: K7).
-- cmd.captain_traits_set lands with the Captains roster that shows the traits (K6): a verb with no
-- screen is half a slice. Ship-scope effects (combat) raise until S4 gives them a reader (K10).
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) cabins: every hull class has a role in the rotation; seat 1 is the Captain's cabin everywhere.
-- (b) the seed: every posted signing seated on a ship of her fleet, at 100 % for her job; no seat twice;
--     merchants use their job only, players their first `slots` known traits and carry a state row.
-- (c) DARK = the pre-image: crew_pct for every fleet × the four effects (skills dark and lit), the six
--     readers' answers; LIT (crew_bite on, rolled back): every merchant fleet = its pre-image.
-- (d) THE PROBE (own throw-away houses, rolled back): a player hires an S navigator into her docked
--     fleet — seated in the Exploration cabin, her five first traits active, a state row; lit, her speed
--     is her value; moved to the Trade cabin it is half, to the Captain's cabin whole; at sea she cannot
--     be moved (E_NOT_IN_PORT); ashore she adds nothing; a merchant probe's captain uses her job only.
-- (e) the re-cuts reverse; ACL / volatility / definer / config unmoved; no body names
--     fleet_officer_bonus; entry points +1 (cmd.seat_captain); 0 client write grants.
-- (f) timing (notice only): the four effects over every fleet, old function vs crew_pct.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Pre-images first. `alter table public.crew_effects` (K4's table; read only by the card builder).
-- New tables; one index on public.ships (fleet_id) — SHARE on ships while it builds (~900 rows, milliseconds).
-- The re-cuts replace function bodies (no table lock). DROP FUNCTION
-- public.fleet_officer_bonus takes its own lock; nothing calls it after the re-cuts. Deploy with the
-- clock unwound (DEPLOY_RUNBOOK): unwind_the_clock() → db push → wind_the_clock().
--
-- ROLLBACK: a forward slice re-creating public.fleet_officer_bonus from this file's pre-image, the
-- re-cut bodies from their hunks' OLD text, the knob officer_bonus_cap_pct (25), and dropping the seat
-- tables (player_officers.fleet_id was kept written by every seating, so it is the same posting).
-- VERSION: 0157. Hunks sliced from PRODUCTION's live bodies at head 0156 (read-only pg_get_functiondef, 2026-10-18; equal to the chain's).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

create or replace function pg_temp.occurs_0157(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0157 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('voyage.fleet_speed(uuid)'), ('public.ship_hold_capacity(uuid)'), ('public.raid_crew_lost(uuid, numeric, numeric)'),
               ('world.spread_effective(uuid, uuid, uuid, boolean)'), ('voyage.settle(uuid, timestamp with time zone)'),
               ('world.fleets()'), ('world.officers()'), ('world.npc_fleet_card(uuid)'), ('world.ship_view(uuid)'),
               ('public.post_officer_to(uuid, text, uuid)'), ('public.sign_officer(uuid, text, uuid)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table untouched_before_0157 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('cmd.post_officer(text, uuid)'), ('cmd.hire_officer(text, uuid)'), ('public.captain_level_mult(uuid)'),
               ('public.house_skill_scopes(uuid, uuid)'), ('public.skill_scale(numeric, numeric)'), ('world.inn(uuid)'),
               ('world.captain_card(uuid)'), ('public.npc_found(jsonb)')) f(fn);

create temp table hunks_0157 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0157 (fn, n, old, new) values
  ('voyage.fleet_speed(uuid)', 1, $o0$  -- 0015: the navigators aboard — a fact about the FLEET. Zero when there are none.
  v_nav := public.fleet_officer_bonus(p_fleet, 'NAVIGATOR');$o0$, $n0$  -- 0015 / 0157: the captains seated in the fleet, for speed (public.crew_pct, the one reader) — a fact
  -- about the FLEET. Zero when there are none.
  v_nav := public.crew_pct(p_fleet, null, 'speed');$n0$),
  ('voyage.fleet_speed(uuid)', 2, $o1$the two are separately capped (officer_bonus_cap_pct and$o1$, $n1$the two are separately capped (crew_effects.cap_pct and$n1$),
  ('public.ship_hold_capacity(uuid)', 1, $o2$  -- fleet_officer_bonus (0015) is the ONLY reading of what officers are worth: it sums within the
  -- specialty and clamps at officer_bonus_cap_pct. Nothing here sums bonus_pct itself.$o2$, $n2$  -- public.crew_pct (0157; it replaced 0015's fleet_officer_bonus) is the ONLY reading of what the
  -- captains are worth: it sums their terms and clamps at crew_effects.cap_pct. Nothing here sums a value itself.$n2$),
  ('public.ship_hold_capacity(uuid)', 2, $o3$(1 + public.fleet_officer_bonus(s.fleet_id, 'QUARTERMASTER'))$o3$, $n3$(1 + public.crew_pct(s.fleet_id, s.id, 'hold'))$n3$),
  ('public.raid_crew_lost(uuid, numeric, numeric)', 1, $o4$public.fleet_officer_bonus(p_fleet, 'SURGEON')$o4$, $n4$public.crew_pct(p_fleet, null, 'crew_saved')$n4$),
  ('world.spread_effective(uuid, uuid, uuid, boolean)', 1, $o5$    v_purser := public.fleet_officer_bonus(p_fleet, 'PURSER');$o5$, $n5$    v_purser := public.crew_pct(p_fleet, null, 'spread', p_good);   -- 0157: the captains, through the one reader$n5$),
  ('voyage.settle(uuid, timestamp with time zone)', 1, $o6$round(public.fleet_officer_bonus(p_fleet, 'SURGEON') * 100, 2)$o6$, $n6$round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2)$n6$),
  ('voyage.settle(uuid, timestamp with time zone)', 2, $o7$      select po.id, public.voyage_xp(v.id) from public.player_officers po
       where po.fleet_id = p_fleet
$o7$, $n7$      select po.id, public.voyage_xp(v.id) from public.player_officers po
       -- 0157: the captains SEATED in her ships (seats change only in port, so these sailed with her)
       join public.captain_seats cs on cs.player_officer_id = po.id
       join public.ships sh2 on sh2.id = cs.ship_id
       where sh2.fleet_id = p_fleet
$n7$),
  ('world.fleets()', 1, $o8$    'officer_pct', jsonb_build_object(
        'NAVIGATOR',     round(public.fleet_officer_bonus(f.id, 'NAVIGATOR')     * 100, 2),
        'QUARTERMASTER', round(public.fleet_officer_bonus(f.id, 'QUARTERMASTER') * 100, 2),
        'SURGEON',       round(public.fleet_officer_bonus(f.id, 'SURGEON')       * 100, 2),
        'PURSER',        round(public.fleet_officer_bonus(f.id, 'PURSER')        * 100, 2)),
$o8$, $n8$    'officer_pct', jsonb_build_object(   -- 0157: through public.crew_pct, the one reader
        'NAVIGATOR',     round(public.crew_pct(f.id, null, 'speed')      * 100, 2),
        'QUARTERMASTER', round(public.crew_pct(f.id, null, 'hold')       * 100, 2),
        'SURGEON',       round(public.crew_pct(f.id, null, 'crew_saved') * 100, 2),
        'PURSER',        round(public.crew_pct(f.id, null, 'spread')     * 100, 2)),
    -- 0157: what the captains add, by source, in the server's words (world.crew_bonuses)
    'crew', world.crew_bonuses(f.id),
$n8$),
  ('world.officers()', 1, $o9$    'bonus_cap_pct', public.wc_num('officer_bonus_cap_pct'),$o9$, $n9$    'bonus_cap_pct', (select max(ce.cap_pct) from public.crew_effects ce where ce.live),   -- 0157: the cap is crew_effects'$n9$),
  ('world.officers()', 2, $o10$               'fleet', f.name,
$o10$, $n10$               'fleet', f.name,
               -- 0157: where she sits — the ship and the cabin (null ashore)
               'ship', sh.name,
               'seat', cs.seat,
$n10$),
  ('world.officers()', 3, $o11$        left join public.fleets f on f.id = po.fleet_id));$o11$, $n11$        -- 0157: where she sits is her seat's (captain_seats → ship → fleet)
        left join public.captain_seats cs on cs.player_officer_id = po.id
        left join public.ships sh on sh.id = cs.ship_id
        left join public.fleets f on f.id = sh.fleet_id));$n11$),
  ('world.npc_fleet_card(uuid)', 1, $o12$                  where po.player_id = p.id and po.fleet_id = f.id),$o12$, $n12$                  where po.player_id = p.id   -- 0157: the captains seated in her ships
                    and exists (select 1 from public.captain_seats cs join public.ships sh on sh.id = cs.ship_id
                                 where cs.player_officer_id = po.id and sh.fleet_id = f.id)),$n12$),
  ('world.ship_view(uuid)', 1, $o13$           'cabins', (select cabins from public.class_cabins where class_code = c.code))$o13$, $n13$           'cabins', (select cabins from public.class_cabins where class_code = c.code),
           -- 0157: who sits in which cabin (world.ship_seats)
           'seats', world.ship_seats(s.id))$n13$),
  ('public.post_officer_to(uuid, text, uuid)', 1, $o14$  v_n      int;
begin$o14$, $n14$  v_n      int;
  v_po     uuid;    -- 0157
  v_pick   record;
  v_res    jsonb;
begin$n14$),
  ('public.post_officer_to(uuid, text, uuid)', 2, $o15$  update public.player_officers set fleet_id = p_fleet
   where player_id = v_player and officer_id = v_off;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'That officer does not serve this house.',
      'fixes', jsonb_build_array('(hire them first)'));
  end if;

  -- 0127: WHEN SHE CAME ABOARD. A voyage teaches only the officers aboard when it departed
  -- (voyage.settle reads this): moved onto a fleet at sea, she earns nothing from that passage.
  insert into public.officer_xp (player_officer_id, aboard_since)
  select po.id, now() from public.player_officers po where po.player_id = v_player and po.officer_id = v_off
  on conflict (player_officer_id) do update set aboard_since = excluded.aboard_since;

  return jsonb_build_object('ok', true, 'officer', v_code, 'fleet', p_fleet);$o15$, $n15$  -- 0157: POSTING IS SEATING. Ashore (no fleet), or a cabin in that fleet chosen by the one picker
  -- (public.captain_seat_pick), written by the one seat core — and only in port, like every seating
  -- (public.seat_captain_for). Her experience clock (officer_xp.aboard_since) is the seat core's to set.
  select po.id into v_po from public.player_officers po where po.player_id = v_player and po.officer_id = v_off;
  if v_po is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'That officer does not serve this house.',
      'fixes', jsonb_build_array('(hire them first)'));
  end if;
  if p_fleet is null then
    v_res := public.seat_captain_for(v_player, v_code, null);
  else
    select * into v_pick from public.captain_seat_pick(v_po, p_fleet);
    if v_pick.ship_id is null then
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_CABIN',
        'error_message', 'Every cabin in that fleet is taken.',
        'fixes', jsonb_build_array('(put a captain ashore first)'));
    end if;
    v_res := public.seat_captain_for(v_player, v_code, v_pick.ship_id, v_pick.seat);
  end if;
  if not coalesce((v_res->>'ok')::boolean, false) then
    return v_res;
  end if;

  return jsonb_build_object('ok', true, 'officer', v_code, 'fleet', p_fleet);$n15$),
  ('public.sign_officer(uuid, text, uuid)', 1, $o16$  v_id     uuid;
begin$o16$, $n16$  v_id     uuid;
  v_npc    boolean;   -- 0157
  v_pick   record;
begin$n16$),
  ('public.sign_officer(uuid, text, uuid)', 2, $o17$  select ducats into v_purse from public.players where id = v_player;
$o17$, $n17$  -- 0157: HIRED INTO A FLEET IS SEATED IN IT — so that fleet must be docked (D9: captains change ships
  -- only in port), said before anything is paid.
  if p_fleet is not null and (select f3.status from public.fleets f3 where f3.id = p_fleet) is distinct from 'DOCKED' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_PORT',
      'error_message', 'That fleet is at sea. A captain joins a fleet only in port.',
      'fixes', jsonb_build_array('(hire her ashore, or name a fleet docked here)'));
  end if;

  select ducats into v_purse from public.players where id = v_player;
$n17$),
  ('public.sign_officer(uuid, text, uuid)', 3, $o18$  returning id into v_id;
$o18$, $n18$  returning id into v_id;

  -- 0157: what she USES — a merchant's captain her job alone (O8: fixed), a player's her first `slots`
  -- known traits — a player's state row, and, hired into a fleet, her seat by the one picker.
  select pl.is_npc into v_npc from public.players pl where pl.id = v_player;
  insert into public.captain_active (player_officer_id, trait)
  select v_id, ct.trait
    from public.captain_profile cp
    join public.captain_grades g on g.code = cp.grade
    join public.captain_traits ct on ct.officer_id = cp.officer_id
   where cp.officer_id = v_off.id and (case when v_npc then ct.ord = 1 else ct.ord <= g.slots end);
  if not v_npc then
    insert into public.captain_state (player_officer_id, grade, home_seen_at)
    select v_id, cp.grade, now() from public.captain_profile cp where cp.officer_id = v_off.id;
  end if;
  if p_fleet is not null then
    select * into v_pick from public.captain_seat_pick(v_id, p_fleet);
    if v_pick.ship_id is null then
      delete from public.player_officers where id = v_id;   -- her active traits and state go with her
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_CABIN',
        'error_message', 'Every cabin in that fleet is taken.',
        'fixes', jsonb_build_array('(put a captain ashore first, or hire her ashore)'));
    end if;
    perform public.captain_seat_put(v_id, v_pick.ship_id, v_pick.seat, not v_npc);
  end if;
$n18$),
  ('public.client_rpc_entry_points()', 1, $o19$      ('world',       'nation_standings',      '')
$o19$, $n19$      ('world',       'nation_standings',      ''),
      -- 0157: seat a captain in a cabin, move her, or put her ashore (docs/SKILLS_AND_CAPTAINS.md K5).
      ('cmd',         'seat_captain',          'text, uuid, int')
$n19$);

-- what every company's captains are worth today, every fleet × the four live jobs, skills dark and lit
create temp table bonus_before_0157 (fleet_id uuid, sp text, effect text, dark numeric, lit numeric, npc boolean) on commit drop;
do $pre$
declare
  v_skills jsonb := (select value from public.world_config where key = 'skills_bite');
  t0       timestamptz;
begin
  insert into bonus_before_0157 (fleet_id, sp, effect, dark, npc)
  select f.id, s.sp, s.effect, public.fleet_officer_bonus(f.id, s.sp), pl.is_npc
    from public.fleets f join public.players pl on pl.id = f.player_id
   cross join (values ('NAVIGATOR', 'speed'), ('QUARTERMASTER', 'hold'), ('PURSER', 'spread'), ('SURGEON', 'crew_saved')) s(sp, effect);
  update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
  update bonus_before_0157 b set lit = public.fleet_officer_bonus(b.fleet_id, b.sp);
  update public.world_config set value = v_skills where key = 'skills_bite';
  -- the old reader's time, a second pass (notice only; compared with crew_pct's at the end)
  t0 := clock_timestamp();
  perform public.fleet_officer_bonus(x.fleet_id, x.sp) from bonus_before_0157 x;
  create temp table time_before_0157 on commit drop as select extract(epoch from clock_timestamp() - t0) * 1000 as ms;
end $pre$;

-- the six readers' answers, on every fleet / ship and 400 sampled quotes
create temp table readers_before_0157 on commit drop as
select 'speed'::text as what, f.id::text as k, voyage.fleet_speed(f.id)::text as v
  from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id)
union all
select 'hold', s.id::text, public.ship_hold_capacity(s.id)::text from public.ships s
union all
select 'raid', f.id::text, public.raid_crew_lost(f.id, 120, 0.15)::text from public.fleets f
union all
select 'spread', q.port_id::text || '/' || q.good_id::text || '/' || q.fleet_id::text,
       world.spread_effective(q.port_id, q.good_id, q.fleet_id, false)::text
  from (select f.id as fleet_id, p.id as port_id, g.id as good_id
          from (select id from public.fleets order by md5(id::text || '0157f') limit 100) f
         cross join (select id from public.ports where kind = 'HARBOUR' order by md5(id::text || '0157p') limit 2) p
         cross join (select id from public.goods order by md5(id::text || '0157g') limit 2) g) q;

create temp table before_0157 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       public.wc_num('officer_bonus_cap_pct') as cap,
       (select count(*) from public.player_officers where fleet_id is not null) as posted;

-- ── 2. THE CATALOGUE GROWS: caps, cabins, two knobs ─────────────────────────────────────────────
alter table public.crew_effects add column if not exists cap_pct numeric;
update public.crew_effects c set cap_pct = w.cap
  from (values
  ('speed', 25),
  ('hold', 25),
  ('spread', 25),
  ('crew_saved', 25),
  ('homesick_relief', 20),
  ('storm', 25),
  ('supplies', 25),
  ('category_spread', 20),
  ('accuracy', 25),
  ('reach', 25),
  ('attack', 25)
       ) w(code, cap) where w.code = c.code;
do $cap$
begin
  if exists (select 1 from public.crew_effects where cap_pct is null) then
    raise exception '0157 self-assert FAIL: an effect has no cap';
  end if;
  if exists (select 1 from public.crew_effects ce cross join before_0157 b where ce.live and ce.cap_pct <> b.cap) then
    raise exception '0157 self-assert FAIL: a live effect''s cap is not the retired knob''s % — dark would move', (select cap from before_0157);
  end if;
end $cap$;
alter table public.crew_effects alter column cap_pct set not null;
alter table public.crew_effects add constraint crew_effects_cap_pct_check check (cap_pct > 0 and cap_pct <= 100);
comment on column public.crew_effects.cap_pct is
  '0157: the most a fleet gains from this effect, in per cent (category_spread: per goods category). Read by '
  'public.crew_pct, the one reader; it retired the knob officer_bonus_cap_pct (the four live effects keep its 25).';

create table if not exists public.cabin_kinds (
  code text primary key check (code in ('captain', 'trading', 'exploration', 'combat')),
  word text not null,
  ord  int  not null unique
);
comment on table public.cabin_kinds is
  '0157: the four cabins (D9): the Captain''s cabin (seat 1, every trait at 100 %) and the three typed ones. '
  'Authored in data/captains.json. Server-only.';
alter table public.cabin_kinds enable row level security;
revoke all on table public.cabin_kinds from public, anon, authenticated;

create table if not exists public.cabin_rotation (
  role  text not null check (role in ('trade', 'explorer', 'support', 'combat')),
  ord   int  not null check (ord >= 1),
  focus text not null references public.cabin_kinds(code) check (focus <> 'captain'),
  primary key (role, ord)
);
comment on table public.cabin_rotation is
  '0157: the typed cabins of a hull of this role, in turn from seat 2 (D9). Authored in data/captains.json. Server-only.';
alter table public.cabin_rotation enable row level security;
revoke all on table public.cabin_rotation from public, anon, authenticated;

insert into public.cabin_kinds (code, word, ord) values
  ('captain', 'Captain''s cabin', 1),
  ('trading', 'Trade cabin', 2),
  ('exploration', 'Exploration cabin', 3),
  ('combat', 'Combat cabin', 4);
insert into public.cabin_rotation (role, ord, focus) values
  ('trade', 1, 'trading'),
  ('trade', 2, 'exploration'),
  ('trade', 3, 'combat'),
  ('explorer', 1, 'exploration'),
  ('explorer', 2, 'trading'),
  ('explorer', 3, 'combat'),
  ('support', 1, 'exploration'),
  ('support', 2, 'trading'),
  ('support', 3, 'combat'),
  ('combat', 1, 'combat'),
  ('combat', 2, 'trading'),
  ('combat', 3, 'exploration');

insert into public.world_config (key, value, description) values
  ('crew_bite', 'false'::jsonb,
   '0157 (K5): when true, public.crew_pct counts every ACTIVE trait of every seated captain at its cabin''s rate '
   '(docs/SKILLS_AND_CAPTAINS.md §4.4). False: exactly the old officer arithmetic — each seated captain''s job '
   'at her value × her level. One UPDATE either way.'),
  ('cabin_off_focus_pct', to_jsonb(50),
   '0157 (D9): what a trait off its cabin''s focus is worth there, in per cent of itself (Origin: 50). Read only '
   'while crew_bite is on.')
on conflict (key) do nothing;

-- the old cap is now crew_effects.cap_pct (asserted equal above): one number, one place
delete from public.world_config where key = 'officer_bonus_cap_pct';

-- ── 3. THE SEATS ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.captain_seats (
  player_officer_id uuid primary key references public.player_officers(id) on delete cascade,
  ship_id           uuid not null references public.ships(id) on delete cascade,
  seat              int  not null check (seat >= 1),
  unique (ship_id, seat)
);
-- a fleet's ships, by fleet: the one reader walks fleet → ships → seats on every call (measured on the cached
-- world: crew_pct over every fleet × 4 effects 383 → 113 ms with it; the old reader, on player_officers'
-- own fleet index, 65 ms). Many bodies filter ships by fleet_id; all of them gain.
create index if not exists ships_fleet_id on public.ships (fleet_id);

comment on table public.captain_seats is
  '0157: where a signing sits — one seat per signing, one signing per seat. Written only by '
  'public.captain_seat_put (through seat_captain_for, sign_officer and post_officer_to). A lost ship puts her '
  'captains ashore (the row goes; the signing stays). player_officers.fleet_id is kept equal to the seat''s fleet '
  'on every write, read by nothing, and dropped in K9. Server-only.';
alter table public.captain_seats enable row level security;
revoke all on table public.captain_seats from public, anon, authenticated;

create table if not exists public.captain_active (
  player_officer_id uuid not null references public.player_officers(id) on delete cascade,
  trait             text not null references public.traits(code),
  primary key (player_officer_id, trait)
);
comment on table public.captain_active is
  '0157: the traits a signing USES (up to her grade''s slots, among the ones she knows). A merchant''s captain uses '
  'her job only (O8: fixed). Read by public.crew_terms while crew_bite is on. Server-only.';
alter table public.captain_active enable row level security;
revoke all on table public.captain_active from public, anon, authenticated;

create table if not exists public.captain_state (
  player_officer_id uuid primary key references public.player_officers(id) on delete cascade,
  grade             text not null references public.captain_grades(code),
  home_seen_at      timestamptz not null
);
comment on table public.captain_state is
  '0157: a PLAYER''s signing — her grade now (promotion, K8) and when her fleet last docked in her home region '
  '(homesickness, K6). A merchant''s captain has none: fixed (O8). Server-only.';
alter table public.captain_state enable row level security;
revoke all on table public.captain_state from public, anon, authenticated;

-- ── 4. THE ONE ANSWERS ─────────────────────────────────────────────────────────────────────────
create or replace function public.crew_bite_on()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce((select value = 'true'::jsonb from public.world_config where key = 'crew_bite'), false) $$;

create or replace function public.cabin_focus(p_class text, p_seat int)
returns text
language sql
stable
set search_path = public, pg_temp
as $cf$
  -- 0157: THE ONE answer to "what is seat n of this hull" (D9): seat 1 the Captain's cabin, then the
  -- hull role's typed cabins in turn. Null for a seat the hull does not have.
  select case when p_seat = 1 then 'captain'
              else (select r.focus from public.cabin_rotation r
                     where r.role = cp.role
                       and r.ord = ((p_seat - 2) % (select count(*) from public.cabin_rotation r2 where r2.role = cp.role)) + 1) end
    from public.class_profile cp
    join public.class_cabins cc on cc.class_code = cp.class_code
   where cp.class_code = p_class and p_seat between 1 and cc.cabins
$cf$;

create or replace function public.crew_terms(p_fleet uuid)
returns table (player_officer_id uuid, officer_id uuid, ship_id uuid, seat int, trait text, effect text, value_pct numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $ct$
-- 0157: EVERY TERM the captains seated in this fleet add, effect by effect, in per cent — the one
-- arithmetic public.crew_pct sums and world.crew_bonuses lists (docs/SKILLS_AND_CAPTAINS.md §4.4).
-- DARK (crew_bite off): each seated captain's JOB (officers.specialty), at her value × her level,
-- for a live effect only — public.fleet_officer_bonus's arithmetic over the seats. LIT: every ACTIVE
-- trait × its effect's mult × her level × her cabin's rate, lifted to her grade's floor only once she
-- stands above her birth grade (K8).
declare
  v_off numeric;
begin
  if not public.crew_bite_on() then
    return query
      select po.id, po.officer_id, cs.ship_id, cs.seat, o.specialty, te.effect,
             o.bonus_pct * public.captain_level_mult(po.id)
        from public.ships s
        join public.captain_seats cs on cs.ship_id = s.id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.officers o on o.id = po.officer_id
        join public.trait_effects te on te.trait = o.specialty
        join public.crew_effects ce on ce.code = te.effect and ce.live
       where s.fleet_id = p_fleet;
    return;
  end if;
  v_off := public.wc_num('cabin_off_focus_pct') / 100.0;
  return query
    select po.id, po.officer_id, cs.ship_id, cs.seat, ca.trait, te.effect,
           greatest(ct.base_pct, case when gs.ord > gb.ord then gs.floor_pct else 0 end)
           * te.mult * public.captain_level_mult(po.id)
           * case when x.cabin in ('captain', t.focus) then 1 else v_off end
      from public.ships s
      join public.captain_seats cs on cs.ship_id = s.id
      join public.ship_classes c on c.id = s.class_id
      cross join lateral (select public.cabin_focus(c.code, cs.seat) as cabin) x
      join public.player_officers po on po.id = cs.player_officer_id
      join public.captain_active ca on ca.player_officer_id = po.id
      join public.captain_traits ct on ct.officer_id = po.officer_id and ct.trait = ca.trait
      join public.traits t on t.code = ca.trait
      join public.trait_effects te on te.trait = ca.trait
      join public.captain_profile cp on cp.officer_id = po.officer_id
      join public.captain_grades gb on gb.code = cp.grade
      left join public.captain_state st on st.player_officer_id = po.id
      -- a merchant's captain has no state row: she stands at her birth grade for ever (O8), said here
      join public.captain_grades gs on gs.code = coalesce(st.grade, cp.grade)
     where s.fleet_id = p_fleet;
end $ct$;

create or replace function public.crew_pct(p_fleet uuid, p_ship uuid, p_effect text, p_good uuid default null)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $cp$
-- 0157: THE ONE READER of what the captains give (docs/SKILLS_AND_CAPTAINS.md §4.4), a fraction:
-- the sum of public.crew_terms for this effect, capped at crew_effects.cap_pct, and — while
-- skills_bite is on, for a company holding a house-scope skill — lifted by Command
-- (public.skill_scale), still under the cap: public.fleet_officer_bonus's order, step for step.
-- p_ship is for a ship-scope effect (combat, read from S4 — refused until then); p_good for a
-- goods trader's effect (K7).
declare
  v_scope  text;
  v_cap    numeric;
  v_sum    numeric;
  v_player uuid;
begin
  select ce.scope, ce.cap_pct into v_scope, v_cap from public.crew_effects ce where ce.code = p_effect;
  if v_scope is null then
    raise exception 'E_NO_SUCH_EFFECT: % is not a crew effect', p_effect using errcode = 'P0001';
  end if;
  if v_scope <> 'fleet' then
    raise exception 'E_NOT_YET: % is a ship effect, read only when combat arrives (S4, K10)', p_effect using errcode = 'P0001';
  end if;
  select coalesce(sum(t.value_pct), 0) into v_sum from public.crew_terms(p_fleet) t where t.effect = p_effect;
  if v_sum = 0 or not public.skills_bite_on() then
    return least(v_sum, v_cap) / 100.0;
  end if;
  select fl.player_id into v_player from public.fleets fl where fl.id = p_fleet;
  if not ('house' = any(public.house_skill_scopes(v_player))) then
    return least(v_sum, v_cap) / 100.0;
  end if;
  return least(public.skill_scale(v_sum, world.skill_pct(v_player, null, 'officer_bonus')), v_cap) / 100.0;
end $cp$;

comment on function public.crew_pct(uuid, uuid, text, uuid) is
  '0157: what the captains give a fleet for one effect, as a fraction (docs/SKILLS_AND_CAPTAINS.md §4.4). The one '
  'reader: voyage.fleet_speed, ship_hold_capacity, raid_crew_lost, spread_effective, settle, world.fleets.';

-- ── 5. THE SEAT CORE ──────────────────────────────────────────────────────────────────────────
create or replace function public.captain_seat_pick(p_signing uuid, p_fleet uuid, p_ship uuid default null)
returns table (ship_id uuid, seat int)
language sql
stable
security definer
set search_path = public, pg_temp
as $pk$
  -- 0157: THE ONE picker — a free seat for her in this fleet (or on this ship): a cabin of her job's
  -- focus, else the Captain's cabin, else any free seat; the flagship first, then by name.
  select s.id, n.seat
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
    join public.class_cabins cc on cc.class_code = c.code
   cross join lateral generate_series(1, cc.cabins) n(seat)
    join public.player_officers po on po.id = p_signing
    join public.officers o on o.id = po.officer_id
    join public.traits t on t.code = o.specialty
   where (case when p_ship is not null then s.id = p_ship else s.fleet_id = p_fleet end)
     and not exists (select 1 from public.captain_seats x where x.ship_id = s.id and x.seat = n.seat
                       and x.player_officer_id <> p_signing)
   order by case public.cabin_focus(c.code, n.seat) when t.focus then 0 when 'captain' then 1 else 2 end,
            s.is_flagship desc, s.name, s.id, n.seat
   limit 1
$pk$;

create or replace function public.captain_seat_put(p_signing uuid, p_ship uuid, p_seat int, p_came_aboard boolean default true)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $pt$
-- 0157: THE ONE WRITER of where a captain sits. Ship null = ashore. player_officers.fleet_id is kept
-- equal to the seat's fleet (read by nothing since 0157; dropped in K9). When she comes aboard, her
-- officer_xp.aboard_since is now (0127: a voyage teaches only the captains aboard when it departed).
begin
  if p_ship is null then
    delete from public.captain_seats where player_officer_id = p_signing;
    update public.player_officers set fleet_id = null where id = p_signing;
    return;
  end if;
  insert into public.captain_seats (player_officer_id, ship_id, seat) values (p_signing, p_ship, p_seat)
  on conflict (player_officer_id) do update set ship_id = excluded.ship_id, seat = excluded.seat;
  update public.player_officers po set fleet_id = s.fleet_id from public.ships s where s.id = p_ship and po.id = p_signing;
  if p_came_aboard then
    insert into public.officer_xp (player_officer_id, aboard_since) values (p_signing, now())
    on conflict (player_officer_id) do update set aboard_since = excluded.aboard_since;
  end if;
end $pt$;

create or replace function public.seat_captain_for(p_player uuid, p_code text, p_ship uuid, p_seat int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $sc$
-- 0157: CORE of cmd.seat_captain — seat a captain you keep in a cabin of a ship you own, move her, or
-- put her ashore (ship null). Only in port: the ship she leaves and the ship she boards must both be
-- docked (D9), so whoever sails from a port is the crew that arrives. A cabin you name must exist and be
-- free; none named, the one picker chooses. Server-only.
declare
  v_code   text := upper(btrim(coalesce(p_code, '')));
  v_po     uuid;
  v_name   text;
  v_now    record;
  v_ship   record;
  v_seat   int := p_seat;
begin
  select po.id, o.name into v_po, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = p_player and o.code = v_code;
  if v_po is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'You do not keep that captain.', 'fixes', jsonb_build_array('(hire her at an inn first)'));
  end if;
  select s.name as ship, f.status, f.name as fleet into v_now
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id join public.fleets f on f.id = s.fleet_id
   where cs.player_officer_id = v_po;
  if v_now.ship is not null and v_now.status <> 'DOCKED' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_PORT',
      'error_message', format('%s is at sea aboard %s. Captains change ships only in port.', v_name, v_now.ship),
      'fixes', jsonb_build_array('(wait until her ship is docked)'));
  end if;
  if p_ship is null then
    perform public.captain_seat_put(v_po, null, null);
    return jsonb_build_object('ok', true, 'officer', v_code, 'ship', null, 'seat', null,
      'sentence', format('%s is ashore.', v_name));
  end if;
  select s.id, s.name, s.player_id, f.status, c.code as class_code, cc.cabins into v_ship
    from public.ships s join public.fleets f on f.id = s.fleet_id
    join public.ship_classes c on c.id = s.class_id join public.class_cabins cc on cc.class_code = c.code
   where s.id = p_ship;
  if v_ship.id is null or v_ship.player_id is distinct from p_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_SHIP',
      'error_message', 'That ship is not yours.', 'fixes', jsonb_build_array('(name one of your own ships)'));
  end if;
  if v_ship.status <> 'DOCKED' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_PORT',
      'error_message', format('%s is at sea. Captains board only in port.', v_ship.name),
      'fixes', jsonb_build_array('(wait until she is docked)'));
  end if;
  if v_seat is null then
    select pk.seat into v_seat from public.captain_seat_pick(v_po, null, p_ship) pk;
    if v_seat is null then
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_CABIN',
        'error_message', format('Every cabin of %s is taken (%s).', v_ship.name, v_ship.cabins),
        'fixes', jsonb_build_array('(put a captain ashore first)'));
    end if;
  elsif v_seat < 1 or v_seat > v_ship.cabins then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_CABIN',
      'error_message', format('%s has %s cabins.', v_ship.name, v_ship.cabins), 'fixes', '[]'::jsonb);
  elsif exists (select 1 from public.captain_seats x where x.ship_id = p_ship and x.seat = v_seat and x.player_officer_id <> v_po) then
    return jsonb_build_object('ok', false, 'error_code', 'E_CABIN_TAKEN',
      'error_message', format('That cabin of %s is taken.', v_ship.name),
      'fixes', jsonb_build_array('(choose a free cabin, or put her captain ashore)'));
  end if;
  perform public.captain_seat_put(v_po, p_ship, v_seat);
  return jsonb_build_object('ok', true, 'officer', v_code, 'ship', p_ship, 'seat', v_seat,
    'sentence', format('%s sits in the %s of %s.', v_name,
                       (select k.word from public.cabin_kinds k where k.code = public.cabin_focus(v_ship.class_code, v_seat)),
                       v_ship.name));
end $sc$;

create or replace function cmd.seat_captain(p_code text, p_ship uuid, p_seat int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $cs$
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN',
      'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  -- 0157: the seating is public.seat_captain_for's.
  return public.seat_captain_for(v_player, p_code, p_ship, p_seat);
end $cs$;

-- ── 6. THE DISPLAY READS ──────────────────────────────────────────────────────────────────────
create or replace function world.ship_seats(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $ss$
  -- 0157: HER CABINS, seat by seat: the cabin's word, and who sits there — her grade, job and what her
  -- job is worth in that cabin (100 / 50), which counts once crew_bite is on (`rates_in_use`).
  select jsonb_build_object(
    'rates_in_use', public.crew_bite_on(),
    'note', case when not public.crew_bite_on() then 'Cabin rates are not in use yet.' end,
    'list', coalesce(jsonb_agg(jsonb_build_object(
        'seat', n.seat,
        'cabin', k.code,
        'cabin_word', k.word,
        'captain', case when o.id is not null then jsonb_build_object(
            'code', o.code, 'name', o.name, 'grade', coalesce(st.grade, cp.grade), 'job_word', t.word,
            'rate_pct', case when k.code in ('captain', t.focus) then 100 else public.wc_num('cabin_off_focus_pct') end) end)
      order by n.seat), '[]'::jsonb))
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
    join public.class_cabins cc on cc.class_code = c.code
   cross join lateral generate_series(1, cc.cabins) n(seat)
    join public.cabin_kinds k on k.code = public.cabin_focus(c.code, n.seat)
    left join public.captain_seats cs on cs.ship_id = s.id and cs.seat = n.seat
    left join public.player_officers po on po.id = cs.player_officer_id
    left join public.officers o on o.id = po.officer_id
    left join public.captain_profile cp on cp.officer_id = o.id
    left join public.captain_state st on st.player_officer_id = po.id
    left join public.traits t on t.code = o.specialty
   where s.id = p_ship
$ss$;

create or replace function world.crew_bonuses(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $cb$
  -- 0157: WHAT THE CAPTAINS ADD TO THIS FLEET, by source — every term public.crew_terms counts, in the
  -- server's words ("Ana de Sousa · Navigator · Exploration cabin · +9% speed"), and the total per
  -- effect as public.crew_pct gives it (capped). The client prints both and adds nothing.
  select jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                 'captain', o.name, 'trait', t.word, 'cabin_word', k.word, 'effect', x.effect,
                 'line', public.trait_effect_words(ce.words, x.value_pct, t.goods_word))
                 order by s.is_flagship desc, s.name, x.seat, ce.ord), '[]'::jsonb)
                from public.crew_terms(p_fleet) x
                join public.officers o on o.id = x.officer_id
                join public.traits t on t.code = x.trait
                join public.crew_effects ce on ce.code = x.effect
                join public.ships s on s.id = x.ship_id
                join public.ship_classes c on c.id = s.class_id
                join public.cabin_kinds k on k.code = public.cabin_focus(c.code, x.seat)
               where x.value_pct > 0),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object(
                 'effect', ce.code, 'pct', round(public.crew_pct(p_fleet, null, ce.code) * 100, 2),
                 'line', public.trait_effect_words(ce.words, public.crew_pct(p_fleet, null, ce.code) * 100, null))
                 order by ce.ord), '[]'::jsonb)
                from public.crew_effects ce
               where ce.scope = 'fleet' and ce.code in (select x.effect from public.crew_terms(p_fleet) x where x.value_pct > 0)))
$cb$;

revoke all on function public.crew_bite_on() from public, anon, authenticated;
revoke all on function public.cabin_focus(text, int) from public, anon, authenticated;
revoke all on function public.crew_terms(uuid) from public, anon, authenticated;
revoke all on function public.crew_pct(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.captain_seat_pick(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.captain_seat_put(uuid, uuid, int, boolean) from public, anon, authenticated;
revoke all on function public.seat_captain_for(uuid, text, uuid, int) from public, anon, authenticated;
revoke all on function world.ship_seats(uuid) from public, anon, authenticated;
revoke all on function world.crew_bonuses(uuid) from public, anon, authenticated;
revoke all on function cmd.seat_captain(text, uuid, int) from public, anon;
grant execute on function cmd.seat_captain(text, uuid, int) to authenticated;

-- ── 7. THE SEED: today's postings take their seats ─────────────────────────────────────────────
do $seed$
declare
  r record;
  p record;
  v_bad int := 0;
begin
  for r in select po.id, po.fleet_id from public.player_officers po
            where po.fleet_id is not null order by po.fleet_id, po.hired_at, po.id loop
    select * into p from public.captain_seat_pick(r.id, r.fleet_id);
    if p.ship_id is null then
      v_bad := v_bad + 1;
      continue;
    end if;
    -- the posting does not move, so her experience clock does not either (p_came_aboard false)
    perform public.captain_seat_put(r.id, p.ship_id, p.seat, false);
  end loop;
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % posted captain(s) found no free cabin in their fleet (expected 0)', v_bad;
  end if;
  -- what each signing USES: a merchant's captain her job only (O8), a player's her first `slots` known traits
  insert into public.captain_active (player_officer_id, trait)
  select po.id, ct.trait
    from public.player_officers po
    join public.players pl on pl.id = po.player_id
    join public.captain_profile cp on cp.officer_id = po.officer_id
    join public.captain_grades g on g.code = cp.grade
    join public.captain_traits ct on ct.officer_id = po.officer_id
   where (pl.is_npc and ct.ord = 1) or (not pl.is_npc and ct.ord <= g.slots);
  insert into public.captain_state (player_officer_id, grade, home_seen_at)
  select po.id, cp.grade, now()
    from public.player_officers po
    join public.players pl on pl.id = po.player_id and not pl.is_npc
    join public.captain_profile cp on cp.officer_id = po.officer_id;
end $seed$;

-- ── 8. THE RE-CUTS, then the old reader goes ────────────────────────────────────────────────────
do $recut$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0157 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0157 where fn = d.fn order by n loop
      if pg_temp.occurs_0157(v_def, h.old) <> 1 then
        raise exception '0157 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against',
          h.n, d.fn, pg_temp.occurs_0157(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $recut$;

drop function public.fleet_officer_bonus(uuid, text);

-- ── 9. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  b        record;
  d        record;
  h        record;
  v_p      record;
  v_def    text;
  v_bad    int;
  v_n      int;
  v_crew   jsonb := (select value from public.world_config where key = 'crew_bite');
  v_skills jsonb := (select value from public.world_config where key = 'skills_bite');
  v_player uuid;
  v_fleet  uuid;
  v_ship   uuid;
  v_po     uuid;
  v_cls    text;
  v_r      jsonb;
  v_val    numeric;
  v_spd    numeric;
  v_m      uuid;
  v_mfleet uuid;
  v_home   uuid;
  t0       timestamptz;
  v_old_ms numeric;
  v_new_ms numeric;
  c_uid constant uuid := '00000000-0157-4000-8000-000000000001';
  c_off constant text := 'ELCANO';        -- an S navigator (data/officers.json), 9 %
  c_npc constant text := 'NPCPILOTPRT';   -- a merchant's navigator, 4 %
begin
  select * into b from before_0157;

  -- (a) CABINS: every hull class has a role in the rotation; seat 1 is the Captain's cabin
  select count(*) into v_bad from public.ship_classes c
   where public.cabin_focus(c.code, 1) is distinct from 'captain'
      or exists (select 1 from public.class_cabins cc cross join generate_series(2, cc.cabins) n(seat)
                  where cc.class_code = c.code and public.cabin_focus(c.code, n.seat) is null);
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % hull class(es) without a Captain''s cabin or with an untyped seat', v_bad;
  end if;

  -- (b) THE SEED: every posting seated in her own fleet, at 100 % for her job; none twice
  if (select count(*) from public.captain_seats) <> b.posted then
    raise exception '0157 self-assert FAIL: % seat(s) for % posting(s)', (select count(*) from public.captain_seats), b.posted;
  end if;
  select count(*) into v_bad
    from public.captain_seats cs join public.ships s on s.id = cs.ship_id
    join public.player_officers po on po.id = cs.player_officer_id
    join public.officers o on o.id = po.officer_id join public.traits t on t.code = o.specialty
    join public.ship_classes c on c.id = s.class_id
   where s.fleet_id is distinct from po.fleet_id
      or public.cabin_focus(c.code, cs.seat) not in ('captain', t.focus);
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % captain(s) seated off their fleet or where their job works at half (expected 0)', v_bad;
  end if;
  select count(*) into v_bad from public.player_officers po join public.players pl on pl.id = po.player_id
   where (pl.is_npc and ((select count(*) from public.captain_active a where a.player_officer_id = po.id) <> 1
                         or exists (select 1 from public.captain_state st where st.player_officer_id = po.id)))
      or (not pl.is_npc and not exists (select 1 from public.captain_state st where st.player_officer_id = po.id));
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % signing(s) with the wrong active traits or state row', v_bad;
  end if;

  -- (c) DARK = the pre-image, skills dark and lit; LIT (crew_bite on) = the pre-image for every merchant
  select count(*) into v_bad from bonus_before_0157 x
   where public.crew_pct(x.fleet_id, null, x.effect) is distinct from x.dark;
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % fleet × effect(s) moved, dark', v_bad;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
  select count(*) into v_bad from bonus_before_0157 x
   where public.crew_pct(x.fleet_id, null, x.effect) is distinct from x.lit;
  update public.world_config set value = v_skills where key = 'skills_bite';
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % fleet × effect(s) moved with skills lit (Command)', v_bad;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
  select count(*) into v_bad from bonus_before_0157 x
   where x.npc and public.crew_pct(x.fleet_id, null, x.effect) is distinct from x.dark;
  update public.world_config set value = v_crew where key = 'crew_bite';
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % merchant fleet × effect(s) moved with crew_bite lit (expected 0: her job, at 100 %%)', v_bad;
  end if;
  if (select count(*) from bonus_before_0157 where dark > 0) = 0 then
    raise exception '0157 self-assert FAIL: no fleet had a captain worth anything — the parity proves nothing';
  end if;
  select count(*) into v_bad from readers_before_0157 r
   where r.v is distinct from case r.what
           when 'speed'  then voyage.fleet_speed(r.k::uuid)::text
           when 'hold'   then public.ship_hold_capacity(r.k::uuid)::text
           when 'raid'   then public.raid_crew_lost(r.k::uuid, 120, 0.15)::text
           when 'spread' then world.spread_effective(split_part(r.k, '/', 1)::uuid, split_part(r.k, '/', 2)::uuid,
                                                     split_part(r.k, '/', 3)::uuid, false)::text end;
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: % reader answer(s) moved (speed / cargo space / raid losses / spread)', v_bad;
  end if;

  -- (d) THE PROBE — own houses, own rows, rolled back
  begin
  v_player := public.new_house(c_uid, 'Casa das Cabines', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select s.id, c.code into v_ship, v_cls from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = v_fleet order by s.is_flagship desc limit 1;
  perform public.credit(v_player, 'PROBE_CABIN', 50000,
    public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0157 self-assert')));
  v_r := public.sign_officer(v_player, c_off, v_fleet);
  if not coalesce((v_r->>'ok')::boolean, false) then
    raise exception '0157 self-assert FAIL: could not hire % into a docked fleet: %', c_off, v_r;
  end if;
  select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = v_player and o.code = c_off;
  if (select public.cabin_focus(v_cls, cs.seat) from public.captain_seats cs where cs.player_officer_id = v_po)
     is distinct from (select t.focus from public.traits t where t.code = 'NAVIGATOR') then
    raise exception '0157 self-assert FAIL: the navigator was not seated in an Exploration cabin';
  end if;
  if (select count(*) from public.captain_active where player_officer_id = v_po)
     <> (select g.slots from public.captain_profile cp join public.captain_grades g on g.code = cp.grade
          join public.player_officers po on po.officer_id = cp.officer_id where po.id = v_po)
     or not exists (select 1 from public.captain_state where player_officer_id = v_po) then
    raise exception '0157 self-assert FAIL: a hired S captain does not use her five first traits, or has no state';
  end if;
  v_val := (select bonus_pct from public.officers where code = c_off) / 100.0;
  if public.crew_pct(v_fleet, null, 'speed') <> v_val then
    raise exception '0157 self-assert FAIL: dark, her speed is % (expected her value %)', public.crew_pct(v_fleet, null, 'speed'), v_val;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
  if public.crew_pct(v_fleet, null, 'speed') <> v_val then
    raise exception '0157 self-assert FAIL: lit, in her own cabin her speed is % (expected %)', public.crew_pct(v_fleet, null, 'speed'), v_val;
  end if;
  -- the Trade cabin: half; the Captain's cabin: whole
  select n.seat into v_n from generate_series(2, (select cabins from public.class_cabins where class_code = v_cls)) n(seat)
   where public.cabin_focus(v_cls, n.seat) = 'trading' limit 1;
  v_r := public.seat_captain_for(v_player, c_off, v_ship, v_n);
  if not coalesce((v_r->>'ok')::boolean, false)
     or public.crew_pct(v_fleet, null, 'speed') <> round(v_val * public.wc_num('cabin_off_focus_pct') / 100.0, 6) then
    raise exception '0157 self-assert FAIL: in the Trade cabin her speed is % (expected half of %): %', public.crew_pct(v_fleet, null, 'speed'), v_val, v_r;
  end if;
  v_r := public.seat_captain_for(v_player, c_off, v_ship, 1);
  if public.crew_pct(v_fleet, null, 'speed') <> v_val then
    raise exception '0157 self-assert FAIL: in the Captain''s cabin her speed is % (expected %)', public.crew_pct(v_fleet, null, 'speed'), v_val;
  end if;
  -- every lit term is one of her active traits, and their sum is crew_pct (below the cap)
  select count(*) into v_bad from public.crew_terms(v_fleet) x
   where not exists (select 1 from public.captain_active a where a.player_officer_id = x.player_officer_id and a.trait = x.trait);
  if v_bad <> 0 then
    raise exception '0157 self-assert FAIL: a lit term counts a trait she does not use';
  end if;
  update public.world_config set value = v_crew where key = 'crew_bite';
  -- dark again: her extra traits add nothing
  if exists (select 1 from public.crew_terms(v_fleet) x where x.trait <> 'NAVIGATOR') then
    raise exception '0157 self-assert FAIL: dark, a trait beyond her job counts';
  end if;
  -- at sea (anchored off the coast) she cannot be moved, nor put ashore
  select port_id into v_home from public.fleets where id = v_fleet;
  update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -12.0 where id = v_fleet;
  v_r := public.seat_captain_for(v_player, c_off, null);
  if v_r->>'error_code' is distinct from 'E_NOT_IN_PORT' then
    raise exception '0157 self-assert FAIL: a captain at sea was put ashore (or refused otherwise): %', v_r;
  end if;
  v_r := public.post_officer_to(v_player, c_off, null);
  if v_r->>'error_code' is distinct from 'E_NOT_IN_PORT' then
    raise exception '0157 self-assert FAIL: posting moved a captain at sea: %', v_r;
  end if;
  update public.fleets set status = 'DOCKED', port_id = v_home, lat = null, lon = null where id = v_fleet;
  -- a cabin that is not there, and one that is taken
  v_r := public.seat_captain_for(v_player, c_off, v_ship, 99);
  if v_r->>'error_code' is distinct from 'E_NO_SUCH_CABIN' then
    raise exception '0157 self-assert FAIL: seat 99 was not refused E_NO_SUCH_CABIN: %', v_r;
  end if;
  -- ashore she adds nothing, and the old column follows
  v_r := public.post_officer_to(v_player, c_off, null);
  if not coalesce((v_r->>'ok')::boolean, false) or public.crew_pct(v_fleet, null, 'speed') <> 0
     or (select fleet_id from public.player_officers where id = v_po) is not null then
    raise exception '0157 self-assert FAIL: ashore, she still counts (or the posting did not follow): %', v_r;
  end if;
  -- and posted back, the picker seats her in her own cabin again
  v_r := public.post_officer_to(v_player, c_off, v_fleet);
  if not coalesce((v_r->>'ok')::boolean, false) or public.crew_pct(v_fleet, null, 'speed') <> v_val then
    raise exception '0157 self-assert FAIL: posted back, her speed is %: %', public.crew_pct(v_fleet, null, 'speed'), v_r;
  end if;
  -- the reads: the fleet's crew bonuses and the ship's cabins say it in the server's words
  v_r := world.crew_bonuses(v_fleet);
  if jsonb_array_length(v_r->'lines') <> 1 or v_r->'lines'->0->>'line' not like '%speed' then
    raise exception '0157 self-assert FAIL: the crew bonuses read %', v_r;
  end if;
  v_r := world.ship_seats(v_ship);
  if jsonb_array_length(v_r->'list') <> (select cabins from public.class_cabins where class_code = v_cls)
     or v_r->'list'->0->>'cabin' <> 'captain'
     or (select count(*) from jsonb_array_elements(v_r->'list') e where e->'captain' is not null and e->'captain' <> 'null'::jsonb) <> 1 then
    raise exception '0157 self-assert FAIL: the ship''s cabins read %', v_r;
  end if;
  -- a merchant's captain (a merchant house of our own): seated, her job only, no state
  v_m := public.new_house(null, 'Casa da Cabine Fixa', 'PRT', p_ducats => 20000, p_is_npc => true);
  select id into v_mfleet from public.fleets where player_id = v_m;
  v_r := public.sign_officer(v_m, c_npc, v_mfleet);
  if not coalesce((v_r->>'ok')::boolean, false) then
    raise exception '0157 self-assert FAIL: a merchant could not hire her navigator: %', v_r;
  end if;
  select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id
   where po.player_id = v_m and o.code = c_npc;
  if (select array_agg(trait) from public.captain_active where player_officer_id = v_po) <> array['NAVIGATOR']
     or exists (select 1 from public.captain_state where player_officer_id = v_po)
     or not exists (select 1 from public.captain_seats where player_officer_id = v_po) then
    raise exception '0157 self-assert FAIL: a merchant''s captain is not seated with her job only and no state';
  end if;
    raise exception 'PROBE_ROLLBACK_0157';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0157' then raise; end if;
  end;
  if exists (select 1 from public.players where company_name in ('Casa das Cabines', 'Casa da Cabine Fixa'))
     or (select value from public.world_config where key = 'crew_bite') <> v_crew then
    raise exception '0157 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (e) THE RE-CUTS reverse; the old reader is gone and nothing names it
  for d in select * from defs_before_0157 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0157 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0157(v_def, h.new) <> 1 then
        raise exception '0157 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0157 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0157 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0157 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0157 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;
  if to_regprocedure('public.fleet_officer_bonus(uuid, text)') is not null
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'world', 'cmd', 'voyage') and p.prosrc like '%fleet\_officer\_bonus(%')
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'world', 'cmd', 'voyage') and p.prosrc like '%officer\_bonus\_cap\_pct%' and p.prosrc like '%wc\_%(''officer\_bonus\_cap\_pct'')%') then
    raise exception '0157 self-assert FAIL: public.fleet_officer_bonus or the retired cap knob is still named by a body';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points + 1
     or not exists (select 1 from public.client_rpc_entry_points() e where e.fn = 'cmd.seat_captain(text, uuid, int)'::regprocedure) then
    raise exception '0157 self-assert FAIL: the entry points are not the old ones + cmd.seat_captain';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
               cross join unnest(array['public.captain_seats', 'public.captain_active', 'public.captain_state',
                                       'public.cabin_kinds', 'public.cabin_rotation']) t(tab)
              where has_table_privilege(r.role, t.tab, 'select,insert,update,delete')) then
    raise exception '0157 self-assert FAIL: a client can read or write a seats table';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0157 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;

  -- (f) TIMING — notice only (the old reader's pass was timed before it was dropped).
  v_old_ms := (select ms from time_before_0157);
  t0 := clock_timestamp();
  perform public.crew_pct(x.fleet_id, null, x.effect) from bonus_before_0157 x;
  v_new_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice '0157 timing: the four effects over % fleet(s): fleet_officer_bonus % ms → crew_pct % ms',
    (select count(distinct fleet_id) from bonus_before_0157), round(v_old_ms), round(v_new_ms);

  raise notice '0157 self-assert ok: A CAPTAIN SITS IN A CABIN (K5, DARK). % posted captain(s) took their seats by the one picker, every one where her job works at 100 %%; every hull has its Captain''s cabin. public.crew_pct is the one reader of what the captains give — dark it is the old officer arithmetic to the digit: every fleet × the four live effects equals its pre-image, skills dark and lit, and so do % reader answer(s) (speed, cargo space, raid losses, spread); lit, every merchant fleet still does. The probe: an S navigator hired into a docked fleet sat in the Exploration cabin using her five first traits; lit her speed was her value there, half in the Trade cabin, whole in the Captain''s; at sea she could not be moved; ashore she added nothing; a merchant''s captain uses her job alone. public.fleet_officer_bonus is gone and no body names it; the cap knob is crew_effects.cap_pct; +1 entry point (cmd.seat_captain); 0 client write grants.',
    b.posted, (select count(*) from readers_before_0157);
end $$;

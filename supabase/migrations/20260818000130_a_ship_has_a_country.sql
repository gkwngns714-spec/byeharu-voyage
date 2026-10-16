-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0130 — A SHIP HAS A COUNTRY  (eleven shipbuilding lines; a hull is built in its line's countries)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8, step S8 "Countries & yards" — the first build step of the ship grid
-- (11 lines × 6 sizes × 4 roles × T1/T2/famous). Every later step (skills, gear racks, the 100 new
-- hulls) hangs a hull on a LINE, and a line on the countries whose yards build it. This file lays
-- that floor and changes nothing a player can build today.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * scripts/lib/world-derive.mjs NATION_OVERRIDE keyed Goa as `goa` — a key no port carries
--     (the port is `old-goa`) — so Old Goa, the Portuguese capital in the Indies from 1510, derived
--     with NO nation. Surat, Khambhat, the five Malabar ports, Jakarta and Banten had none either:
--     the powers that held them (Gujarat, Calicut & Cochin, Banten) were not among the twenty.
--   * The eastern chief yards derive as building-yard tier 1-2 (public.harbour_buildings, 0089:81,
--     dev_industry 10-13), so no line but the European ones could ever build a medium hull.
--   * cmd.do_build (0072, as cut by 0096/0122) asks the yard's TIER only: where a hull may be
--     built has no country.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) +3 nations — GUJ Gujarat Sultanate, MLB Malabar, BAN Banten — and the port fixes: Old Goa →
--     PRT; Surat, Khambhat → GUJ; Kozhikode, Kochi, Kannur, Kollam, Mangaluru → MLB; Jakarta,
--     Banten → BAN. The derive script says the same (world-derive.mjs), and the world guard
--     (scripts/db/world-guard.mjs) holds the database to it on every apply.
-- (2) public.ship_lines — the eleven lines (data/ship-lines.json): home nation (the flag a hull is
--     shown under), builder nations, philosophy, modifiers, traits, and the ARSENAL (the line's
--     chief yard). Server-only; served through world.snapshot() and world.building_yard().
-- (3) public.class_profile (class_code, line_code, size 1-6, role, tech, deck, any_yard) — a SIDE
--     table. ship_classes is not touched: its tier stays the 1-5 escort score and equals
--     least(size, 5) (asserted), so its check is never altered. The three live hulls (barca,
--     carlat, nau) are PRT with any_yard = true: every company builds them at every yard, as before.
-- (4) THE ARSENALS: the seven chief yards (Seville, Amsterdam, Istanbul, Surat, Guangzhou, Osaka,
--     Busan) become building-yard tier 3, so every line has a yard for every size. The ONE rule
--     for a yard's tier, public.harbour_buildings (0089), is re-cut to read ship_lines.arsenal_port,
--     and the seven rows are raised from it. ports.yard_tier (the repair yard) is untouched.
-- (5) THE ONE COUNTRY RULE: public.yard_wrong_country(port, class) — null when this port's country
--     may build the class (any_yard, or its nation is among the line's builders), else the
--     E_WRONG_YARD sentence with its figures (the line's country, every builder by name, and this
--     port's country). Read by cmd.do_build (one hunk, after the tier check) and by
--     world.building_yard (buildable + the new right_yard), so the screen and the door cannot
--     disagree. world.snapshot() serves each class's line and line_nation for the Codex flag.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No new hull, no skill, no stat moves (modifiers and traits are recorded, read by nothing yet).
-- No new entry point, no client write, no cron, no knob. ports.yard_tier, ship_classes and
-- hull_recipes untouched. MUG's capital stays Surat (0003) though Surat is now Gujarat's: moving a
-- capital is not in S8's list. Side effect, said plainly (§3.2): the inn's weighting toward an
-- officer's own nation (0119) sees these ten ports as national for the first time.
--
-- ── LOCKS, AND THE PROBES ───────────────────────────────────────────────────────────────────────
-- lock_timeout 5 s; no LOCK TABLE, no set role, no begin/commit. The new tables' FKs take SHARE ROW
-- EXCLUSIVE on ship_classes / nations (never written by a tick). Row writes: 10 ports rows, at most
-- 7 port_buildings rows, 3 nations rows. Self-asserts hold on a LIVED-IN world: every probe runs on
-- its own founded house and rolls back; counts are measured against pre-images taken in this file,
-- never against an assumed empty world.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once and to reverse to its pre-image: cmd.do_build (0072 as cut by 0096/0122), world.building_yard
-- (0072), world.snapshot() (0076), public.harbour_buildings (0089).
--
-- ROLLBACK (forward migration): restore the seven tiers and the ten port nations from the printed
-- lists, reverse the four hunks, drop yard_wrong_country, class_profile, ship_lines and the three
-- nations (no port references them then).
-- VERSION: 0130. Applies on prod head 0129.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- 0127's posture: never queue the arrivals sweep for long
end $guard$;

-- ── 0. THE PROBE: what BUILD answers for each live hull at every build yard ────────────────────
-- Founds its own house (rolled back), docks its fleet at each yard in turn with every material of
-- the three hulls in storage and money enough, and calls the one door, cmd.do_build. Each build is
-- undone at once; the whole house is undone at the end. Returns {yard/class: 'ok' | E_CODE}.
-- p_control: before probing, tag the nau as a Dutch hull with any_yard off — the gate must then bite
-- at every yard outside the Dutch line's builders (and only there). Also returns the sentence the
-- door gave at Lisbon and what the yard screen served there.
create or replace function pg_temp.probe_0130(p_control boolean)
returns jsonb
language plpgsql
as $$
declare
  c_uid    constant uuid := '00000000-0130-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_out    jsonb := '{}'::jsonb;
  v_lis    text;
  v_view   jsonb;
  v_res    text;
  v_msg    text;
  y        record;
  k        text;
begin
  begin
    v_player := public.new_house(c_uid, 'Casa da Prova', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform public.credit(v_player, 'PROBE_0130', 10000000);
    if p_control then
      update public.class_profile set line_code = 'NLD', any_yard = false where class_code = 'nau';
    end if;
    for y in select b.port_id, p.code from public.port_buildings b join public.ports p on p.id = b.port_id
              where b.kind = 'building_yard' order by p.code loop
      update public.fleets set port_id = y.port_id, status = 'DOCKED' where id = v_fleet;
      insert into public.player_storage (player_id, port_id, good_id, qty)
      select v_player, y.port_id, hg.good_id, sum(hg.qty) from public.hull_recipe_goods hg
       where hg.class_code in ('barca', 'carlat', 'nau') group by hg.good_id
      on conflict (player_id, port_id, good_id) do update set qty = excluded.qty;
      insert into public.player_items (player_id, port_id, item_code, qty)
      select v_player, y.port_id, hi.item_code, sum(hi.qty) from public.hull_recipe_items hi
       where hi.class_code in ('barca', 'carlat', 'nau') group by hi.item_code
      on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
      foreach k in array array['barca', 'carlat', 'nau'] loop
        v_msg := null;
        begin
          perform cmd.do_build(v_fleet, jsonb_build_object('class', k, 'name', 'Prova ' || k));
          raise exception 'PROBE_UNDO_0130';
        exception when others then
          v_msg := sqlerrm;
        end;
        v_res := case when v_msg = 'PROBE_UNDO_0130' then 'ok' else split_part(v_msg, ':', 1) end;
        v_out := v_out || jsonb_build_object(y.code || '/' || k, v_res);
        if y.code = 'LIS' and k = 'nau' then v_lis := v_msg; end if;
      end loop;
      if y.code = 'LIS' then
        select h.value into v_view from jsonb_array_elements(world.building_yard(y.port_id)->'hulls') h
         where h.value->>'class' = 'nau';
      end if;
    end loop;
    raise exception 'PROBE_ROLLBACK_0130';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0130' then raise; end if;
  end;
  return jsonb_build_object('outcomes', v_out, 'lis_nau', v_lis, 'lis_view', v_view);
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0130 as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['cmd.do_build(uuid, jsonb)',
                    'world.building_yard(uuid)',
                    'world.snapshot()',
                    'public.harbour_buildings(uuid)']) f(fn);

create temp table before_0130 as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.nations) as nations,
       (select count(*) from public.port_buildings) as buildings,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) as classes_hash,
       (select count(*) from public.ship_classes) as classes,
       (select string_agg(pg_get_constraintdef(k.oid), ' | ' order by k.conname)
          from pg_constraint k where k.conrelid = 'public.ship_classes'::regclass) as classes_checks,
       (select count(*) from public.ports where kind = 'HARBOUR' and nation_id is null) as stateless;

create temp table ports_before_0130 as
select p.id, p.code, p.nation_id from public.ports p;

create temp table buildings_before_0130 as
select b.port_id, b.kind, b.tier from public.port_buildings b;

-- building-yard rows the rule (0089) did not name exactly, before this file (0 on a world 0089 furnished)
create temp table rule_misses_before_0130 as
select b.port_id from public.port_buildings b
  left join lateral public.harbour_buildings(b.port_id) r on r.kind = b.kind
 where b.kind = 'building_yard' and r.tier is distinct from b.tier;

create temp table probe_before_0130 as
select pg_temp.probe_0130(false) as j;

-- ── 2. THE THREE NATIONS (world-derive.mjs NATIONS / CAPITALS) ─────────────────────────────────
insert into public.nations (code, name, flag_char, capital_port_code) values
  ('GUJ', 'Gujarat Sultanate', '❁', 'KHA'),
  ('MLB', 'Malabar', '✹', 'KOZ'),
  ('BAN', 'Banten', '✧', 'BNT')
on conflict (code) do nothing;

-- ── 3. THE PORT FIXES (world-derive.mjs NATION_OVERRIDE) ───────────────────────────────────────
create temp table port_nations_0130 (code text primary key, nation text not null);
insert into port_nations_0130 values
  ('OLD', 'PRT'),
  ('SRT', 'GUJ'), ('KHA', 'GUJ'),
  ('KOZ', 'MLB'), ('KOC', 'MLB'), ('KAN', 'MLB'), ('KOL', 'MLB'), ('MNG', 'MLB'),
  ('JAK', 'BAN'), ('BNT', 'BAN');

update public.ports p
   set nation_id = n.id
  from port_nations_0130 w
  join public.nations n on n.code = w.nation
 where p.code = w.code and p.nation_id is distinct from n.id;

-- ── 4. THE LINES (data/ship-lines.json `lines`) ────────────────────────────────────────────────
create table if not exists public.ship_lines (
  code            text primary key check (code ~ '^[A-Z]{3}$'),
  name            text not null,
  home_nation     text not null references public.nations(code),
  builder_nations text[] not null check (cardinality(builder_nations) >= 1),
  arsenal_port    text check (arsenal_port is null or arsenal_port ~ '^[A-Z]{3}$'),
  philosophy      text not null,
  modifiers       jsonb not null,
  traits          jsonb not null,
  check (home_nation = any(builder_nations))
);

comment on table public.ship_lines is
  '0130: a shipbuilding tradition ("Dutch hulls", docs/SHIPS_AND_SKILLS.md §3.1). home_nation is the '
  'flag a hull is shown under; builder_nations are the nations whose build yards may build its hulls '
  '(public.yard_wrong_country, the one rule); arsenal_port is the chief yard public.harbour_buildings '
  'raises to tier 3. modifiers/traits are recorded for the generator (S12) and skills (S11); no rule '
  'reads them yet. Authored in data/ship-lines.json; scripts/db/world-guard.mjs holds the table to it.';

alter table public.ship_lines enable row level security;
revoke all on table public.ship_lines from public, anon, authenticated;

insert into public.ship_lines (code, name, home_nation, builder_nations, arsenal_port, philosophy, modifiers, traits) values
  ('PRT', 'Portugal', 'PRT', '{PRT}', null,
   'The ocean pioneers: balanced, far-seeing, the anchor of the scale.',
   '{"mult": {"hold": 1, "speed": 1, "crew": 1, "hull": 1, "attack": 1}, "add": {"handling": 0, "armour": 0, "accuracy": 0, "reach": 0, "sighting": 0, "draft": 0}}',
   '[{"stat": "sighting", "pct": 4}, {"stat": "speed", "pct": 2}]'),
  ('ESP', 'Spain', 'ESP', '{ESP}', 'SVQ',
   'The treasure fleets: high-sided, armoured, heavily manned, slow.',
   '{"mult": {"hold": 1.00, "speed": 0.96, "crew": 1.15, "hull": 1.15, "attack": 1.15}, "add": {"handling": -4, "armour": 6, "accuracy": 0, "reach": 4, "sighting": 0, "draft": 0}}',
   '[{"stat": "hull", "pct": 5}, {"stat": "attack", "pct": 4}]'),
  ('NLD', 'The Netherlands', 'NLD', '{NLD,HAN,POL,DNK,SWE}', 'AMS',
   'The efficient carriers: huge holds, tiny crews, shallow draft, light guns.',
   '{"mult": {"hold": 1.25, "speed": 0.98, "crew": 0.75, "hull": 0.90, "attack": 0.75}, "add": {"handling": 2, "armour": -4, "accuracy": 0, "reach": 0, "sighting": 0, "draft": -1}}',
   '[{"stat": "hold", "pct": 5}, {"stat": "handling", "pct": 3}]'),
  ('ENG', 'England', 'ENG', '{ENG}', null,
   'Race-built gun ships: fast, handy, shoot straight and far.',
   '{"mult": {"hold": 0.92, "speed": 1.05, "crew": 1.00, "hull": 0.95, "attack": 1.05}, "add": {"handling": 6, "armour": -2, "accuracy": 8, "reach": 8, "sighting": 0, "draft": 0}}',
   '[{"stat": "accuracy", "pct": 4}, {"stat": "speed", "pct": 2}]'),
  ('FRA', 'France', 'FRA', '{FRA}', null,
   'Elegant hulls: quick and handy, all-round.',
   '{"mult": {"hold": 1.00, "speed": 1.04, "crew": 1.00, "hull": 1.00, "attack": 1.05}, "add": {"handling": 4, "armour": 0, "accuracy": 4, "reach": 0, "sighting": 1, "draft": 0}}',
   '[{"stat": "handling", "pct": 4}, {"stat": "reach", "pct": 4}]'),
  ('ITA', 'Italy', 'VEN', '{VEN,GEN}', null,
   'Galleys and great galleys: oared, nimble, crowded, short-ranged.',
   '{"mult": {"hold": 0.90, "speed": 1.00, "crew": 1.35, "hull": 0.95, "attack": 1.15}, "add": {"handling": 8, "armour": 0, "accuracy": 2, "reach": -10, "sighting": 0, "draft": -1}}',
   '[{"stat": "attack", "pct": 5}, {"stat": "handling", "pct": 4}]'),
  ('OTT', 'The Ottoman Empire', 'OTT', '{OTT}', 'IST',
   'The Arsenal''s fleets: stout, manned for boarding.',
   '{"mult": {"hold": 0.95, "speed": 0.98, "crew": 1.25, "hull": 1.10, "attack": 1.15}, "add": {"handling": 2, "armour": 4, "accuracy": 0, "reach": -4, "sighting": 0, "draft": 0}}',
   '[{"stat": "armour", "pct": 5}, {"stat": "attack", "pct": 4}]'),
  ('IND', 'Arabia & India', 'GUJ', '{GUJ,MLB,BAN}', 'SRT',
   'Sewn and teak hulls of the monsoon: fast, sweet-handling, lightly armed.',
   '{"mult": {"hold": 1.08, "speed": 1.04, "crew": 0.85, "hull": 1.05, "attack": 0.60}, "add": {"handling": 4, "armour": -2, "accuracy": -10, "reach": -10, "sighting": 1, "draft": -1}}',
   '[{"stat": "hull", "pct": 5}, {"stat": "hold", "pct": 3}]'),
  ('CHN', 'China', 'MNG', '{MNG}', 'GUA',
   'Bulkheaded junks: roomy, very hard to sink, clumsy.',
   '{"mult": {"hold": 1.15, "speed": 0.95, "crew": 1.00, "hull": 1.20, "attack": 0.90}, "add": {"handling": -8, "armour": 6, "accuracy": -4, "reach": 0, "sighting": 0, "draft": 0}}',
   '[{"stat": "hull", "pct": 5}, {"stat": "hold", "pct": 4}]'),
  ('JPN', 'Japan', 'JPN', '{JPN}', 'OSA',
   'Pine-hulled war boats and red-seal traders: precise gunnery, short range.',
   '{"mult": {"hold": 0.90, "speed": 1.00, "crew": 1.15, "hull": 0.95, "attack": 1.10}, "add": {"handling": 4, "armour": 2, "accuracy": 6, "reach": -8, "sighting": 1, "draft": 0}}',
   '[{"stat": "accuracy", "pct": 4}, {"stat": "attack", "pct": 4}]'),
  ('KOR', 'Joseon', 'JOS', '{JOS}', 'BUS',
   'Plated decks: the best armour afloat.',
   '{"mult": {"hold": 0.90, "speed": 0.97, "crew": 1.10, "hull": 1.10, "attack": 1.10}, "add": {"handling": 2, "armour": 10, "accuracy": 4, "reach": 0, "sighting": 0, "draft": 0}}',
   '[{"stat": "armour", "pct": 5}, {"stat": "accuracy", "pct": 3}]')
on conflict (code) do nothing;

-- ── 5. THE CLASS PROFILE (data/ship-lines.json `profiles`) ─────────────────────────────────────
create table if not exists public.class_profile (
  class_code text primary key references public.ship_classes(code),
  line_code  text not null references public.ship_lines(code),
  size       int  not null check (size between 1 and 6),
  role       text not null check (role in ('trade', 'combat', 'explorer', 'support')),
  tech       text not null check (tech in ('T1', 'T2', 'F')),
  deck       int  not null check (deck >= 0),
  any_yard   boolean not null default false
);

comment on table public.class_profile is
  '0130: a hull''s line, size (1-6), role, tech and deck budget — a SIDE table, so ship_classes and '
  'its 1-5 tier check are never altered (ship_classes.tier = least(size, 5), asserted). any_yard: '
  'buildable at every build yard whatever its country — true only for the three hulls every company '
  'could build before 0130. Authored in data/ship-lines.json; the world guard holds it to the file.';

alter table public.class_profile enable row level security;
revoke all on table public.class_profile from public, anon, authenticated;

insert into public.class_profile (class_code, line_code, size, role, tech, deck, any_yard) values
  ('barca',  'PRT', 1, 'trade',    'T1', 12, true),
  ('carlat', 'PRT', 2, 'explorer', 'T1', 22, true),
  ('nau',    'PRT', 3, 'trade',    'T1', 56, true)
on conflict (class_code) do nothing;

-- ── 6. THE ONE COUNTRY RULE ────────────────────────────────────────────────────────────────────
create or replace function public.yard_wrong_country(p_port uuid, p_class text)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when cp.class_code is null then
      format('E_WRONG_YARD: %s belongs to no shipbuilding country, so no build yard can build it.', c.name)
    when cp.any_yard then null
    when n.code = any(sl.builder_nations) then null
    else format('E_WRONG_YARD: %s is a ship from %s. Only build yards in %s can build it, and %s',
                c.name, sl.name,
                case when cardinality(b.names) = 1 then b.names[1]
                     else array_to_string(b.names[1:cardinality(b.names) - 1], ', ') || ' or ' || b.names[cardinality(b.names)] end,
                case when n.code is null then 'this port belongs to no country.'
                     else format('this port is in %s.', n.name) end)
  end
  from public.ship_classes c
  left join public.class_profile cp on cp.class_code = c.code
  left join public.ship_lines sl on sl.code = cp.line_code
  left join lateral (select array_agg(bn.name order by array_position(sl.builder_nations, bn.code)) as names
                       from public.nations bn where bn.code = any(sl.builder_nations)) b on true
  left join public.ports p on p.id = p_port
  left join public.nations n on n.id = p.nation_id
 where c.code = p_class
$$;

comment on function public.yard_wrong_country(uuid, text) is
  '0130 THE ONE COUNTRY RULE: null when this port''s build yard may build the class (class_profile.'
  'any_yard, or the port''s nation is among its line''s builder_nations), else the E_WRONG_YARD sentence '
  'with its figures. Read by cmd.do_build (the door) and world.building_yard (the screen), nothing else.';

revoke all on function public.yard_wrong_country(uuid, text) from public, anon, authenticated;

-- ── 7. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0130 (fn text, n int, old text, new text);
insert into hunks_0130 values
-- public.harbour_buildings: a line's arsenal is a tier-3 building yard
('public.harbour_buildings(uuid)', 1,
$h$      ('building_yard', case when p.dev_industry >= 15 then 3 when p.dev_industry >= 12 then 2 else 1 end,
                        p.yard_tier >= 3)
$h$,
$h$      -- 0130: a line's ARSENAL (public.ship_lines.arsenal_port) builds every size, whatever its industry
      ('building_yard', case when exists (select 1 from public.ship_lines sl where sl.arsenal_port = p.code) then 3
                             when p.dev_industry >= 15 then 3 when p.dev_industry >= 12 then 2 else 1 end,
                        p.yard_tier >= 3)
$h$),
-- cmd.do_build: the yard's country must build the hull's line
('cmd.do_build(uuid, jsonb)', 1,
$h$  v_tier   int;
  v_name   text := btrim(coalesce(p_args->>'name', ''));
$h$,
$h$  v_tier   int;
  v_wrong  text;   -- 0130: the country rule's refusal, or null
  v_name   text := btrim(coalesce(p_args->>'name', ''));
$h$),
('cmd.do_build(uuid, jsonb)', 2,
$h$  if v_tier < h.yard_tier then
    raise exception 'E_YARD_TOO_SMALL: a % wants a tier % yard and this one is tier %',
      c.name, h.yard_tier, v_tier using errcode = 'P0001';
  end if;
$h$,
$h$  if v_tier < h.yard_tier then
    raise exception 'E_YARD_TOO_SMALL: a % wants a tier % yard and this one is tier %',
      c.name, h.yard_tier, v_tier using errcode = 'P0001';
  end if;
  -- 0130: a hull is built only in its line's countries — the one rule, public.yard_wrong_country.
  v_wrong := public.yard_wrong_country(f.port_id, c.code);
  if v_wrong is not null then
    raise exception '%', v_wrong using errcode = 'P0001';
  end if;
$h$),
-- world.building_yard: the screen reads the same rule, and serves the hull's country
('world.building_yard(uuid)', 1,
$h$        'buildable', v_tier is not null and v_tier >= h.yard_tier,
$h$,
$h$        'buildable', v_tier is not null and v_tier >= h.yard_tier
                     and public.yard_wrong_country(p_port, c.code) is null,
        -- 0130: the hull's country — its line, the flag it is shown under, the countries whose
        -- yards build it, and whether THIS port is one of them (the one rule, as cmd.do_build reads it).
        'line', cp.line_code, 'line_name', sl.name, 'line_nation', sl.home_nation,
        'builders', to_jsonb(coalesce(sl.builder_nations, '{}'::text[])),
        'right_yard', public.yard_wrong_country(p_port, c.code) is null,
$h$),
('world.building_yard(uuid)', 2,
$h$      from public.hull_recipes h join public.ship_classes c on c.code = h.class_code));
$h$,
$h$      from public.hull_recipes h join public.ship_classes c on c.code = h.class_code
      left join public.class_profile cp on cp.class_code = c.code      -- 0130
      left join public.ship_lines sl on sl.code = cp.line_code));      -- 0130
$h$),
-- world.snapshot(): each class carries its line and the flag it is shown under (the Codex)
('world.snapshot()', 1,
$h$    'ship_classes', (select coalesce(jsonb_agg(to_jsonb(c) order by c.tier), '[]'::jsonb)
      from public.ship_classes c),
$h$,
$h$    'ship_classes', (select coalesce(jsonb_agg(to_jsonb(c)
        || jsonb_build_object('line', cp.line_code, 'line_nation', sl.home_nation)   -- 0130
        order by c.tier), '[]'::jsonb)
      from public.ship_classes c
      left join public.class_profile cp on cp.class_code = c.code
      left join public.ship_lines sl on sl.code = cp.line_code),
$h$);

-- ── 8. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0130(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0130 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0130 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0130(fn) from defs_before_0130 order by fn;

-- ── 9. THE ARSENALS: raised by the rule, not by a second list ──────────────────────────────────
update public.port_buildings b
   set tier = r.tier
  from public.ports p
  cross join lateral public.harbour_buildings(p.id) r
 where b.port_id = p.id and b.kind = 'building_yard' and r.kind = 'building_yard'
   and p.code in (select sl.arsenal_port from public.ship_lines sl where sl.arsenal_port is not null)
   and b.tier < r.tier;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bad      int;
  v_n        int;
  v_list     text;
  v_moved    int;
  v_raised   int;
  v_raised_l text;
  v_ports_l  text;
  v_def      text;
  h          record;
  d          record;
  v_pre      jsonb := (select j from probe_before_0130);
  v_post     jsonb;
  v_ctl      jsonb;
  v_yards    int;
  v_snap     jsonb;
  v_lis      text;
begin
  -- (a) THREE NATIONS, and only three; each capital resolves to a port it holds.
  if (select count(*) from public.nations) <> (select nations from before_0130) + 3 then
    raise exception '0130 self-assert FAIL: % nations, expected % + 3', (select count(*) from public.nations), (select nations from before_0130);
  end if;
  select count(*) into v_bad from public.nations n
   where n.code in ('GUJ', 'MLB', 'BAN')
     and not exists (select 1 from public.ports p where p.code = n.capital_port_code and p.nation_id = n.id);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % new nation(s) whose capital is not a port they hold', v_bad;
  end if;

  -- (b) ONLY THE LISTED PORTS CHANGED NATION, and every listed port now holds its own.
  select count(*), string_agg(p.code, ',' order by p.code) into v_moved, v_ports_l
    from public.ports p join ports_before_0130 b on b.id = p.id
   where p.nation_id is distinct from b.nation_id;
  select count(*) into v_bad
    from public.ports p join ports_before_0130 b on b.id = p.id
   where p.nation_id is distinct from b.nation_id
     and p.code not in (select code from port_nations_0130);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % port(s) outside the list changed nation (%)', v_bad, v_ports_l;
  end if;
  select count(*) into v_bad from port_nations_0130 w
   where not exists (select 1 from public.ports p join public.nations n on n.id = p.nation_id
                      where p.code = w.code and n.code = w.nation);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % listed port(s) do not hold their nation', v_bad;
  end if;
  if (select count(*) from public.ports) <> (select count(*) from ports_before_0130) then
    raise exception '0130 self-assert FAIL: the port count moved';
  end if;

  -- (c) ONLY THE ARSENAL ROWS CHANGED TIER: no building row added, dropped or moved but a building
  --     yard at an arsenal, and every arsenal now builds every size.
  if (select count(*) from public.port_buildings) <> (select buildings from before_0130) then
    raise exception '0130 self-assert FAIL: % building rows, % before', (select count(*) from public.port_buildings), (select buildings from before_0130);
  end if;
  select count(*), string_agg(p.code || ' ' || b.tier || '→' || pb.tier, ', ' order by p.code)
    into v_raised, v_raised_l
    from buildings_before_0130 b
    join public.port_buildings pb on pb.port_id = b.port_id and pb.kind = b.kind
    join public.ports p on p.id = b.port_id
   where pb.tier <> b.tier;
  select count(*) into v_bad
    from buildings_before_0130 b
    join public.port_buildings pb on pb.port_id = b.port_id and pb.kind = b.kind
    join public.ports p on p.id = b.port_id
   where pb.tier <> b.tier
     and not (b.kind = 'building_yard' and p.code in (select arsenal_port from public.ship_lines where arsenal_port is not null));
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % building row(s) other than an arsenal''s yard changed tier (%)', v_bad, v_raised_l;
  end if;
  select count(*) into v_bad from public.ship_lines sl
   where sl.arsenal_port is not null
     and not exists (select 1 from public.port_buildings b join public.ports p on p.id = b.port_id
                      where p.code = sl.arsenal_port and b.kind = 'building_yard' and b.tier >= 3);
  if v_bad <> 0 or (select count(*) from public.ship_lines where arsenal_port is not null) <> 7 then
    raise exception '0130 self-assert FAIL: % of the seven arsenals keep no tier-3 build yard', v_bad;
  end if;
  -- the rule names every building yard as it stands (no new miss; the arsenals are not misses)
  select count(*) into v_bad from public.port_buildings b
    left join lateral public.harbour_buildings(b.port_id) r on r.kind = b.kind
   where b.kind = 'building_yard' and r.tier is distinct from b.tier
     and b.port_id not in (select port_id from rule_misses_before_0130);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % build yard(s) whose tier the rule (harbour_buildings) no longer names', v_bad;
  end if;

  -- (d) THE LINES: eleven, each home nation among its builders, every builder a nation, and every
  --     line has at least one tier-3 build yard in its own countries (so every size can be built).
  if (select count(*) from public.ship_lines) <> 11 then
    raise exception '0130 self-assert FAIL: % ship lines, expected 11', (select count(*) from public.ship_lines);
  end if;
  select count(*) into v_bad from public.ship_lines sl, unnest(sl.builder_nations) bn
   where not exists (select 1 from public.nations n where n.code = bn);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % builder nation(s) are no nation', v_bad;
  end if;
  select string_agg(sl.code, ',' order by sl.code) into v_list from public.ship_lines sl
   where not exists (select 1 from public.port_buildings b
                       join public.ports p on p.id = b.port_id
                       join public.nations n on n.id = p.nation_id
                      where b.kind = 'building_yard' and b.tier >= 3 and n.code = any(sl.builder_nations));
  if v_list is not null then
    raise exception '0130 self-assert FAIL: line(s) % have no tier-3 build yard in their own countries', v_list;
  end if;

  -- (e) THE PROFILE: every class has one; the three live hulls are PRT, any yard, sizes 1/2/3;
  --     ship_classes.tier = least(size, 5) for every class.
  select count(*) into v_bad from public.ship_classes c
   where not exists (select 1 from public.class_profile cp where cp.class_code = c.code);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % ship class(es) have no profile', v_bad;
  end if;
  select count(*) into v_n from public.class_profile cp
   where (cp.class_code, cp.line_code, cp.size, cp.any_yard) in
         (('barca', 'PRT', 1, true), ('carlat', 'PRT', 2, true), ('nau', 'PRT', 3, true));
  if v_n <> 3 then
    raise exception '0130 self-assert FAIL: only % of the three live hulls are tagged PRT / any yard / sizes 1-2-3', v_n;
  end if;
  select count(*) into v_bad from public.ship_classes c join public.class_profile cp on cp.class_code = c.code
   where c.tier <> least(cp.size, 5);
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % class(es) whose tier is not least(size, 5)', v_bad;
  end if;

  -- (f) SHIP_CLASSES UNTOUCHED: every row (hash), the count and every constraint, as found.
  if (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) <> (select classes_hash from before_0130)
     or (select count(*) from public.ship_classes) <> (select classes from before_0130)
     or (select string_agg(pg_get_constraintdef(k.oid), ' | ' order by k.conname)
           from pg_constraint k where k.conrelid = 'public.ship_classes'::regclass) <> (select classes_checks from before_0130) then
    raise exception '0130 self-assert FAIL: ship_classes moved (rows, count or constraints)';
  end if;

  -- (g) THE RE-CUTS: each new body reverses to its pre-image hunk by hunk; ACLs unmoved; no new
  --     entry point; the new rule and tables are server-only.
  for d in select * from defs_before_0130 loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0130 where fn = d.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0130 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0130 self-assert FAIL: % does not reverse to its pre-image — something beyond the hunks moved', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0130 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0130) then
    raise exception '0130 self-assert FAIL: the client entry points moved';
  end if;
  if has_function_privilege('authenticated', 'public.yard_wrong_country(uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.yard_wrong_country(uuid, text)', 'execute')
     or has_table_privilege('authenticated', 'public.ship_lines', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.ship_lines', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.class_profile', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.class_profile', 'select,insert,update,delete') then
    raise exception '0130 self-assert FAIL: a client role can reach the country rule or its tables';
  end if;

  -- (h) THE LIVE HULLS ARE BUILT EXACTLY AS BEFORE, at every yard, through the one door (a probe
  --     house of this file's own, rolled back). The only differences allowed are the arsenals'
  --     raised tiers: there a hull a tier-1/2 yard refused (E_YARD_TOO_SMALL) is now built.
  v_post := pg_temp.probe_0130(false)->'outcomes';
  select count(*) into v_yards from public.port_buildings where kind = 'building_yard';
  if v_yards < 30 or (select count(*) from jsonb_object_keys(v_pre->'outcomes')) <> v_yards * 3
     or (select count(*) from jsonb_object_keys(v_post)) <> v_yards * 3 then
    raise exception '0130 self-assert FAIL: the probe saw % / % outcomes for % build yards',
      (select count(*) from jsonb_object_keys(v_pre->'outcomes')), (select count(*) from jsonb_object_keys(v_post)), v_yards;
  end if;
  select count(*), string_agg(e.key || ' ' || e.value || '→' || coalesce(v_post->>e.key, 'none'), ', ')
    into v_bad, v_list
    from jsonb_each_text(v_pre->'outcomes') e
   where e.value is distinct from v_post->>e.key
     and not (split_part(e.key, '/', 1) in (select arsenal_port from public.ship_lines where arsenal_port is not null)
              and e.value = 'E_YARD_TOO_SMALL' and v_post->>e.key = 'ok');
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % live-hull build outcome(s) moved: %', v_bad, v_list;
  end if;
  -- non-vacuity: a barca is built at every yard; a nau somewhere; the gate never refuses a live hull
  select count(*) into v_bad from jsonb_each_text(v_post) e where e.key like '%/barca' and e.value <> 'ok';
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: % yard(s) refuse a barca with everything to hand', v_bad;
  end if;
  if not exists (select 1 from jsonb_each_text(v_post) e where e.key like '%/nau' and e.value = 'ok') then
    raise exception '0130 self-assert FAIL: no yard builds a nau — the probe proves nothing';
  end if;
  if exists (select 1 from jsonb_each_text(v_post) e where e.value not in ('ok', 'E_YARD_TOO_SMALL')) then
    raise exception '0130 self-assert FAIL: a live hull is refused for a reason other than the yard''s size';
  end if;

  -- (i) POSITIVE CONTROL: the gate BITES. With the nau tagged a Dutch hull (any_yard off), BUILD
  --     refuses E_WRONG_YARD at every yard outside the Dutch line's builders, and at theirs answers
  --     what it answered before. The sentence names the figures; the yard screen agrees.
  v_ctl := pg_temp.probe_0130(true);
  select count(*), string_agg(e.key || ' ' || e.value, ', ')
    into v_bad, v_list
    from jsonb_each_text(v_ctl->'outcomes') e
    join public.ports p on p.code = split_part(e.key, '/', 1)
    left join public.nations n on n.id = p.nation_id
   where e.value is distinct from case
           when e.key not like '%/nau' then v_post->>e.key
           when n.code = any(array['NLD', 'HAN', 'POL', 'DNK', 'SWE']) then v_post->>e.key
           when v_post->>e.key = 'ok' then 'E_WRONG_YARD'   -- the tier check runs first
           else v_post->>e.key end;
  if v_bad <> 0 then
    raise exception '0130 self-assert FAIL: with the nau Dutch, % outcome(s) are not what the country rule says: %', v_bad, v_list;
  end if;
  select count(*) into v_n from jsonb_each_text(v_post) e
    join public.ports p on p.code = split_part(e.key, '/', 1)
    left join public.nations n on n.id = p.nation_id
   where e.key like '%/nau' and e.value = 'ok'
     and not coalesce(n.code = any(array['NLD', 'HAN', 'POL', 'DNK', 'SWE']), false);
  if v_n < 5 or (select count(*) from jsonb_each_text(v_ctl->'outcomes') e where e.value = 'E_WRONG_YARD') <> v_n then
    raise exception '0130 self-assert FAIL: the control refused at % yard(s); % yard(s) outside the Dutch builders build a nau',
      (select count(*) from jsonb_each_text(v_ctl->'outcomes') e where e.value = 'E_WRONG_YARD'), v_n;
  end if;
  v_lis := v_ctl->>'lis_nau';
  if v_lis is null or position('E_WRONG_YARD: Nau' in v_lis) <> 1
     or position('The Netherlands, The Hanse, Poland-Lithuania, Denmark-Norway or Sweden' in v_lis) = 0
     or position('this port is in Portugal.' in v_lis) = 0 then
    raise exception '0130 self-assert FAIL: the refusal at Lisbon does not carry its figures: %', v_lis;
  end if;
  if (v_ctl->'lis_view'->>'buildable')::boolean or (v_ctl->'lis_view'->>'right_yard')::boolean
     or v_ctl->'lis_view'->>'line_nation' <> 'NLD' then
    raise exception '0130 self-assert FAIL: the yard screen at Lisbon disagrees with the door: %', v_ctl->'lis_view';
  end if;
  if (select any_yard from public.class_profile where class_code = 'nau') is not true
     or exists (select 1 from public.players where auth_uid = '00000000-0130-4000-8000-000000000001') then
    raise exception '0130 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (j) THE SERVED COUNTRY: every class in the snapshot carries its line and flag nation.
  v_snap := world.snapshot()->'ship_classes';
  select count(*) into v_bad from jsonb_array_elements(v_snap) s
   where s->>'line' is distinct from 'PRT' or s->>'line_nation' is distinct from 'PRT';
  if jsonb_array_length(v_snap) <> (select classes from before_0130) or v_bad <> 0 then
    raise exception '0130 self-assert FAIL: the snapshot does not serve every class''s country';
  end if;

  raise notice '0130 self-assert ok: A SHIP HAS A COUNTRY. +3 nations (GUJ, MLB, BAN), each capital a port it holds; % port(s) changed nation (%) — none outside the ten listed, all ten hold theirs (% harbours still of no nation, % before); % building row(s) changed tier, every one an arsenal''s build yard (%), all seven arsenals tier 3, the rule (harbour_buildings) names every build yard; 11 lines, every builder a nation, every line a tier-3 yard in its own countries; % class(es) profiled, the live three PRT / any yard / sizes 1-2-3, tier = least(size, 5); ship_classes rows, count and constraints unchanged (hash); 4 bodies (do_build, building_yard, snapshot, harbour_buildings) reverse to their pre-images, ACLs unmoved, no new entry point, the rule and tables server-only. PROBE (own house, every one of % build yards, through cmd.do_build): the live hulls'' % outcomes equal the pre-image but at the arsenals'' raised tiers; a barca at every yard. CONTROL (nau tagged Dutch): E_WRONG_YARD at % yard(s) outside the Dutch builders and only there, with its figures; the yard screen agrees. Rolled back.',
    v_moved, coalesce(v_ports_l, 'none'), (select count(*) from public.ports where kind = 'HARBOUR' and nation_id is null),
    (select stateless from before_0130), v_raised, coalesce(v_raised_l, 'none'),
    (select count(*) from public.class_profile), v_yards, v_yards * 3,
    (select count(*) from jsonb_each_text(v_ctl->'outcomes') e where e.value = 'E_WRONG_YARD');
end $$;

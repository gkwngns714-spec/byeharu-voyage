-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: every new ask is 0, so no sea asks anything new)
-- 0525 - THE SEAS CAN ASK MORE  (dark twice: 0215's sea_conditions_bite is false, and every new ask ships at 0)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-red-2026-11-25.md, R11, R12, section 3): "add more restrictions like 내파". FIRST PART: the figures and the proof. The asks of
--   section 3.2 are placeholders and are NOT shipped: the proven table is docs/dev-log/2026-11-25-sea-asks-more.md, for the owner to set the figures from.
-- WHAT:
--   THREE FIGURES on wave resistance's scale, derived (as 0215 derived wave) from stats the chain has, by one rule, public.sea_stats_derive(), and stored as data:
--     Ice resistance    a hull: 0.6 x armour + 3 x (6 - draft): small strong hulls; a piece: 0.6 x its armour, and Anchor, Sheet Anchor, Hold Frames, Doubled Frames by grade
--     Current strength  a hull: 0.2 x handling + 2 x speed - 10; a piece: 0.2 x its handling + 2 x its speed (Sails, Rudder, Headsails), and the anchors by grade
--     Light wind        OARS OR SAILS, the better: oared 40 - 2 x size; sails 2 x speed - 12 + rig (lateen 6, mixed 4); a piece: 2 x its speed, and Lateen Re-rig by grade
--   public.sea_stats_class, public.sea_stats_item   the data (a row a class, a row a piece and figure that is not 0); a class or piece made later is read by the rule.
--   world.ship_stat (1 hunk)   answers 'ice', 'current', 'light' (public.ship_sea_stat: her class and her fitted units, a worn one by public.worn_delta). world.ship_stats, read
--                              by every merchant, is not touched.
--   public.fleet_sea_stats     the fleet's three averages, floored, as public.fleet_wave. No single ship type is ever needed for light wind.
--   public.sea_zones.ice_min, current_min, light_min   the asks, 0.
--   public.sea_refusal         SUPERSEDED (dropped and made with a fourth argument, the fleet's three figures, null when not given): still the only place an ask is compared. With
--                              the fourth null, or every ask 0, its answer is the one it gave, to the letter. A sea refused on a new ask adds that ask's two figures.
--   public.sea_more            the gatherer: a COMPANY's fleet asked of the rule with her two floors (the sea she lies in and her capital's, as public.sea_floor has them); a merchant is
--                              never asked; while every sea of the set asks 0 it reads nothing.
--   public.sea_gate, public.sea_closed, world.sea_conditions (2), public.sea_routes, public.seas_relit_ready (2), cmd.refusal_line: by hunks. PASS HOME (0513) covers the new asks by
--                              construction: it lets a homeward leg through whatever refused it, and the pathfinder's closed seas are public.sea_closed's.
-- NOT CHANGED: any ask, switch, knob, raster cell, course, wave, level, merchant's order; world.ship_stats. NOT IN THIS PART: the screens, skills (Handling, Light air).
-- ROWS: two tables of data: 157 rows and about 300; no index but their keys; no cron. 0 new rows a minute.
-- retention: none, bounded by the hull classes and the items (public.sea_stats_class, public.sea_stats_item: one row each, data only a migration writes)
-- budget: no cron job, no autovacuum or fillfactor change. Tick: 0 ms. Lit with the asks at 0: one sum of three columns a sea.
-- LOCKS: ALTER TABLE sea_zones ADD COLUMN x3 (constant default, no rewrite); CREATE TABLE x2; DROP + CREATE public.sea_refusal; CREATE FUNCTION x5; hunks x7 bodies. TIME: a second or
--   two. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, the asks 0 (they are). FULL: the hunks reversed, sea_refusal as 0396 left it, the functions, tables and columns dropped.
-- SELF-ASSERT: every row is the rule's; each hunk once and reversing; no other function or knob moved; server only; every ask 0; THE PROBE (rolled back; its own company, the switch
--   and one ask planted inside it): the rule's answers are unmoved for 8 levels x 64 seas; an ask above her figure refuses E_SEA_CLOSED with its words, one at her figure does not.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['world.ship_stat(uuid,text)', 'public.sea_gate(uuid,uuid,uuid,jsonb)', 'public.sea_closed(uuid,uuid)', 'public.sea_routes(uuid,integer,numeric,jsonb)', 'world.sea_conditions()', 'public.seas_relit_ready()', 'cmd.refusal_line(text,jsonb)']::text[];
  c_new    constant text[] := array['public.sea_refusal(integer,numeric,text[],jsonb)', 'public.sea_stats_derive()', 'public.ship_sea_stat(uuid,text)', 'public.fleet_sea_stats(uuid)', 'public.sea_more(uuid,text[])']::text[];
  c_gone   constant text[] := array['public.sea_refusal(integer,numeric,text[])']::text[];   -- dropped and made again with more to answer (the same arguments)
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_rule text;
  v_me   uuid;
  v_fl   uuid;
  v_to   uuid;
  v_s    jsonb;
  v_r    jsonb;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null and not (u.q = any (c_gone))) then
    raise exception '0525 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0525 refuses: a function it cuts is not in this world: %', (select string_agg(u.q, ' ') from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null);
  end if;


  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_gone) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  alter table public.sea_zones add column ice_min integer not null default 0 check (ice_min between 0 and 200);
  alter table public.sea_zones add column current_min integer not null default 0 check (current_min between 0 and 200);
  alter table public.sea_zones add column light_min integer not null default 0 check (light_min between 0 and 200);
  comment on column public.sea_zones.ice_min is '0525: the Ice resistance this sea asks (public.fleet_sea_stats); 0 asks nothing. The owner sets it.';
  comment on column public.sea_zones.current_min is '0525: the Current strength this sea asks; 0 asks nothing. The owner sets it.';
  comment on column public.sea_zones.light_min is '0525: the Light wind figure this sea asks (oars or sails); 0 asks nothing. The owner sets it.';
  -- retention: none, bounded by the hull classes
  create table public.sea_stats_class (class_code text primary key references public.ship_classes(code), ice integer not null, current integer not null, light integer not null);
  -- retention: none, bounded by the items
  create table public.sea_stats_item (item_code text not null references public.item_profile(item_code), stat text not null check (stat in ('ice', 'current', 'light')), delta integer not null, primary key (item_code, stat));
  alter table public.sea_stats_class enable row level security;
  alter table public.sea_stats_item enable row level security;
  revoke all on public.sea_stats_class, public.sea_stats_item from public, anon, authenticated, service_role;
  select md5(string_agg(k.l || z.code || coalesce(public.sea_refusal(k.l, k.w, array[z.code])::text, '-'), ',' order by k.l, k.w, z.code)) into v_rule
    from public.sea_zones z cross join (values (1, 12::numeric), (3, 30), (6, null), (8, 50), (8, 75), (null, 12), (null, 75)) k(l, w);
  drop function public.sea_refusal(integer, numeric, text[]);
  execute $f$
create function public.sea_refusal(p_title integer, p_wave numeric, p_zones text[], p_sea jsonb default null)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0215: THE ONE RULE. Over the zones in requirement order, the first whose title_min is above her title (skipped
  -- when the title is null: a merchant) or whose wave_min is above her fleet's wave (skipped when null: a title-only
  -- ask) refuses E_SEA_CLOSED — a cmd.refusal with the four figures. Null when every zone is open to her.
  -- 0525: or whose ice, current or light ask is above her fleet's figure of it in p_sea ({ice, current, light}; null, or a figure not given: not asked).
  select cmd.refusal('E_SEA_CLOSED',
           format('%s asks title %s and wave resistance %s — %s', z.name, z.title_min, z.wave_min,
                  concat_ws(' and ',
                            case when p_title is not null then format('you are title %s', p_title) end,
                            case when p_wave is not null then format('your fleet holds %s', p_wave) end)),
           jsonb_build_object('zone', z.code, 'zone_name', z.name, 'needs_title', z.title_min, 'title', p_title,
                              'needs_wave', z.wave_min, 'wave', p_wave,
                              -- 0396: WHICH OF THE TWO IS SHORT, written here beside the rule and nowhere else (false when her figure is null)
                              'short_title', coalesce(z.title_min > p_title, false), 'short_wave', coalesce(z.wave_min > p_wave, false))
           -- 0525: the new asks she is short of, each with its two figures; none otherwise
           || case when z.ice_min > (p_sea->>'ice')::numeric then jsonb_build_object('needs_ice', z.ice_min, 'ice', p_sea->'ice') else '{}'::jsonb end
           || case when z.current_min > (p_sea->>'current')::numeric then jsonb_build_object('needs_current', z.current_min, 'current', p_sea->'current') else '{}'::jsonb end
           || case when z.light_min > (p_sea->>'light')::numeric then jsonb_build_object('needs_light', z.light_min, 'light', p_sea->'light') else '{}'::jsonb end)
    from public.sea_zones z
   where z.code = any(coalesce(p_zones, '{}'::text[]))
     and ((p_title is not null and z.title_min > p_title) or (p_wave is not null and z.wave_min > p_wave)
          or z.ice_min > (p_sea->>'ice')::numeric or z.current_min > (p_sea->>'current')::numeric or z.light_min > (p_sea->>'light')::numeric)
   order by z.ord
   limit 1
$body$
  $f$;
  revoke all on function public.sea_refusal(integer, numeric, text[], jsonb) from public, anon, authenticated, service_role;
  comment on function public.sea_refusal(integer, numeric, text[], jsonb) is
    '0215, 0525: THE ONE RULE of what a sea asks: level, wave resistance and, when given, ice resistance, current strength and light wind. Server only.';
  execute $f$
create function public.sea_stats_derive()
returns table (kind text, code text, stat text, val integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0525: THE ONE DERIVATION of the three sea figures (0215 derived wave the same way: from what a class and a piece already are). See 0525's head for the words.
  select 'class', c.code, s.stat, s.val
    from public.ship_classes c join public.class_profile p on p.class_code = c.code
   cross join lateral (values
     ('ice', round(0.6 * c.armour)::int + 3 * (6 - c.draft)),
     ('current', round(0.2 * c.handling + 2 * c.speed_kn - 10)::int),
     ('light', greatest(round(2 * c.speed_kn)::int - 12 + case c.rig when 'lateen' then 6 when 'mixed' then 4 else 0 end,
                        case when c.rig = 'oared' then 40 - 2 * p.size else 0 end))) s(stat, val)
  union all
  select 'item', ip.item_code, s.stat, s.val
    from public.item_profile ip
   cross join lateral (select coalesce(sum(e.delta) filter (where e.stat = 'armour'), 0) as armour, coalesce(sum(e.delta) filter (where e.stat = 'handling'), 0) as handling,
                              coalesce(sum(e.delta) filter (where e.stat = 'speed'), 0) as speed from public.item_effects e where e.item_code = ip.item_code) e
   cross join lateral (values
     ('ice', round(0.6 * e.armour)::int + coalesce((case ip.base_type when 'Anchor' then array[1,2,2,3,3] when 'Sheet Anchor' then array[2,2,3,3,4]
                                                       when 'Hold Frames' then array[2,3,3,4,5] when 'Doubled Frames' then array[2,3,3,3,3] end)[least(5, greatest(1, ip.grade))], 0)),
     ('current', round(0.2 * e.handling + 2 * e.speed)::int + coalesce((case ip.base_type when 'Anchor' then array[1,1,2,2,3] when 'Sheet Anchor' then array[1,2,2,3,3] end)[least(5, greatest(1, ip.grade))], 0)),
     ('light', round(2 * e.speed)::int + coalesce((case ip.base_type when 'Lateen Re-rig' then array[3,4,4,4,4] end)[least(5, greatest(1, ip.grade))], 0))) s(stat, val)
   where s.val <> 0
$body$
  $f$;
  revoke all on function public.sea_stats_derive() from public, anon, authenticated, service_role;
  comment on function public.sea_stats_derive() is
    '0525: the one derivation of Ice resistance, Current strength and Light wind for every hull class and gear piece. Server only.';

  insert into public.sea_stats_class (class_code, ice, current, light)
  select d.code, max(d.val) filter (where d.stat = 'ice'), max(d.val) filter (where d.stat = 'current'), max(d.val) filter (where d.stat = 'light')
    from public.sea_stats_derive() d where d.kind = 'class' group by d.code;
  insert into public.sea_stats_item (item_code, stat, delta) select d.code, d.stat, d.val from public.sea_stats_derive() d where d.kind = 'item';
  execute $f$
create function public.ship_sea_stat(p_ship uuid, p_stat text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0525: ONE HULL'S SEA FIGURE: her class's and her fitted units' (a worn unit's gain through public.worn_delta, 0158), never under 0. Read through world.ship_stat. A class or a
  -- piece with no row (made since) is read by the rule itself. Null: no such ship.
  select greatest(0, coalesce((select case p_stat when 'ice' then k.ice when 'current' then k.current else k.light end from public.sea_stats_class k where k.class_code = c.code),
                              (select d.val from public.sea_stats_derive() d where d.kind = 'class' and d.code = c.code and d.stat = p_stat), 0)
                     + coalesce((select sum(case when f.wear > 0 and i.delta > 0 then public.worn_delta(i.delta, f.wear) else i.delta end)
                                   from public.fitted_units f join public.sea_stats_item i on i.item_code = f.item_code and i.stat = p_stat where f.ship_id = s.id), 0))::numeric
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = p_ship
$body$
  $f$;
  revoke all on function public.ship_sea_stat(uuid, text) from public, anon, authenticated, service_role;
  comment on function public.ship_sea_stat(uuid, text) is
    '0525: a hull''s ice, current or light figure: class and gear. Read through world.ship_stat. Server only.';
  execute $f$
create function public.fleet_sea_stats(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0525: THE FLEET'S THREE FIGURES, each the floor of her hulls' average, as public.fleet_wave. Null for a fleet with no hull.
  select case when count(*) > 0 then jsonb_build_object('ice', floor(avg(world.ship_stat(s.id, 'ice'))), 'current', floor(avg(world.ship_stat(s.id, 'current'))),
                                                        'light', floor(avg(world.ship_stat(s.id, 'light')))) end
    from public.ships s where s.fleet_id = p_fleet
$body$
  $f$;
  revoke all on function public.fleet_sea_stats(uuid) from public, anon, authenticated, service_role;
  comment on function public.fleet_sea_stats(uuid) is
    '0525: a fleet''s average ice, current and light figures. Server only.';
  execute $f$
create function public.sea_more(p_fleet uuid, p_zones text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0525: THE NEW ASKS OF A SET OF SEAS, put to the one rule (public.sea_refusal) for a company's fleet, with her two floors as public.sea_judge lays them: a sea of the rank she lies in
-- or of her capital's asks her no more than that sea asks. Null: open, a merchant's fleet, no fleet, or no sea of the set asks any (and then nothing else is read).
declare
  v_s jsonb;
  f   record;
  z   record;
  r   jsonb;
begin
  if p_fleet is null or not exists (select 1 from public.sea_zones q where q.code = any (coalesce(p_zones, '{}'::text[])) and q.ice_min + q.current_min + q.light_min > 0)
     or not exists (select 1 from public.fleets x join public.players pl on pl.id = x.player_id and not pl.is_npc where x.id = p_fleet) then
    return null;
  end if;
  v_s := public.fleet_sea_stats(p_fleet);
  if v_s is null then return null; end if;
  select fl.title_min, fl.home_title, l.ice_min as li, l.current_min as lc, l.light_min as ll, h.ice_min as hi, h.current_min as hc, h.light_min as hl into f
    from public.sea_floor(p_fleet, null) fl left join public.sea_zones l on l.code = fl.zone left join public.sea_zones h on h.code = fl.home_zone;
  for z in select q.code, q.title_min from public.sea_zones q where q.code = any (p_zones) and q.ice_min + q.current_min + q.light_min > 0 order by q.ord loop
    r := public.sea_refusal(null, null, array[z.code], jsonb_build_object(
           'ice', greatest((v_s->>'ice')::numeric, case when z.title_min = f.title_min then f.li end, case when z.title_min = f.home_title then f.hi end),
           'current', greatest((v_s->>'current')::numeric, case when z.title_min = f.title_min then f.lc end, case when z.title_min = f.home_title then f.hc end),
           'light', greatest((v_s->>'light')::numeric, case when z.title_min = f.title_min then f.ll end, case when z.title_min = f.home_title then f.hl end)));
    if r is not null then return r; end if;
  end loop;
  return null;
end
$body$
  $f$;
  revoke all on function public.sea_more(uuid, text[]) from public, anon, authenticated, service_role;
  comment on function public.sea_more(uuid, text[]) is
    '0525: what the seas of a set ask beside level and wave, put to public.sea_refusal for a company''s fleet with her floors. Server only.';

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0525 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0525 values
  ('world.ship_stat(uuid,text)', 1,
$h$  v numeric := (world.ship_stats(p_ship) ->> p_stat)::numeric;
$h$,
$h$  -- 0525: the three sea figures have their own reading (public.ship_sea_stat); the eleven are as they were
  v numeric := case when p_stat in ('ice', 'current', 'light') then public.ship_sea_stat(p_ship, p_stat) else (world.ship_stats(p_ship) ->> p_stat)::numeric end;
$h$),
  ('public.sea_gate(uuid,uuid,uuid,jsonb)', 1,
$h$  -- 0513 PASS HOME: refused,$h$,
$h$  v_shut := coalesce(v_shut, public.sea_more(p_fleet, v_zones));   -- 0525: ice, current, light wind
  -- 0513 PASS HOME: refused,$h$),
  ('public.sea_closed(uuid,uuid)', 1,
$h$fl.home_title, fl.home_wave) is not null
$h$,
$h$fl.home_title, fl.home_wave) is not null
      or (z.ice_min + z.current_min + z.light_min > 0 and public.sea_more(p_fleet, array[z.code]) is not null)   -- 0525
$h$),
  ('public.sea_routes(uuid,integer,numeric,jsonb)', 1,
$h$then public.sea_judge(p_title, p_wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave) end as refusal
$h$,
$h$then coalesce(public.sea_judge(p_title, p_wave, array[z.code], fl.title_min, fl.wave_min, fl.home_title, fl.home_wave),
                              case when z.ice_min + z.current_min + z.light_min > 0 then public.sea_more(p_fleet, array[z.code]) end) end as refusal   -- 0525
$h$),
  ('world.sea_conditions()', 1,
$h$                                    cross join lateral (select public.sea_refusal(
$h$,
$h$                                    cross join lateral (select coalesce(case when z.ice_min + z.current_min + z.light_min > 0 then public.sea_more(f.id, array[z.code]) end, public.sea_refusal(   -- 0525
$h$),
  ('world.sea_conditions()', 2,
$h$                                                          array[z.code]) as x) r
$h$,
$h$                                                          array[z.code])) as x) r
$h$),
  ('public.seas_relit_ready()', 1,
$h$public.sea_refusal(v_title, public.fleet_wave(f.id), array[v_zone]) is null;$h$,
$h$public.sea_refusal(v_title, public.fleet_wave(f.id), array[v_zone], public.fleet_sea_stats(f.id)) is null;   -- 0525$h$),
  ('public.seas_relit_ready()', 2,
$h$z.title_min || ':' || z.wave_min, ',' order by z.code)$h$,
$h$z.title_min || ':' || z.wave_min || case when z.ice_min + z.current_min + z.light_min > 0 then ':' || z.ice_min || ':' || z.current_min || ':' || z.light_min else '' end, ',' order by z.code)$h$),
  ('cmd.refusal_line(text,jsonb)', 1,
$h$    return concat_ws(' ', format('%s closed.', p_figures->>'zone_name'),
$h$,
$h$    return concat_ws(' ', format('%s closed.', p_figures->>'zone_name'),
                     -- 0525: the new asks she is short of
                     case when p_figures ? 'needs_ice' then format('Ice resistance %s / %s.', cmd.refusal_figure((p_figures->>'ice')::numeric), cmd.refusal_figure((p_figures->>'needs_ice')::numeric)) end,
                     case when p_figures ? 'needs_current' then format('Current strength %s / %s.', cmd.refusal_figure((p_figures->>'current')::numeric), cmd.refusal_figure((p_figures->>'needs_current')::numeric)) end,
                     case when p_figures ? 'needs_light' then format('Light wind %s / %s.', cmd.refusal_figure((p_figures->>'light')::numeric), cmd.refusal_figure((p_figures->>'needs_light')::numeric)) end,
$h$);

  for v_h in select h.fn from hunks_0525 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0525 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0525 refuses: hunk % of % is found % times in the live body, not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0525 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0525 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0525 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0525 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0525 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when false then 'v' else 's' end) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0525 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key <> all (array[]::text[])) <> v_cfg_before then
    raise exception '0525 self-assert FAIL: a knob this file does not add moved';
  end if;

  -- ── 5. THE DATA IS THE RULE'S; EVERY ASK 0; THE RULE AS IT WAS ──
  if exists (select 1 from public.sea_stats_derive() d left join public.sea_stats_class k on d.kind = 'class' and k.class_code = d.code
              where d.kind = 'class' and (case d.stat when 'ice' then k.ice when 'current' then k.current else k.light end) is distinct from d.val)
     or exists (select 1 from (select d.code, d.stat, d.val from public.sea_stats_derive() d where d.kind = 'item') d full join public.sea_stats_item i on i.item_code = d.code and i.stat = d.stat where d.val is distinct from i.delta)
     or (select count(*) from public.sea_stats_class) <> (select count(*) from public.class_profile) then
    raise exception '0525 self-assert FAIL: a sea figure is not the rule''s';
  end if;
  if exists (select 1 from public.sea_zones z where z.ice_min <> 0 or z.current_min <> 0 or z.light_min <> 0) then
    raise exception '0525 self-assert FAIL: an ask is not 0';
  end if;
  if (select md5(string_agg(k.l || z.code || coalesce(public.sea_refusal(k.l, k.w, array[z.code])::text, '-'), ',' order by k.l, k.w, z.code))
        from public.sea_zones z cross join (values (1, 12::numeric), (3, 30), (6, null), (8, 50), (8, 75), (null, 12), (null, 75)) k(l, w)) is distinct from v_rule then
    raise exception '0525 self-assert FAIL: the rule''s answers moved';
  end if;

  -- ── 6. THE PROBE (its own company; rolled back) ──
  begin
    v_me := public.new_house('00000000-0525-4000-8000-000000000001', 'Casa do Gelo 0525', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
    v_s := public.fleet_sea_stats(v_fl);
    select p.id into v_to from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id join public.sea_zones z on z.code = o.zones[1]
     where p.kind = 'HARBOUR' and z.code = 'AEG' order by p.code limit 1;
    if v_s is null or public.sea_gate(v_me, v_fl, v_to, null) is not null then
      raise exception '0525 self-assert FAIL: before an ask: figures %, gate %', v_s, public.sea_gate(v_me, v_fl, v_to, null);
    end if;
    -- the Aegean is of her capital's rank, whose own sea asks 0: the ask stands
    update public.sea_zones set current_min = (v_s->>'current')::int where code = 'AEG';
    if public.sea_gate(v_me, v_fl, v_to, null) is not null then
      raise exception '0525 self-assert FAIL: an ask at her figure refuses';
    end if;
    update public.sea_zones set current_min = (v_s->>'current')::int + 1 where code = 'AEG';
    v_r := public.sea_gate(v_me, v_fl, v_to, null);
    if v_r->>'code' is distinct from 'E_SEA_CLOSED' or (v_r->'figures'->>'needs_current')::int is distinct from (v_s->>'current')::int + 1
       or v_r->>'sentence' not like 'Aegean Sea closed. Current strength%' or v_r->>'sentence' like '%Wave%' or not 'AEG' = any (public.sea_closed(v_me, v_fl)) then
      raise exception '0525 self-assert FAIL: an ask above her figure: %', v_r;
    end if;
    v_note := format('a new company''s fleet holds %s; %s', v_s, v_r->>'sentence');
    raise exception using errcode = 'ZX525', message = 'PROBE_ROLLBACK_0525';
  exception when sqlstate 'ZX525' then
    v_lived := true;
  end;
  if not v_lived or exists (select 1 from public.players p where p.company_name = 'Casa do Gelo 0525') then
    raise exception '0525 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0525 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0525 self-assert ok: THE SEAS CAN ASK MORE (dark: every ask 0). Every hunk once and reversing; no other function or knob moved; the data is the rule, the one rule keeps its answers. %. % ms.', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights combat_rounds_enabled)
-- 0521 - COMBAT ROUNDS  (dark: combat_rounds_enabled. Slice `combat-rounds`, docs/design/rounds-2026-11-25.md section 4.1)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R5, R6): send a fleet to a sea, destroy the pirates, that is one round; show what a round costs, not a chance; no RUN.
--
-- THE FIGHT IS public.tick_fight AND NOTHING ELSE (0435): her hulls as they are (voyage.fleet_hulls) close on the pirates of that sea
--   (voyage.raider_hulls of voyage.sea_danger x 40, the hazard's own strength), both with the stance FIGHT (no a_flee, no RUN). At Send (and for a quote)
--   the server plays 8 fights (4 for a fleet over 3 hulls: public.round_fights) and freezes them; each round is one of them by voyage.rng (fleet, round, Send). So
--   12 hours of rounds cost 8 fights, once, and the settle fights nothing.
-- THE RUN IS ARITHMETIC ON THAT SEQUENCE (public.round_sequence, at Send): hull, hands, won or beaten a round, round by round; it stops after the round that
--   leaves the hull under stop.hull (default 40 per cent, decided by default), after a round she was BEATEN OFF in, before the round that would take her
--   hands under MIN, or at any bound of 0518 and 0520. A late settle and a prompt one still agree.
-- WHAT IS SERVED: a round's MEAN cost (hull, hands, food, water, ammo). Neither the fights nor any share won is served (asserted).
-- HANDS: a round loses half the share of hull it lost, of the hands she left with (knob round_hand_share 0.1).
-- Never a company, a merchant or a navy: the side she closes on is no ship's row. A sea with no pirates (danger 0), a fleet with no guns: refused.
-- THE COST of a Send (PGlite, docs/dev-log/2026-11-25-combat-rounds.md): under 200 ms for every fleet against what a sea can hold (strength at most 40).
-- ROWS as 0518's (the frozen rounds add up to 2 KB to a run's row). -- budget: none more. -- retention: none (no table).
-- LOCKS: one row of data, CREATE FUNCTION x4, CREATE OR REPLACE x6 by hunks. BUDGET: 60 s, 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): combat_rounds_enabled false. FULL: a migration reversing the hunks and deleting the row.
-- VERSION: 0521 (after 0520).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.round_terms(uuid,text,jsonb)', 'public.round_settle(uuid,timestamp with time zone)', 'public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 'public.round_run_card(uuid)', 'public.round_job_param(uuid,uuid,jsonb)', 'public.round_plan(uuid)', 'public.round_works_for(uuid,uuid)', 'public.fleet_job_set_for(uuid,uuid,text,jsonb)']::text[];
  c_new    constant text[] := array['public.combat_rounds_on()', 'public.round_fights(uuid,uuid)', 'public.round_sequence(uuid,jsonb,jsonb,jsonb,timestamptz)', 'public.round_hull(uuid,numeric)', 'public.round_fights_sig(uuid,uuid)', 'public.round_fights_keep(uuid,uuid,jsonb)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['combat_rounds_enabled', 'round_hull_stop', 'round_hand_share']::text[];
  c_ua     constant uuid := '00000000-0521-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);
  -- ── 0. GUARD ──
  if to_regprocedure('public.combat_rounds_on()') is not null then
    raise exception '0521 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.tick_fight(uuid,jsonb,jsonb,jsonb)', 'public.round_ammo_need(uuid,numeric)', 'voyage.raider_hulls(numeric)', 'voyage.sea_danger(uuid,timestamp with time zone)']::text[]) f where to_regprocedure(f) is null) then
    raise exception '0521 refuses: what it stands on is not in this world';
  end if;
  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0521 (fn text primary key, def text) on commit drop;
  insert into pre_0521 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  -- ── 2. THE KNOBS AND THE DATA ──
  insert into public.world_config (key, value, description) values
    ('combat_rounds_enabled', 'false'::jsonb, '0521: THE SWITCH (the owner''s). true: the work "pirates" may be sent on (while rounds_enabled).'),
    ('round_hull_stop', '40'::jsonb, '0521: the hull, in per cent of whole, under which a combat run ends when the player set none (decided by default, 2026-11-25).'),
    ('round_hand_share', '0.1'::jsonb, '0521: the share of a round''s hull loss that its hands lose.');
  -- retention: none, bounded by construction: one row a fleet, gone with it
  create table public.round_fights_kept (fleet_id uuid primary key references public.fleets(id) on delete cascade, sig text not null, guns numeric not null, fights jsonb not null);
  comment on table public.round_fights_kept is '0521: the fights a fleet would have, kept while nothing of her has changed by a tenth (public.round_fights_sig). Server only.';
  alter table public.round_fights_kept enable row level security;
  revoke all on table public.round_fights_kept from public, anon, authenticated;
  insert into public.round_works (code, ord, kind, word, skill, level, seconds, food_days, water_days, crew_pct, ammo, lit_by)
  values ('pirates', 1, 'combat', 'Pirates', 'combat', 1, 600, 0.4, 0.4, 0, 0.01, 'combat_rounds_enabled');

  -- ── 3. THE RULES ──
  execute $f$
create function public.combat_rounds_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0521: THE SWITCH, read once: world_config combat_rounds_enabled.
  select public.wc('combat_rounds_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.round_fights(p_fleet uuid, p_sea uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0521: THE FIGHTS A FLEET WOULD HAVE in a sea, played once by public.tick_fight: {strength, guns, fights: [{l: the share of her hull lost, w: won, b: beaten off}]}.
-- 8 fights, 4 for a fleet over 3 hulls (the cost of a fight grows with the hulls). The same fleet in the same sea has the same fights: those kept for her
-- (public.round_fights_kept, by public.round_fights_sig) while nothing of her has changed by a tenth. Writes nothing.
declare
  v_h    jsonb;
  v_sig  text := public.round_fights_sig(p_fleet, p_sea);
  v_str  numeric := split_part(v_sig, ':', 1)::numeric;
  v_kept jsonb := (select jsonb_build_object('strength', v_str, 'guns', k.guns, 'sig', k.sig, 'fights', k.fights) from public.round_fights_kept k where k.fleet_id = p_fleet and k.sig = v_sig);
  v_guns numeric;
  v_n    int;
  r      jsonb;
  v_out  jsonb := '[]'::jsonb;
  v_l    numeric;
begin
  if v_kept is not null then
    return v_kept;
  end if;
  v_h := voyage.fleet_hulls(p_fleet);
  select coalesce(sum((e->>'attack')::numeric), 0), case when count(*) > 3 then 4 else 8 end into v_guns, v_n from jsonb_array_elements(coalesce(v_h, '[]'::jsonb)) e;
  if v_guns <= 0 or v_str <= 0 then
    return jsonb_build_object('strength', v_str, 'guns', v_guns, 'fights', v_out);
  end if;
  for i in 1 .. v_n loop
    r := public.tick_fight(md5(p_fleet::text || ':' || p_sea::text || ':' || i)::uuid, voyage.raider_hulls(v_str), v_h, '{"a_ai": "FIGHT", "b_ai": "FIGHT"}'::jsonb) -> 'r';
    v_l := round(1 - (r #>> '{hull,b}')::numeric / greatest((r #>> '{hull,b_start}')::numeric, 0.0001), 4);
    v_out := v_out || jsonb_build_array(jsonb_build_object('l', least(1, greatest(0, v_l)),
               'w', r->>'outcome' in ('PLUNDERED', 'RANSOM') or (r #>> '{hull,a}')::numeric <= 0,
               'b', coalesce((r->>'broke_off')::boolean, false) or (r #>> '{hull,b}')::numeric <= 0));
  end loop;
  return jsonb_build_object('strength', v_str, 'guns', v_guns, 'sig', v_sig, 'fights', v_out);
end
$body$
  $f$;
  execute $f$
create function public.round_fights_sig(p_fleet uuid, p_sea uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0521: WHAT THE FIGHTS DEPEND ON, coarse enough to be kept: the sea's pirates (danger x 40 in steps of 2, at least 2 where there are any) and each hull's
  -- attack, armour and reach, its hull and its hands by tenths.
  select (case when z.d > 0 then greatest(2, round(z.d * 20) * 2) else 0 end)::text || ':' ||
         md5(coalesce((select string_agg(concat_ws('/', e->>'attack', e->>'armour', e->>'reach', e->>'accuracy', e->>'tier', round((e->>'hull')::numeric / greatest((e->>'maxd')::numeric, 1) * 10), round((e->>'crew')::numeric / 10)), ',' order by e->>'id')
                         from jsonb_array_elements(voyage.fleet_hulls(p_fleet)) e), ''))
    from (select coalesce(voyage.sea_danger(p_sea, now()), 0) as d) z
$body$
  $f$;
  execute $f$
create function public.round_fights_keep(p_fleet uuid, p_sea uuid, p_x jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0521: keep the fights of a fleet (one row a fleet): given, or played here (where a job of combat is set, outside any tick), so the tick's Send plays none.
declare
  v_x jsonb := coalesce(p_x, public.round_fights(p_fleet, p_sea));
begin
  if v_x ? 'sig' and jsonb_array_length(coalesce(v_x->'fights', '[]'::jsonb)) > 0
     and not exists (select 1 from public.round_fights_kept k where k.fleet_id = p_fleet and k.sig = v_x->>'sig') then
    insert into public.round_fights_kept (fleet_id, sig, guns, fights) values (p_fleet, v_x->>'sig', (v_x->>'guns')::numeric, v_x->'fights')
    on conflict (fleet_id) do update set sig = excluded.sig, guns = excluded.guns, fights = excluded.fights;
  end if;
end
$body$
  $f$;
  execute $f$
create function public.round_sequence(p_fleet uuid, p_terms jsonb, p_fights jsonb, p_stop jsonb, p_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0521: THE ROUNDS OF ONE SEND, frozen: round n is one of the fights by voyage.rng (fleet, n, the Send's instant). The terms with `most` and `why` cut to it and
-- `fight`: {l: [hull lost a round], c: [hands a round], w: [won]}. The stops: the hull under stop.hull after a round (hull), beaten off in it (beaten),
-- the hands under MIN in the next (crew), or what 0518's terms already say. Writes nothing.
declare
  v_hull numeric := 1 - public.fleet_damage_pct(p_fleet) / 100.0;
  v_floor numeric := coalesce((p_stop->>'hull')::numeric, public.wc_num('round_hull_stop')) / 100.0;
  v_crew int := (p_terms->>'crew0')::int;
  v_min  int := (p_terms->>'min')::int;
  v_k    int := jsonb_array_length(p_fights);
  v_hs   numeric := public.wc_num('round_hand_share');
  v_l    jsonb := '[]'::jsonb;
  v_c    jsonb := '[]'::jsonb;
  v_w    jsonb := '[]'::jsonb;
  v_most int := 0;
  v_why  text := p_terms->>'why';
  e      jsonb;
  v_lost int;
begin
  for n in 1 .. (p_terms->>'most')::int loop
    e := p_fights -> least(v_k - 1, floor(voyage.rng(p_fleet, n, 'round:' || extract(epoch from p_at)::text) * v_k)::int);
    v_lost := round((e->>'l')::numeric * v_hs * (p_terms->>'crew0')::int)::int;
    if v_crew - v_lost < v_min then
      v_why := 'crew';
      exit;
    end if;
    v_most := n;
    v_crew := v_crew - v_lost;
    v_hull := v_hull - (e->>'l')::numeric;
    v_l := v_l || jsonb_build_array(e->'l');
    v_c := v_c || jsonb_build_array(v_lost);
    v_w := v_w || jsonb_build_array(case when (e->>'w')::boolean then 1 else 0 end);
    if (e->>'b')::boolean then
      v_why := 'beaten';
      exit;
    end if;
    if v_hull < v_floor then
      v_why := 'hull';
      exit;
    end if;
  end loop;
  return p_terms || jsonb_build_object('most', v_most, 'why', v_why, 'fight', jsonb_build_object('l', v_l, 'c', v_c, 'w', v_w));
end
$body$
  $f$;
  execute $f$
create function public.round_hull(p_fleet uuid, p_share numeric)
returns void
language sql
security definer
set search_path = public, pg_temp
as $body$
  -- 0521: the rounds' damage: p_share of each hull's whole, never under one per cent of it (a run is not how a ship is lost).
  update public.ships s set durability = greatest(least(s.durability, (select sb.durability from public.ship_base(s.id) sb) * 0.01),
                                                  round(s.durability - (select sb.durability from public.ship_base(s.id) sb) * p_share, 2))
   where s.fleet_id = p_fleet and p_share > 0
$body$
  $f$;
  foreach v_def in array c_new || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;
  foreach v_def in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_def::regprocedure);
  end loop;
  -- ── 4. THE HUNKS ──
  create temp table hunks_0521 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0521 values
  ('public.round_terms(uuid,text,jsonb)', 1,
$h$  v_am    numeric;   -- 0520: units of each ammo good a round
begin
$h$,
$h$  v_am    numeric;   -- 0520: units of each ammo good a round
  v_x     jsonb;     -- 0521: the fights of a combat work (public.round_fights)
  v_hl    numeric := 0;
begin
$h$),
  ('public.round_terms(uuid,text,jsonb)', 2,
$h$  v_am := public.round_ammo_need(p_fleet, w.ammo);   -- 0520
$h$,
$h$  v_am := public.round_ammo_need(p_fleet, w.ammo);   -- 0520
  -- 0521: a combat round's mean cost: the hull it loses and the hands with it (the fights themselves are never in a quote)
  if w.kind = 'combat' and not coalesce(p_stop, '{}'::jsonb) ? 'light' then
    v_x := public.round_fights(p_fleet, (select h.sea_id from public.fleets f join public.ports h on h.id = f.port_id where f.id = p_fleet));
    v_hl := coalesce((select round(avg((e->>'l')::numeric), 4) from jsonb_array_elements(v_x->'fights') e), 0);
    v_c := round(v_crew * v_hl * public.wc_num('round_hand_share'), 4);
  end if;
$h$),
  ('public.round_terms(uuid,text,jsonb)', 3,
$h$'food', v_fr, 'water', v_wr, 'ammo', v_am,
$h$,
$h$'food', v_fr, 'water', v_wr, 'ammo', v_am, 'hull', v_hl,
$h$),
  ('public.round_terms(uuid,text,jsonb)', 4,
$h$'most', v_most::int, 'why', v_why, 'level', v_lv);$h$,
$h$'most', v_most::int, 'why', v_why, 'level', v_lv)
         || case when w.kind = 'combat' then jsonb_build_object('guns', v_x->'guns', 'strength', v_x->'strength', 'fights', v_x) else '{}'::jsonb end;   -- 0521$h$),
  ('public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 1,
$h$  t := public.round_terms(p_fleet, p_work, coalesce(p_stop, '{}'::jsonb));
$h$,
$h$  t := public.round_terms(p_fleet, p_work, coalesce(p_stop, '{}'::jsonb));
  if w.kind = 'combat' then   -- 0521: guns, pirates, then the rounds themselves, frozen
    if coalesce((t->>'guns')::numeric, 0) <= 0 then
      perform cmd.refuse('E_NO_GUNS', format('%s carries no guns', f.name));
    end if;
    if coalesce((t->>'strength')::numeric, 0) <= 0 then
      perform cmd.refuse('E_NO_PIRATES', 'no pirates sail this sea');
    end if;
    if (t->>'most')::int >= 1 then
      perform public.round_fights_keep(p_fleet, v_sea, t->'fights');
      t := public.round_sequence(p_fleet, t - 'fights', t #> '{fights,fights}', coalesce(p_stop, '{}'::jsonb), p_at);
    end if;
  end if;
$h$),
  ('public.round_send_for(uuid,uuid,text,jsonb,timestamp with time zone)', 2,
$h$  return jsonb_build_object('ok', true, 'fleet', p_fleet, 'terms', t);
$h$,
$h$  return jsonb_build_object('ok', true, 'fleet', p_fleet, 'terms', t - 'fight' - case when w.kind = 'combat' then 'most' else '' end - case when w.kind = 'combat' then 'why' else '' end);   -- 0521: what a fight will do is not told
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 1,
$h$    v_hand := (floor(v_c * (r.booked + v_n)) - floor(v_c * r.booked))::int;
$h$,
$h$    v_hand := (floor(v_c * (r.booked + v_n)) - floor(v_c * r.booked))::int;
    if r.terms ? 'fight' then   -- 0521: the rounds frozen at Send: their hands and their hull
      select coalesce(sum((r.terms #>> array['fight', 'c', (g - 1)::text])::int), 0) into v_hand from generate_series(r.booked + 1, r.booked + v_n) g;
      perform public.round_hull(p_fleet, (select sum((r.terms #>> array['fight', 'l', (g - 1)::text])::numeric) from generate_series(r.booked + 1, r.booked + v_n) g));
    end if;
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 2,
$h$'crew', (floor(v_c * g) - floor(v_c * (g - 1)))::int), 1000000 + g
$h$,
$h$'crew', (floor(v_c * g) - floor(v_c * (g - 1)))::int)
                         || case when r.terms ? 'fight' then jsonb_build_object('crew', r.terms #> array['fight', 'c', (g - 1)::text], 'hull', r.terms #> array['fight', 'l', (g - 1)::text],
                                                                                'won', r.terms #> array['fight', 'w', (g - 1)::text]) else '{}'::jsonb end, 1000000 + g   -- 0521
$h$),
  ('public.round_settle(uuid,timestamp with time zone)', 3,
$h$              'crew', floor((r.terms->>'crew')::numeric * r.booked)));
$h$,
$h$              'crew', case when r.terms ? 'fight' then (select coalesce(sum(q.c::int), 0) from jsonb_array_elements_text(r.terms #> '{fight,c}') q(c)) else floor((r.terms->>'crew')::numeric * r.booked) end));
$h$),
  ('public.round_run_card(uuid)', 1,
$h$'most', r.terms->'most', 'why', r.terms->>'why', 'next_at'$h$,
$h$'most', case when r.terms ? 'fight' then null else r.terms->'most' end, 'why', case when r.terms ? 'fight' then null else r.terms->>'why' end, 'next_at'$h$),
  ('public.round_run_card(uuid)', 2,
$h$'crew', r.terms->'crew'),
$h$,
$h$'crew', r.terms->'crew', 'ammo', r.terms->'ammo', 'hull', r.terms->'hull'),
$h$),
  ('public.round_run_card(uuid)', 3,
$h$'sent_at', r.sent_at, 'stop_at', r.stop_at,$h$,
$h$'sent_at', r.sent_at, 'stop_at', case when r.terms ? 'fight' and r.state = 'out' then null else r.stop_at end,$h$),
  ('public.round_job_param(uuid,uuid,jsonb)', 1,
$h$('rounds', 1, 999, 'the rounds')) t($h$,
$h$('rounds', 1, 999, 'the rounds'), ('hull', 10, 95, 'the hull to leave at')) t($h$),
  ('public.round_works_for(uuid,uuid)', 1,
$h$public.round_terms(p_fleet, w.code, '{}'::jsonb))$h$,
$h$public.round_terms(p_fleet, w.code, '{}'::jsonb) - 'fights')$h$),
  ('public.fleet_job_set_for(uuid,uuid,text,jsonb)', 1,
$h$    v_p := public.round_job_param(p_player, p_fleet, p_params);   -- 0519
$h$,
$h$    v_p := public.round_job_param(p_player, p_fleet, p_params);   -- 0519
    if (select w.kind from public.round_works w where w.code = v_p->>'work') = 'combat' then   -- 0521: her fights are played now, at her press, not in the tick
      perform public.round_fights_keep(p_fleet, (select h.sea_id from public.ports h where h.code = v_p->>'base'), null);
    end if;
$h$),
  ('public.round_plan(uuid)', 1,
$h$  t := public.round_terms(p_fleet, j.params->>'work', j.params->'stop');
$h$,
$h$  t := public.round_terms(p_fleet, j.params->>'work', j.params->'stop' || '{"light": true}'::jsonb);   -- 0521: no fight is played to plan
  -- 0521: a hull already under the one to leave at, and no yard here to mend it: she waits
  if t->>'kind' = 'combat' and 100 - v_dmg <= coalesce((j.params #>> '{stop,hull}')::numeric, public.wc_num('round_hull_stop')) then
    return jsonb_build_object('wait', 'range', 'sentence', format('hull at %s %%, mend her first', 100 - v_dmg));
  end if;
$h$);

  for x in select distinct h.fn from hunks_0521 h loop
    v_pre := (select p.def from pre_0521 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0521 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0521 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0521 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0521 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0521 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new || c_doors) u(q)))) <> v_fn_before then
    raise exception '0521 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0521 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.combat_rounds_on() then
    raise exception '0521 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0521 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;

  -- ── 5. THE PROBE (its own company, work, stores; rolled back) ──
  begin
    declare
      v_pl uuid; v_fl uuid; v_sea uuid; d text; t jsonb; a jsonb; b jsonb; i int; r record; s jsonb; v_e text; v_c0 int; v_ms numeric; v_t timestamptz; n int; v_seq jsonb;
    begin
      v_pl := public.new_house(c_ua, 'Casa da Prova 0521', 'PRT');
      select f.id, h.sea_id into v_fl, v_sea from public.fleets f join public.ports h on h.id = f.port_id where f.player_id = v_pl;
      update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled');
      update public.ships s set class_id = (select k.id from public.ship_classes k where k.code = 'xebec') where s.fleet_id = v_fl;
      update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 60, water_t = 90, durability = (select sb.durability from public.ship_base(s.id) sb) where s.fleet_id = v_fl;
      begin
        perform public.round_send_for(v_pl, v_fl, 'pirates', '{}', now());
      exception when sqlstate 'P0001' then d := sqlerrm;
      end;
      update public.world_config set value = 'true'::jsonb where key = 'combat_rounds_enabled';
      update public.seas q set piracy_index = 0.2 where q.id = v_sea;
      delete from public.sea_pressure q where q.sea_id = v_sea;
      v_t := clock_timestamp();
      t := public.round_terms(v_fl, 'pirates', '{}');
      v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000);
      -- at once and one by one: the same hull, hands and log
      for i in 1 .. 2 loop
        begin
          perform public.round_send_for(v_pl, v_fl, 'pirates', '{"hull": 70, "days": 0}', now());
          select zr.* into r from public.round_runs zr where zr.fleet_id = v_fl;
          s := r.terms;
          if i = 2 then
            for k in 1 .. (s->>'most')::int loop
              perform public.round_settle(v_fl, now() + make_interval(secs => k * 600.0));
            end loop;
          end if;
          perform cmd.advance(v_fl, now() + interval '3 days');
          select zr.* into r from public.round_runs zr where zr.fleet_id = v_fl;
          raise exception using errcode = 'ZY521', message = jsonb_build_object('state', r.state, 'booked', r.booked, 'ended', r.ended, 'log', r.log, 'dmg', public.fleet_damage_pct(v_fl),
            'crew', (select sum(q.crew) from public.ships q where q.fleet_id = v_fl), 'terms', s)::text;
        exception when sqlstate 'ZY521' then
          if i = 1 then a := sqlerrm::jsonb; else b := sqlerrm::jsonb; end if;
        end;
      end loop;
      select sum(q.crew) into v_c0 from public.ships q where q.fleet_id = v_fl;
      -- the stops, on fights written here (no dice of the world is asked a sign)
      v_seq := jsonb_build_object(
        'hull', public.round_sequence(v_fl, '{"most": 72, "why": "cap", "crew0": 100, "min": 10}', '[{"l": 0.05, "w": true, "b": false}]', '{"hull": 70}', now()),
        'beaten', public.round_sequence(v_fl, '{"most": 72, "why": "cap", "crew0": 100, "min": 10}', '[{"l": 0.16, "w": false, "b": true}]', '{}', now()),
        'crew', public.round_sequence(v_fl, '{"most": 72, "why": "cap", "crew0": 100, "min": 92}', '[{"l": 0.02, "w": true, "b": false}]', '{"hull": 10}', now()),
        'cap', public.round_sequence(v_fl, '{"most": 5, "why": "food", "crew0": 100, "min": 10}', '[{"l": 0.0, "w": true, "b": false}]', '{}', now()));
      update public.seas q set piracy_index = 0 where q.id = v_sea;
      begin
        perform public.round_send_for(v_pl, v_fl, 'pirates', '{}', now());
      exception when sqlstate 'P0001' then v_e := sqlerrm;
      end;
      raise exception using errcode = 'ZX521', message = jsonb_build_object('dark', d, 'none', v_e, 'ms', v_ms, 'quote', t - 'fights', 'a', a - 'log', 'b', b - 'log', 'same', a = b, 'kept', a #> '{terms,fight}' is not null, 'c0', v_c0,
        'lines', jsonb_array_length(a->'log'), 'line', a #> '{log,-1}', 'seq', (select jsonb_object_agg(e.key, jsonb_build_array(e.value->'most', e.value->'why')) from jsonb_each(v_seq) e))::text;
    end;
  exception when sqlstate 'ZX521' then v_l := sqlerrm::jsonb;
  end;
  if v_l is null or not coalesce(v_l->>'dark' ~ '^E_NOT_IN_USE' and v_l->>'none' ~ '^E_NO_PIRATES' and not (v_l->'quote' ? 'fight') and (v_l->>'kept')::boolean and (v_l #>> '{quote,hull}')::numeric > 0 and (v_l->>'same')::boolean
     and v_l #>> '{a,state}' = 'home' and v_l #>> '{a,booked}' = v_l #>> '{a,terms,most}' and v_l #>> '{a,ended}' in ('hull', 'beaten', 'crew', 'food', 'water', 'cap')
     and (v_l #>> '{a,dmg}')::numeric > 0 and (v_l->'line') ?& array['hull', 'won', 'crew'] and (v_l->>'ms')::numeric < 1500
     and v_l->'seq' = '{"hull": [7, "hull"], "beaten": [1, "beaten"], "crew": [8, "crew"], "cap": [5, "food"]}'::jsonb, false) then
    raise exception '0521 self-assert FAIL: the probe: %', v_l;
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0521') or public.combat_rounds_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0521 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0521 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0521 self-assert ok: COMBAT ROUNDS (dark). Hunks once and reversing; no other function moved; four functions server only. Probe (rolled back): % . % ms.', v_l, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0521;
  drop table pre_0521;
end $m$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0145 — MERCHANTS GIVE FOR THEIR COUNTRY  (docs/INFLUENCE.md slice I3, + owner addition A4)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- O2 (2026-10-17): merchants invest too, for their own countries. A4 (2026-10-17): "distribute them
-- if one side is too over-populated" — and the older rule (OWNER_REQUESTS row 119): "powerful and
-- rich countries will have more ships compared to the ones that are poor".
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE MERCHANT COMPANIES ARE SPREAD ACROSS THE 23 COUNTRIES (A4) — once, here, as data. Each
--     country's quota is 0105's rule (Σ dev_commerce + dev_industry over its harbours — today's
--     holder, public.port_nation — over all, × the companies there are), WITH A CAP (no country more
--     than 12 % of the companies) and A FLOOR (every country at least 12), water-filled: a capped or
--     floored country is fixed, the rest re-shared by the same weights, until it stands; largest
--     remainders round it to the exact total. Companies move from the countries above their quota
--     to those below: a company re-flagged takes the new country (players.nation_id), its ink
--     (0105's nation → ink table, three added), and a HOME (npc_houses.home_port_id — the harbour
--     that refounds it, written by npc_found and read by npc_tend_houses alone) at a harbour of the
--     new country ON ITS OWN LOOP; only where no loop reaches the country is the home its capital.
--     One NATION_CHANGED event per company (reason 'rebalance'). No player's company, purse, ship
--     or cargo is touched; no route changes.
-- (2) WHERE A MERCHANT GIVES (D12, O2). public.npc_invest keeps WHO (purse > npc_invest_above ×
--     capital), HOW MUCH (down to npc_invest_keep × capital) and HOW MANY (npc_invest_max_per_hour).
--     Lit (public.influence_on()), WHERE is public.npc_closest_race(company): the contestable stop
--     of her loop where her country is in the closest race — to flip a city (attack:
--     flip_lead × holder / hers − 1), to claim a free one (claim_min / hers − 1), or not to be
--     flipped (defend: flip_lead × hers / best rival − 1, never below 0). She buys shares there if
--     offered (invest_for) and gives the rest as a gift (donate_for, under D7's cap). With no race
--     on her loop (her country has given nowhere yet) 0123's rule stands, byte for byte. Dark, the
--     function answers exactly as 0123's did (asserted, run against its own pre-image).
-- (3) THE RECEIPT counts `donated` (npc_tend_houses, npc_tend_sum); the merchant card serves
--     `company.influence` (her influence by city and country, most first).
-- (4) Knobs influence_flip_lead 1.10 and influence_claim_min 10,000 (D5 — the daily count, I4,
--     reads them too).
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * NOT THE OWNER'S — the cap 12 % and the floor 12 companies (measured on prod 2026-10-17:
--   ESP 205 · PRT 122 · OTT 96 · … · RUS 8 · MLB / GUJ / BAN 0, of 821). Spain falls to the cap,
--   Portugal and the Ottomans near it, the three empty countries get theirs.
-- * NOT THE OWNER'S — the ink of the three countries 0105 had none for: Gujarat ott, Malabar east,
--   Banten east. A re-flagged company keeps its NAME (its people emigrated; the roster generator
--   has no names for Gujarat, Malabar or Banten).
-- * D12's gap formula as written in the plan compared defence the wrong way round (her /
--   (lead × rival)); built as the plan's words say: the smallest distance to flipping or to being
--   flipped.
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- (a) The re-cuts reverse to their pre-images; ACL unmoved. (b) The rebalance: the total of
--     companies unchanged; every country inside [floor, cap] and at its quota; every moved company's
--     home a harbour of its new country (on its loop, but for the counted capital fallbacks); its
--     ink its country's; every ledger reconciles; no player company moved. (c) Dark: npc_invest
--     answers and writes exactly as its pre-image on a probe of rich companies. (d) Lit: a probe
--     merchant whose country leads one stop by a margin and trails another by 5 % gives at the
--     trailing one — shares, then a gift up to the cap; with no race on her loop she picks what
--     0123's rule picks. Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- UPDATE on the moved companies' players / npc_houses rows (one row each, NOWAIT-free: a merchant
-- row is written by the reconcile, which the deploy runbook stops — unwind_the_clock()).
-- CREATE OR REPLACE FUNCTION. The probes' writes are rolled back.
--
-- ROLLBACK: the move is data (each company's NATION_CHANGED event records from / to and the old
-- home); the where-rule is dark until influence_switch(true).
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once: public.npc_invest (0123), public.npc_tend_houses (0137), public.npc_tend_sum (0137),
-- world.npc_fleet_card (0131). VERSION: 0145. Applies on 0144.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0145(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0145 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('public.npc_invest(timestamp with time zone)'),
               ('public.npc_tend_houses(timestamp with time zone)'),
               ('public.npc_tend_sum(jsonb, jsonb)'),
               ('world.npc_fleet_card(uuid)')) f(fn);

-- the old npc_invest under a pg_temp name, for the side-by-side proof
do $$
declare
  v_def text := replace((select def from defs_before_0145 where fn like 'public.npc_invest%'),
                        'CREATE OR REPLACE FUNCTION public.npc_invest(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_invest_old_0145(');
begin
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION pg_temp.npc_invest_old_0145(') <> 1 then
    raise exception '0145 self-assert FAIL: the old copy of public.npc_invest was not renamed';
  end if;
  execute v_def;
end $$;

-- ── 2. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('influence_flip_lead', to_jsonb(1.10),
   '0145 (D5): a challenger takes a contested city only when its influence there is at least this '
   'times the holder''s. Read by the merchants'' where-rule (0145) and the daily count (I4).'),
  ('influence_claim_min', to_jsonb(10000),
   '0145 (D5): a city no country holds goes to the leader once the leader has at least this much '
   'influence there. Read by the merchants'' where-rule (0145) and the daily count (I4).')
on conflict (key) do nothing;

-- ── 3. THE COMPANIES ARE SPREAD (A4) ───────────────────────────────────────────────────────────
create temp table ink_0145 (nation text primary key, ink text not null) on commit drop;
insert into ink_0145 values
  ('PRT', 'prt'), ('ESP', 'esp'), ('NLD', 'nld'), ('ENG', 'eng'), ('FRA', 'eng'), ('DNK', 'eng'),
  ('HAN', 'han'), ('GEN', 'ita'), ('VEN', 'ita'), ('OTT', 'ott'), ('MUG', 'ott'), ('PER', 'ott'),
  ('MNG', 'east'), ('JPN', 'east'), ('JOS', 'east'), ('AYU', 'east'),
  ('POL', 'han'), ('SWE', 'han'), ('RUS', 'han'), ('MAR', 'ott'),
  -- 0145: the three countries 0105 founded no company for
  ('GUJ', 'ott'), ('MLB', 'east'), ('BAN', 'east');

create temp table quota_0145 on commit drop as
select n.id as nation_id, n.code, n.capital_port_code,
       coalesce((select sum(p.dev_commerce + p.dev_industry) from public.ports p
                  where p.kind = 'HARBOUR' and public.port_nation(p.id) = n.id), 0)::numeric as w,
       (select count(*) from public.npc_houses h join public.players pl on pl.id = h.player_id
         where pl.nation_id = n.id)::int as before,
       null::numeric as q,
       null::int as quota,
       false as fixed
  from public.nations n;

do $$
declare
  c_cap_share constant numeric := 0.12;   -- NOT the owner's: no country above 12 % of the companies
  c_floor     constant int := 12;         -- NOT the owner's: every country at least 12
  v_n     int := (select sum(before) from quota_0145);
  v_cap   int := round(c_cap_share * (select sum(before) from quota_0145));
  v_moved boolean := true;
  v_rest  numeric;
  v_w     numeric;
  v_short int;
begin
  if (select count(*) from quota_0145 where code not in (select nation from ink_0145)) > 0 then
    raise exception '0145 self-assert FAIL: a country has no ink';
  end if;
  -- water-fill: fix whoever the proportional share puts above the cap or under the floor, re-share
  while v_moved loop
    v_moved := false;
    select v_n - coalesce(sum(quota) filter (where fixed), 0), coalesce(sum(w) filter (where not fixed), 0)
      into v_rest, v_w from quota_0145;
    update quota_0145 set q = v_rest * w / nullif(v_w, 0) where not fixed;
    update quota_0145 set fixed = true, quota = v_cap, q = v_cap where not fixed and q > v_cap;
    if found then v_moved := true; continue; end if;
    update quota_0145 set fixed = true, quota = c_floor, q = c_floor where not fixed and q < c_floor;
    if found then v_moved := true; end if;
  end loop;
  -- largest remainders to the exact total
  update quota_0145 set quota = floor(q)::int where not fixed;
  v_short := v_n - (select sum(quota) from quota_0145);
  update quota_0145 x set quota = x.quota + 1
    from (select nation_id from quota_0145 where not fixed order by q - floor(q) desc, code limit v_short) t
   where x.nation_id = t.nation_id;
  if (select sum(quota) from quota_0145) <> v_n
     or exists (select 1 from quota_0145 where quota < c_floor or quota > v_cap) then
    raise exception '0145 self-assert FAIL: the quotas do not sum to % inside [%, %]: %', v_n, c_floor, v_cap,
      (select string_agg(code || '=' || quota, ' ' order by code) from quota_0145);
  end if;
  raise notice '0145 quotas (cap %, floor %): %', v_cap, c_floor,
    (select string_agg(format('%s %s→%s', code, before, quota), ' · ' order by quota desc, code) from quota_0145);
end $$;

create temp table moved_0145 (player_id uuid primary key, from_nation uuid, to_nation uuid, from_home uuid, to_home uuid, on_loop boolean) on commit drop;

do $$
declare
  rcv  record;
  c    record;
  v_need int;
begin
  -- receivers, the largest shortfall first; donors are the countries above their quota
  for rcv in select q.*, (q.quota - q.before) as need from quota_0145 q where q.quota > q.before
              order by q.quota - q.before desc, q.code loop
    v_need := rcv.need;
    -- (i) companies of a donor country whose loop calls at a harbour of this one: home there
    for c in
      select h.player_id, pl.nation_id as from_nation, h.home_port_id as from_home,
             (select st.port_id from public.npc_fleets nf
                join public.standing_route_stops st on st.route_id = nf.route_id
               where nf.player_id = h.player_id and public.port_nation(st.port_id) = rcv.nation_id
               order by nf.roster_ord, st.ord limit 1) as to_home
        from public.npc_houses h
        join public.players pl on pl.id = h.player_id and pl.is_npc
       where not exists (select 1 from moved_0145 m where m.player_id = h.player_id)
         and exists (select 1 from public.npc_fleets nf
                       join public.standing_route_stops st on st.route_id = nf.route_id
                      where nf.player_id = h.player_id and public.port_nation(st.port_id) = rcv.nation_id)
       order by h.roster_ord desc
    loop
      exit when v_need <= 0;
      -- only while the donor is still above its quota
      continue when (select q.before - (select count(*) from moved_0145 m where m.from_nation = q.nation_id) <= q.quota
                       from quota_0145 q where q.nation_id = c.from_nation);
      insert into moved_0145 values (c.player_id, c.from_nation, rcv.nation_id, c.from_home, c.to_home, true);
      v_need := v_need - 1;
    end loop;
    -- (ii) where no loop reaches it: companies of the donors most above their quota, homed at the capital
    while v_need > 0 loop
      select h.player_id, pl.nation_id as from_nation, h.home_port_id as from_home into c
        from public.npc_houses h
        join public.players pl on pl.id = h.player_id and pl.is_npc
        join quota_0145 q on q.nation_id = pl.nation_id
       where not exists (select 1 from moved_0145 m where m.player_id = h.player_id)
         and q.before - (select count(*) from moved_0145 m where m.from_nation = q.nation_id) > q.quota
       order by q.before - (select count(*) from moved_0145 m where m.from_nation = q.nation_id) - q.quota desc, h.roster_ord desc
       limit 1;
      if c.player_id is null then
        raise exception '0145 self-assert FAIL: no donor company is left for % (short %)', rcv.code, v_need;
      end if;
      insert into moved_0145 values (c.player_id, c.from_nation, rcv.nation_id, c.from_home,
                                     (select p.id from public.ports p where p.code = rcv.capital_port_code), false);
      v_need := v_need - 1;
    end loop;
  end loop;
end $$;

-- the move itself: country, ink, home; one event each. Money, ships, routes: untouched.
update public.players pl set nation_id = m.to_nation from moved_0145 m where pl.id = m.player_id and pl.is_npc;
update public.npc_houses h
   set home_port_id = m.to_home,
       ink = (select i.ink from ink_0145 i join public.nations n on n.code = i.nation where n.id = m.to_nation)
  from moved_0145 m where h.player_id = m.player_id;
select public.emit_event(m.player_id, 'NATION_CHANGED', jsonb_build_object(
         'from', fn.code, 'from_name', fn.name, 'to', tn.code, 'to_name', tn.name, 'reason', 'rebalance',
         'from_home', (select p.code from public.ports p where p.id = m.from_home),
         'to_home', (select p.code from public.ports p where p.id = m.to_home)))
  from moved_0145 m join public.nations fn on fn.id = m.from_nation join public.nations tn on tn.id = m.to_nation;

do $$
declare
  v_bad text;
begin
  select string_agg(format('%s has %s, quota %s', q.code, x.n, q.quota), '; ') into v_bad
    from quota_0145 q
    cross join lateral (select count(*) as n from public.npc_houses h join public.players pl on pl.id = h.player_id
                         where pl.nation_id = q.nation_id) x
   where x.n <> q.quota;
  if v_bad is not null then
    raise exception '0145 self-assert FAIL: the companies are not at their quotas: %', v_bad;
  end if;
  if (select count(*) from public.npc_houses) <> (select sum(before) from quota_0145) then
    raise exception '0145 self-assert FAIL: the number of companies moved';
  end if;
  if exists (select 1 from moved_0145 m join public.players pl on pl.id = m.player_id where not pl.is_npc) then
    raise exception '0145 self-assert FAIL: a player''s company was moved';
  end if;
  if exists (select 1 from moved_0145 m join public.npc_houses h on h.player_id = m.player_id
              where public.port_nation(h.home_port_id) is distinct from m.to_nation
                 or h.ink <> (select i.ink from ink_0145 i join public.nations n on n.code = i.nation where n.id = m.to_nation)) then
    raise exception '0145 self-assert FAIL: a moved company''s home is not its new country''s, or its ink is not';
  end if;
  if exists (select 1 from moved_0145 m where m.on_loop and not exists (
               select 1 from public.npc_fleets nf join public.standing_route_stops st on st.route_id = nf.route_id
                where nf.player_id = m.player_id and st.port_id = m.to_home)) then
    raise exception '0145 self-assert FAIL: an on-loop home is not a stop of the company''s loop';
  end if;
  perform public.assert_ledger_reconciles(m.player_id) from moved_0145 m;
  raise notice '0145 moved % companies (% homed on their own loop, % at the capital): %',
    (select count(*) from moved_0145), (select count(*) from moved_0145 where on_loop), (select count(*) from moved_0145 where not on_loop),
    (select string_agg(format('%s→%s %s', fc, tc, k), ', ' order by fc, tc)
       from (select fn.code fc, tn.code tc, count(*) k from moved_0145 m join public.nations fn on fn.id = m.from_nation
               join public.nations tn on tn.id = m.to_nation group by 1, 2) x);
end $$;

-- ── 4. WHERE A MERCHANT GIVES (D12) ────────────────────────────────────────────────────────────
create or replace function public.npc_closest_race(p_player uuid)
returns table(port_id uuid, gap numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0145 (D12): the contestable stop of this company's loop where its country is in the CLOSEST race
-- — the smallest distance, in its own influence there, to flipping a city (attack:
-- influence_flip_lead × holder / hers − 1, not yet won), to claiming a free one
-- (influence_claim_min / hers − 1, not yet claimed), or to being flipped (defend:
-- influence_flip_lead × hers / best rival − 1, never below 0). A stop where its country has given
-- nothing (attack, claim) or nobody challenges it (defend) is no race. Shares are
-- public.influence_shares' (the one reader). No race: no row. Ties: the port code.
declare
  v_nation uuid := (select pl.nation_id from public.players pl where pl.id = p_player);
  v_lead   numeric := public.wc_num('influence_flip_lead');
  v_claim  numeric := public.wc_num('influence_claim_min');
begin
  return query
    with stops as (
      select distinct st.port_id from public.npc_fleets nf
        join public.standing_route_stops st on st.route_id = nf.route_id
        join public.port_allegiance a on a.port_id = st.port_id and not a.home
       where nf.player_id = p_player
    ), race as (
      select s.port_id, public.port_nation(s.port_id) as holder,
             coalesce((select x.points from public.influence_shares(s.port_id) x where x.nation_id = v_nation), 0) as hers,
             coalesce((select x.points from public.influence_shares(s.port_id) x where x.nation_id = public.port_nation(s.port_id)), 0) as held,
             coalesce((select max(x.points) from public.influence_shares(s.port_id) x where x.nation_id <> v_nation), 0) as rival
        from stops s
    ), gaps as (
      select r.port_id,
             case when r.holder = v_nation then
                    case when r.rival > 0 then greatest(0, v_lead * r.hers / r.rival - 1) end
                  when r.holder is null then
                    case when r.hers > 0 and v_claim / r.hers - 1 >= 0 then v_claim / r.hers - 1 end
                  else
                    case when r.hers > 0 and v_lead * r.held / r.hers - 1 >= 0 then v_lead * r.held / r.hers - 1 end
             end as gap
        from race r
    )
    select g.port_id, g.gap from gaps g join public.ports p on p.id = g.port_id
     where g.gap is not null
     order by g.gap, p.code
     limit 1;
end $$;
revoke all on function public.npc_closest_race(uuid) from public, anon, authenticated;

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create temp table hunks_0145 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0145 values
('public.npc_invest(timestamp with time zone)', 1,
$h$  v_failed   int := 0;
  v_notes    jsonb := '[]'::jsonb;
begin$h$,
$h$  v_failed   int := 0;
  v_notes    jsonb := '[]'::jsonb;
  -- 0145 (D12): where she gives, lit
  v_race     uuid;
  v_stake    record;
  v_left     numeric;
  v_room     bigint;
  v_donated  int := 0;
  v_gave     boolean;
begin$h$),
('public.npc_invest(timestamp with time zone)', 2,
$h$    begin
      select w.port_id, w.kind, public.city_offered(w.port_id, w.kind) as offered,$h$,
$h$    begin
      -- 0145 (D12, O2): LIT, she gives where her country is in the closest race on her loop
      -- (public.npc_closest_race) — shares there if offered, the rest as a gift under D7's cap. No race
      -- on her loop: 0123's rule below, as it was.
      v_race := null;
      if public.influence_on() then
        select r.port_id into v_race from public.npc_closest_race(hi.player_id) r;
      end if;
      if v_race is not null then
        v_left := hi.ducats - public.wc_num('npc_invest_keep') * hi.capital;
        v_gave := false;
        select w.kind, public.city_offered(w.port_id, w.kind) as offered, public.works_share_price(w.level) as price
          into v_stake
          from public.city_works w
         where w.port_id = v_race and public.city_offered(w.port_id, w.kind) > 0
         order by 2 desc, array_position(array['docks', 'market', 'production', 'inn'], w.kind)
         limit 1;
        if v_stake.kind is not null then
          v_buy := least(v_stake.offered, floor(v_left / v_stake.price))::int;
          if v_buy >= 1 and v_buy * v_stake.price >= public.wc_int('invest_min_ducats') then
            perform public.invest_for(hi.player_id, v_race, v_stake.kind, v_buy);
            v_left := v_left - v_buy * v_stake.price;
            v_invested := v_invested + 1;
            v_gave := true;
          end if;
        end if;
        select public.wc_int('influence_day_cap') - coalesce(sum(i.day_given), 0) into v_room
          from public.port_influence i where i.port_id = v_race and i.player_id = hi.player_id;
        if floor(least(v_left, v_room)) >= public.wc_int('donate_min_ducats') then
          perform public.donate_for(hi.player_id, v_race, floor(least(v_left, v_room))::bigint);
          v_donated := v_donated + 1;
          v_gave := true;
        end if;
        if v_gave then
          update public.npc_houses set invested_at = p_now where player_id = hi.player_id;
        end if;
        continue;
      end if;
      select w.port_id, w.kind, public.city_offered(w.port_id, w.kind) as offered,$h$),
('public.npc_invest(timestamp with time zone)', 3,
$h$  return jsonb_build_object('invested', v_invested, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $function$$h$,
$h$  return jsonb_build_object('invested', v_invested, 'donated', v_donated, 'deferred', v_deferred, 'failed', v_failed, 'notes', v_notes);
end $function$$h$),
('public.npc_tend_houses(timestamp with time zone)', 1,
$h$                            'invested', coalesce((v_inv->>'invested')::int, 0),$h$,
$h$                            'invested', coalesce((v_inv->>'invested')::int, 0),
                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145$h$),
('public.npc_tend_sum(jsonb, jsonb)', 1,
$h$                             'invested', 'busy', 'failed', 'deferred'] loop$h$,
$h$                             'invested', 'donated', 'busy', 'failed', 'deferred'] loop   -- 0145: donated$h$),
('world.npc_fleet_card(uuid)', 1,
$h$                            where s.player_id = p.id group by po.code, po.name) x)),$h$,
$h$                            where s.player_id = p.id group by po.code, po.name) x),
      -- 0145: her influence, by city and the country it counts for, most first —
      -- `Influence 3,000 at Havana for Castile-Spain`.
      'influence', (select coalesce(jsonb_agg(jsonb_build_object('port', x.code, 'name', x.name, 'nation', x.nation,
                                                                 'points', round(x.points))
                                              order by x.points desc, x.code), '[]'::jsonb)
                      from (select po.code, po.name, n.code as nation, i.points from public.port_influence i
                              join public.ports po on po.id = i.port_id join public.nations n on n.id = i.nation_id
                             where i.player_id = p.id and i.points > 0) x)),$h$);

create or replace function pg_temp.recut_0145(p_fn text)
returns text
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0145 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0145 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0145(v_def, h.old);
    if v_n <> 1 then
      raise exception '0145 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  return v_def;
end $$;

create temp table recut_0145 on commit drop as
select fn, pg_temp.recut_0145(fn) as def from defs_before_0145;

do $$
declare
  r record;
begin
  for r in select * from recut_0145 order by fn loop
    execute r.def;
  end loop;
end $$;

-- ── 6. THE PROOF ───────────────────────────────────────────────────────────────────────────────
create temp table proven_0145 (k text primary key, v text) on commit drop;

do $$
declare
  d record;
  h record;
  v_rev text;
begin
  for d in select * from defs_before_0145 loop
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0145 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0145(v_rev, h.new) <> 1 then
        raise exception '0145 self-assert FAIL: % — the new text of hunk % is not in the live body exactly once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0145 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.acl
       or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> d.vol
       or (select p.prosecdef from pg_proc p where p.oid = d.fn::regprocedure) <> d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = d.fn::regprocedure) <> d.cfg
       or (select p.proowner from pg_proc p where p.oid = d.fn::regprocedure) <> d.owner then
      raise exception '0145 self-assert FAIL: % — ACL, volatility, definer, config or owner moved', d.fn;
    end if;
  end loop;
  insert into proven_0145 values ('recut', '4 bodies reverse to their pre-images, attributes unmoved');
end $$;

create temp table pre_events_0145 on commit drop as
select e.id from public.events e where e.kind in ('INVESTED', 'DONATED');
-- what a run of npc_invest WROTE: the stakes and gifts its events record, in order
create or replace function pg_temp.npc_writes_0145(p_since timestamptz)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(jsonb_build_object('who', e.player_id, 'kind', e.kind, 'port', e.payload->>'port',
                                               'work', e.payload->>'kind', 'n', coalesce(e.payload->>'shares', e.payload->>'amount'))
                            order by e.player_id, e.kind, e.payload->>'port'), '[]'::jsonb)
    from public.events e
   where e.kind in ('INVESTED', 'DONATED') and e.created_at >= p_since
     and not exists (select 1 from pre_events_0145 x where x.id = e.id)
$$;

-- one company made the ONLY one npc_invest takes: npc_invest_above raised past every purse, and
-- these companies' purses raised past it
create or replace function pg_temp.only_rich_0145(p_players uuid[])
returns void
language plpgsql
as $$
begin
  update public.world_config set value = to_jsonb(1000) where key = 'npc_invest_above';
  update public.world_config set value = to_jsonb(cardinality(p_players)) where key = 'npc_invest_max_per_hour';
  update public.npc_houses set invested_at = null where player_id = any(p_players);
  perform public.credit(h.player_id, 'PROBE_0145', h.capital * 1001 - pl.ducats + 1, null)
     from public.npc_houses h join public.players pl on pl.id = h.player_id where h.player_id = any(p_players);
end $$;

create or replace function pg_temp.probe_0145()
returns jsonb
language plpgsql
as $$
declare
  v_base   int := (select count(*) from public.players);
  v_rich   uuid[];
  v_old    jsonb;
  v_new    jsonb;
  v_ro     jsonb;
  v_rn     jsonb;
  v_m      uuid;
  v_x      uuid;
  v_a      uuid;
  v_b      uuid;
  v_prt    uuid := (select id from public.nations where code = 'PRT');
  v_esp    uuid := (select id from public.nations where code = 'ESP');
  v_race   record;
  v_lit    jsonb;
  v_fb_old jsonb;
  v_fb_new jsonb;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
  select array_agg(player_id) into v_rich
    from (select h.player_id from public.npc_houses h order by md5(h.player_id::text || '0145') limit 10) x;

  -- (c) DARK: the old and the new npc_invest on the same ten rich companies write the same stakes
  begin
    perform pg_temp.only_rich_0145(v_rich);
    v_ro := pg_temp.npc_invest_old_0145(now());
    v_old := pg_temp.npc_writes_0145(now());
    raise exception 'ROLL_0145';
  exception when others then if sqlerrm <> 'ROLL_0145' then raise; end if;
  end;
  begin
    perform pg_temp.only_rich_0145(v_rich);
    v_rn := public.npc_invest(now());
    v_new := pg_temp.npc_writes_0145(now());
    raise exception 'ROLL_0145';
  exception when others then if sqlerrm <> 'ROLL_0145' then raise; end if;
  end;
  if v_old is distinct from v_new or (v_rn - 'donated') is distinct from v_ro or (v_rn->>'donated')::int <> 0
     or coalesce((v_ro->>'invested')::int, 0) < 1 then
    raise exception '0145 self-assert FAIL: dark, npc_invest is not its pre-image (or invested nothing): old % / %, new % / %', v_ro, v_old, v_rn, v_new;
  end if;

  -- (d) LIT: a company with two contestable stops; her country (PRT) holds one with a wide margin
  -- and trails ESP at the other by 5 per cent — she gives at the second
  select h.player_id into v_m
    from public.npc_houses h
   where (select count(distinct st.port_id) from public.npc_fleets nf
            join public.standing_route_stops st on st.route_id = nf.route_id
            join public.port_allegiance a on a.port_id = st.port_id and not a.home
           where nf.player_id = h.player_id) >= 2
   order by md5(h.player_id::text || '0145m') limit 1;
  select h.player_id into v_x from public.npc_houses h where h.player_id <> v_m order by md5(h.player_id::text || '0145x') limit 1;
  select (array_agg(st.port_id order by p.code))[1], (array_agg(st.port_id order by p.code))[2] into v_a, v_b
    from (select distinct s2.port_id from public.npc_fleets nf
            join public.standing_route_stops s2 on s2.route_id = nf.route_id
            join public.port_allegiance a on a.port_id = s2.port_id and not a.home
           where nf.player_id = v_m) st
    join public.ports p on p.id = st.port_id;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    update public.players set nation_id = v_prt where id = v_m;
    update public.players set nation_id = v_esp where id = v_x;
    delete from public.port_influence where port_id in (
      select st.port_id from public.npc_fleets nf join public.standing_route_stops st on st.route_id = nf.route_id where nf.player_id = v_m);
    update public.port_allegiance set nation_id = v_prt where port_id = v_a;
    update public.port_allegiance set nation_id = v_esp where port_id = v_b;
    insert into public.port_influence (port_id, nation_id, player_id, points) values
      (v_a, v_prt, v_m, 1000), (v_a, v_esp, v_x, 500),
      (v_b, v_esp, v_x, 1050), (v_b, v_prt, v_m, 1000);
    select r.port_id, r.gap into v_race from public.npc_closest_race(v_m) r;
    if v_race.port_id is distinct from v_b or round(v_race.gap, 4) <> round(public.wc_num('influence_flip_lead') * 1050 / 1000 - 1, 4) then
      raise exception '0145 self-assert FAIL: the closest race for a country trailing by 5 per cent is not that city: % (gap %)', v_race.port_id, v_race.gap;
    end if;
    perform pg_temp.only_rich_0145(array[v_m]);
    v_rn := public.npc_invest(now());
    v_lit := pg_temp.npc_writes_0145(now());
    if (select count(*) from jsonb_array_elements(v_lit) e where e->>'port' = (select code from public.ports where id = v_a)) > 0
       or (select count(*) from jsonb_array_elements(v_lit) e
            where e->>'kind' = 'DONATED' and e->>'port' = (select code from public.ports where id = v_b)
              and (e->>'n')::bigint = public.wc_int('influence_day_cap')) <> 1
       or (v_rn->>'donated')::int <> 1 then
      raise exception '0145 self-assert FAIL: lit, she did not give at the city where her country trails, up to the cap: % / %', v_rn, v_lit;
    end if;
    perform public.assert_ledger_reconciles(v_m);
    raise exception 'ROLL_0145';
  exception when others then if sqlerrm <> 'ROLL_0145' then raise; end if;
  end;

  -- (d) LIT with no race on her loop: what 0123's rule picks, written exactly as the old body writes it
  begin
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    delete from public.port_influence where port_id in (
      select st.port_id from public.npc_fleets nf join public.standing_route_stops st on st.route_id = nf.route_id where nf.player_id = v_m);
    perform pg_temp.only_rich_0145(array[v_m]);
    perform pg_temp.npc_invest_old_0145(now());
    v_fb_old := pg_temp.npc_writes_0145(now());
    raise exception 'ROLL_0145';
  exception when others then if sqlerrm <> 'ROLL_0145' then raise; end if;
  end;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    delete from public.port_influence where port_id in (
      select st.port_id from public.npc_fleets nf join public.standing_route_stops st on st.route_id = nf.route_id where nf.player_id = v_m);
    perform pg_temp.only_rich_0145(array[v_m]);
    if exists (select 1 from public.npc_closest_race(v_m)) then
      raise exception '0145 self-assert FAIL: a race was found on a loop where her country has given nothing';
    end if;
    perform public.npc_invest(now());
    v_fb_new := pg_temp.npc_writes_0145(now());
    raise exception 'ROLL_0145';
  exception when others then if sqlerrm <> 'ROLL_0145' then raise; end if;
  end;
  if v_fb_old is distinct from v_fb_new or jsonb_array_length(v_fb_new) < 1 then
    raise exception '0145 self-assert FAIL: with no race she did not follow 0123''s rule: old %, new %', v_fb_old, v_fb_new;
  end if;

  if (select count(*) from public.players) <> v_base then
    raise exception '0145 self-assert FAIL: the probe did not leave the world as it found it';
  end if;
  return jsonb_build_object('dark', format('%s stakes written alike by the old and the new body', jsonb_array_length(v_new)),
                            'lit', v_lit, 'no_race', v_fb_new);
end $$;

do $$
declare
  v_p jsonb;
  w jsonb := (select jsonb_object_agg(key, value) from public.world_config
               where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled', 'npc_invest_above',
                             'npc_invest_max_per_hour', 'influence_enabled'));
begin
  begin
    v_p := pg_temp.probe_0145();
    raise exception 'ROLL_OUTER_0145';
  exception when others then if sqlerrm <> 'ROLL_OUTER_0145' then raise; end if;
  end;
  if w is distinct from (select jsonb_object_agg(key, value) from public.world_config
                          where key in ('city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled', 'npc_invest_above',
                                        'npc_invest_max_per_hour', 'influence_enabled')) then
    raise exception '0145 self-assert FAIL: the probe left a knob moved';
  end if;
  insert into proven_0145 values ('probe', v_p::text);
  insert into proven_0145 values ('rebalance', (select format('%s companies moved; every country at its quota (%s)', count(*),
    (select string_agg(format('%s %s', code, quota), ' ' order by quota desc, code) from quota_0145)) from moved_0145));
  raise notice '0145 self-assert ok: MERCHANTS GIVE FOR THEIR COUNTRY — %',
    (select string_agg(k || ': ' || v, ' | ' order by k) from proven_0145);
end $$;

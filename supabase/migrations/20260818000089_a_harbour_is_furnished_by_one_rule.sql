-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0089 — A HARBOUR IS FURNISHED BY ONE RULE  (the buildings a city keeps, stated once, for the
--        harbours that exist and for every harbour the world grows)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-09-14 (docs/OWNER_REQUESTS.md row 91): *"I see no cities on the left side of
-- america, the number of cities are weird. Check"*. The check found FIVE harbours on the whole
-- Pacific coast of the Americas and the growth that follows (0090) adds fourteen. A new harbour
-- needs its buildings, and there was no one place that says which buildings a harbour keeps.
--
-- ── WHAT SAYS IT TODAY: FOUR TIMES, INLINE, IN FOUR APPLIED FILES ──────────────────────────────
-- Spaghetti, named plainly. "Which buildings does a harbour keep, at what tier" is written as
-- four INSERT statements in four migrations, each the author of one or two kinds:
--   * 0067:125-136  market and inn at every harbour (tier = size_tier, clamped 1..5); shipyard
--                   where has_yard (tier = yard_tier); academy where has_academy (tier = size_tier)
--   * 0068:199-206  workstation where dev_industry >= 7 (tier 3 at >= 13, 2 at >= 9, else 1)
--   * 0070:83-86    warehouse at every harbour (tier = size_tier)
--   * 0072:159-166  building_yard where yard_tier >= 3 (tier 3 at dev_industry >= 15, 2 at >= 12,
--                   else 1)
-- Each ran once, over the 224 harbours that existed on its day, and none of them runs again. So
-- a harbour inserted by a growth migration arrives with NO market, NO inn, NO warehouse: the port
-- screen's face strip is driven by these rows (0067 §3), cmd.do_store refuses a city with no
-- warehouse (0070), and `world.inn` answers for a building that is not there. The growth
-- generator (scripts/build-world-growth.mjs) predates all four files and knows nothing of them.
-- Writing the four rules a fifth time inside the generator would be the copy NO_SPAGHETTI §1
-- forbids — "written a second time → it becomes a function" — so this file is the function.
--
-- ── THE RULE, ONCE ──────────────────────────────────────────────────────────────────────────────
--   public.harbour_buildings(port)  THE RULE: the (kind, tier) rows a harbour keeps, derived from
--                                   the authored columns exactly as the four files derived them.
--                                   A sea place keeps none. Pure, stable, reads only public.ports.
--   public.furnish_harbours()       THE WRITER: inserts, for every harbour, each row the rule
--                                   names that the city does not already keep, and returns how
--                                   many. `on conflict do nothing`, deliberately — 0067's own
--                                   words: *"a tier that a player raises has nowhere to live in a
--                                   boolean"*. A row that exists is the game's; this never lowers,
--                                   raises or deletes one. It only furnishes an empty city.
--
-- ── SUPERSEDE, AND THE NO-OP PROOF ──────────────────────────────────────────────────────────────
-- Nothing is dropped or re-cut: the four inline inserts are history and stay in their files. What
-- this file SUPERSEDES is their AUTHORITY over the rule — from here, the function is where the
-- numbers live, and 0090 calls it rather than retyping them. That the function IS the deployed
-- rule and not a fifth reading of it is asserted, not claimed: over every harbour in the world the
-- rule's rows EQUAL the rows the four files seeded, as a set with tiers, in both directions, and
-- the writer inserts ZERO rows on this world — a fixed point. Then both halves are made to bite:
-- a deleted inn is refurnished at the rule's tier, and a raised tier is left alone.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
--   * It does not seed any building at any existing harbour (proven: 0 rows written).
--   * It does not serve anything: world.snapshot()'s `buildings` (0067 §3) reads the rows as before.
--   * It does not move the thresholds. 13 / 9 / 7 and 15 / 12 are 0068's and 0072's measured
--     numbers, restated here as the ONE place they now live, and proven equal to what they seeded.
--   * It is not a client entry point: revoked from public, anon and authenticated.
--
-- Depends on: 0002 (ports), 0036 (ports.kind), 0067 (building_kinds, port_buildings), 0068, 0070,
-- 0072 (the kinds those files added).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE RULE ────────────────────────────────────────────────────────────────────────────────
create or replace function public.harbour_buildings(p_port uuid)
returns table (kind text, tier int)
language sql
stable
set search_path = public, pg_temp
as $$
  select k.kind, k.tier
    from public.ports p
    cross join lateral (values
      -- 0067:125-136 — every harbour trades and every harbour pours; the two that already existed
      ('market',        greatest(1, least(5, p.size_tier)), true),
      ('inn',           greatest(1, least(5, p.size_tier)), true),
      ('shipyard',      greatest(1, least(5, p.yard_tier)), p.has_yard),
      ('academy',       greatest(1, least(5, p.size_tier)), p.has_academy),
      -- 0068:199-206 — a city works metal and timber because it industrially can
      ('workstation',   case when p.dev_industry >= 13 then 3 when p.dev_industry >= 9 then 2 else 1 end,
                        p.dev_industry >= 7),
      -- 0070:83-86 — every city keeps a shed
      ('warehouse',     greatest(1, least(5, p.size_tier)), true),
      -- 0072:159-166 — a building yard stands where a city genuinely builds
      ('building_yard', case when p.dev_industry >= 15 then 3 when p.dev_industry >= 12 then 2 else 1 end,
                        p.yard_tier >= 3)
    ) as k(kind, tier, keeps)
   where p.id = p_port and p.kind = 'HARBOUR' and k.keeps
$$;

comment on function public.harbour_buildings(uuid) is
  'THE RULE (0089): the (kind, tier) rows a harbour keeps, derived from ports.size_tier, yard_tier, '
  'has_yard, has_academy and dev_industry exactly as 0067/0068/0070/0072 seeded them. A sea place '
  'keeps none. The one place the thresholds live; public.furnish_harbours() writes what it names.';

revoke all on function public.harbour_buildings(uuid) from public, anon, authenticated;

-- ── 2. THE WRITER ──────────────────────────────────────────────────────────────────────────────
create or replace function public.furnish_harbours()
returns int
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  insert into public.port_buildings (port_id, kind, tier)
  select p.id, b.kind, b.tier
    from public.ports p
    cross join lateral public.harbour_buildings(p.id) b
   where p.kind = 'HARBOUR'
  on conflict (port_id, kind) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.furnish_harbours() is
  'THE WRITER (0089): inserts every (harbour, kind, tier) row public.harbour_buildings names that '
  'the city does not already keep, and returns how many. NEVER updates or deletes: a row that '
  'exists is the game''s (0067: a tier a player raises lives here). Called by every growth '
  'migration after it inserts harbours; a fixed point (0 rows) on a furnished world.';

revoke all on function public.furnish_harbours() from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_harbours   int;
  v_rows       int;
  v_missing    int;
  v_extra      int;
  v_list       text;
  v_written    int;
  v_probe      uuid;
  v_probe_code text;
  v_tier       int;
  v_kinds      int;
begin
  -- Non-vacuity first: the world this file finds has harbours and they have buildings.
  select count(*) into v_harbours from public.ports where kind = 'HARBOUR';
  select count(*) into v_rows from public.port_buildings;
  if v_harbours < 200 or v_rows < v_harbours * 3 then
    raise exception '0089 self-assert FAIL: % harbours and % building rows — not the furnished world this file was written against', v_harbours, v_rows;
  end if;

  -- (a) THE RULE IS THE DEPLOYED RULE: for every harbour, the rows the function names EQUAL the
  --     rows the four files seeded — kind AND tier, both directions, 0 disagreements.
  select count(*) into v_missing
    from public.ports p
    cross join lateral public.harbour_buildings(p.id) b
   where p.kind = 'HARBOUR'
     and not exists (select 1 from public.port_buildings pb
                      where pb.port_id = p.id and pb.kind = b.kind and pb.tier = b.tier);
  select count(*) into v_extra
    from public.port_buildings pb
    join public.ports p on p.id = pb.port_id
   where p.kind = 'HARBOUR'
     and not exists (select 1 from public.harbour_buildings(p.id) b
                      where b.kind = pb.kind and b.tier = pb.tier);
  if v_missing <> 0 or v_extra <> 0 then
    select string_agg(x.s, ', ') into v_list from (
      select p.code || '·' || b.kind || '@' || b.tier as s
        from public.ports p cross join lateral public.harbour_buildings(p.id) b
       where p.kind = 'HARBOUR'
         and not exists (select 1 from public.port_buildings pb
                          where pb.port_id = p.id and pb.kind = b.kind and pb.tier = b.tier)
      union all
      select p.code || '·' || pb.kind || '@' || pb.tier || ' (kept, not named)'
        from public.port_buildings pb join public.ports p on p.id = pb.port_id
       where p.kind = 'HARBOUR'
         and not exists (select 1 from public.harbour_buildings(p.id) b
                          where b.kind = pb.kind and b.tier = pb.tier)
      limit 20) x;
    raise exception '0089 self-assert FAIL: the rule is not the deployed rule — % row(s) it names are not kept, % kept row(s) it does not name: %', v_missing, v_extra, v_list;
  end if;
  select count(distinct kind) into v_kinds from public.port_buildings;
  if v_kinds <> 7 then
    raise exception '0089 self-assert FAIL: % distinct building kinds are kept; the rule names 7 and a kind it does not know would pass (a) unseen', v_kinds;
  end if;

  -- (b) A SEA PLACE KEEPS NOTHING.
  if exists (select 1 from public.ports p cross join lateral public.harbour_buildings(p.id) b where p.kind <> 'HARBOUR') then
    raise exception '0089 self-assert FAIL: the rule furnishes a sea place';
  end if;

  -- (c) THE WRITER IS A FIXED POINT on a furnished world: 0 rows written, the table unchanged.
  v_written := public.furnish_harbours();
  if v_written <> 0 or (select count(*) from public.port_buildings) <> v_rows then
    raise exception '0089 self-assert FAIL: furnish_harbours wrote % row(s) on an already-furnished world (% rows before, % after)',
      v_written, v_rows, (select count(*) from public.port_buildings);
  end if;

  -- (d) AND IT BITES. The subject: the smallest-tier harbour with the lowest code — deterministic,
  --     and a size_tier-2 city so its market tier (2) can be raised without hitting the CHECK's 5.
  select p.id, p.code into v_probe, v_probe_code from public.ports p
   where p.kind = 'HARBOUR' and p.size_tier = 2 order by p.code limit 1;
  if v_probe is null then
    raise exception '0089 self-assert FAIL: no size_tier-2 harbour to probe with';
  end if;
  --     (d1) an unfurnished city is furnished at the rule's tier
  delete from public.port_buildings where port_id = v_probe and kind = 'inn';
  v_written := public.furnish_harbours();
  select tier into v_tier from public.port_buildings where port_id = v_probe and kind = 'inn';
  if v_written <> 1 or v_tier is distinct from 2 then
    raise exception '0089 self-assert FAIL (positive control): deleted %''s inn; furnish_harbours wrote % row(s) and the inn reads tier % (expected 1 row at tier 2)',
      v_probe_code, v_written, v_tier;
  end if;
  --     (d2) a tier the game raised is left alone — the writer never updates
  update public.port_buildings set tier = 3 where port_id = v_probe and kind = 'market';
  v_written := public.furnish_harbours();
  select tier into v_tier from public.port_buildings where port_id = v_probe and kind = 'market';
  if v_written <> 0 or v_tier <> 3 then
    raise exception '0089 self-assert FAIL (positive control): raised %''s market to 3; furnish_harbours wrote % row(s) and the market reads tier % (expected 0 rows, tier 3 kept)',
      v_probe_code, v_written, v_tier;
  end if;
  update public.port_buildings set tier = 2 where port_id = v_probe and kind = 'market';
  --     and the world is exactly what it was
  if (select count(*) from public.port_buildings) <> v_rows then
    raise exception '0089 self-assert FAIL: the probe left the table at % rows, not %', (select count(*) from public.port_buildings), v_rows;
  end if;

  -- (e) THE LOCKDOWN. Neither function reaches a client; both halves of the lockdown read zero.
  if has_function_privilege('anon', 'public.harbour_buildings(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.harbour_buildings(uuid)', 'execute')
     or has_function_privilege('anon', 'public.furnish_harbours()', 'execute')
     or has_function_privilege('authenticated', 'public.furnish_harbours()', 'execute') then
    raise exception '0089 self-assert FAIL: a client role can execute the rule or the writer';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0089 self-assert FAIL: the grant lockdown does not read zero (write grants, executable writers, read-wall gaps)';
  end if;

  raise notice '0089 self-assert ok: A HARBOUR IS FURNISHED BY ONE RULE. public.harbour_buildings names, for all % harbours, exactly the % building rows 0067/0068/0070/0072 seeded (kind and tier, both directions, 7 kinds, 0 disagreements) and names none for a sea place; public.furnish_harbours is a fixed point on this world (0 rows written) and BITES both ways — %''s deleted inn came back at tier 2, its market raised to 3 was left at 3; neither function is executable by a client; 0 client write grants, 0 client-executable writers, 0 read-wall gaps.',
    v_harbours, v_rows, v_probe_code;
end $$;

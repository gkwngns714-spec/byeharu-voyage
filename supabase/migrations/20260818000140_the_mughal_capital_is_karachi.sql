-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0140 — THE MUGHAL CAPITAL IS KARACHI  (every nation's capital is a harbour of its own nation)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Mughal India's capital was Surat (SRT, seeded by 0003). 0130 gave Surat to the Gujarat Sultanate
-- (NATION_OVERRIDE `surat: 'GUJ'`) and said plainly that MUG's capital stayed behind — so Mughal
-- India's capital sat in another country. The owner was asked to pick, asked for the best choice,
-- and Karachi was chosen (2026-10-17). Mughal India holds two harbours, both size 2: Karachi
-- (industry 6 / commerce 9 / military 4 = 19) and Chittagong (4 / 9 / 4 = 17). Karachi is the more
-- developed and sits on the Arabian Sea routes. Surat stays Gujarat's: moving it back would strip
-- Gujarat of its only tier-3 yard.
--
-- ── EVERY READER OF A CAPITAL (repo grep + pg_get_functiondef over public / cmd / world / voyage, read-only)
--   * public.nations.capital_port_code — the column (0002), seeded by 0003 and 0130.
--   * world.snapshot — serves each nation's `capital` (0028 / 0032). The ONE live body that reads
--     it. The client prints it (src/features/compendium/NationsFace.tsx, type src/lib/rpc/types.ts).
--   * scripts/lib/world-derive.mjs CAPITALS — the generator; scripts/db/world-guard.mjs holds the
--     database to it on every apply. This file and that map move together (MUG: 'karachi').
--   * scripts/roster/world-facts.mjs, scripts/build-npc-0098.mjs / build-npc-0105.mjs — read the
--     column for reports only: the merchants' home ports are drawn from a nation's own harbours by
--     development, never from its capital. No house, fleet, officer or yard is placed by a capital
--     (public.new_house and cmd.found_house take the harbour as an argument). So nothing founded at
--     Surat moves, and no live player asset is touched.
--   The other twenty-two nations were checked on prod: each capital is already a harbour of its own
--   nation. MUG is the only mismatch.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- One row: public.nations MUG capital_port_code SRT → KAR. Nothing else.
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- Pre-image: MUG's capital is SRT (or already KAR — a re-run changes nothing); every other nation
-- row is snapshotted. After: MUG's capital is KAR; KAR is a harbour and its nation is MUG; EVERY
-- nation with a capital names a harbour of its own nation; every other nation row (code, name,
-- flag, capital) equals its pre-image; world.snapshot serves MUG's capital as KAR. The world guard
-- (apply-chain.mjs) holds the result to world-derive.mjs. Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- One UPDATE of one public.nations row (never written by a tick). No LOCK TABLE, no set role, no
-- begin/commit. Holds on a lived-in world: nothing here reads runtime state.
--
-- ROLLBACK: a forward migration setting MUG's capital_port_code back to 'SRT' (and world-derive.mjs
-- CAPITALS MUG back to 'surat').
-- VERSION: 0140. Applies on prod head 0139.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create temp table nations_pre_0140 on commit drop as
  select code, name, flag_char, capital_port_code from public.nations;

do $pre$
declare
  v_cap text;
begin
  select capital_port_code into v_cap from public.nations where code = 'MUG';
  if not found then
    raise exception '0140 pre-image FAIL: no nation MUG';
  end if;
  if v_cap is distinct from 'SRT' and v_cap is distinct from 'KAR' then
    raise exception '0140 pre-image FAIL: MUG''s capital is %, expected SRT (0003) or KAR', coalesce(v_cap, 'NULL');
  end if;
  if not exists (select 1 from public.ports p join public.nations n on n.id = p.nation_id
                  where p.code = 'KAR' and p.kind = 'HARBOUR' and n.code = 'MUG') then
    raise exception '0140 pre-image FAIL: KAR is not a harbour of Mughal India';
  end if;
end $pre$;

-- ── 1. THE ONE ROW (world-derive.mjs CAPITALS MUG: 'karachi') ─────────────────────────────────
update public.nations set capital_port_code = 'KAR'
 where code = 'MUG' and capital_port_code is distinct from 'KAR';

-- ── 2. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $assert$
declare
  v_t0   timestamptz := clock_timestamp();
  v_bad  int;
  v_list text;
  v_snap text;
begin
  -- (a) MUG's capital is Karachi, and Karachi is Mughal India's harbour
  if (select capital_port_code from public.nations where code = 'MUG') is distinct from 'KAR' then
    raise exception '0140 self-assert FAIL: MUG''s capital is not KAR';
  end if;
  if not exists (select 1 from public.ports p join public.nations n on n.id = p.nation_id
                  where p.code = 'KAR' and p.kind = 'HARBOUR' and n.code = 'MUG') then
    raise exception '0140 self-assert FAIL: KAR''s nation is not MUG';
  end if;

  -- (b) EVERY nation's capital is a harbour of its own nation
  select count(*), string_agg(n.code || '→' || n.capital_port_code, ', ' order by n.code)
    into v_bad, v_list
    from public.nations n
   where n.capital_port_code is not null
     and not exists (select 1 from public.ports p
                      where p.code = n.capital_port_code and p.kind = 'HARBOUR' and p.nation_id = n.id);
  if v_bad > 0 then
    raise exception '0140 self-assert FAIL: % capital(s) not a harbour of their own nation: %', v_bad, v_list;
  end if;

  -- (c) nothing else moved: every nation row but MUG's capital equals its pre-image, both directions
  select count(*) into v_bad from (
    (select code, name, flag_char, case when code = 'MUG' then 'KAR' else capital_port_code end
       from nations_pre_0140
     except
     select code, name, flag_char, capital_port_code from public.nations)
    union all
    (select code, name, flag_char, capital_port_code from public.nations
     except
     select code, name, flag_char, case when code = 'MUG' then 'KAR' else capital_port_code end
       from nations_pre_0140)) d;
  if v_bad > 0 then
    raise exception '0140 self-assert FAIL: % nation row(s) differ from the pre-image beyond MUG''s capital', v_bad;
  end if;

  -- (d) the one live reader serves it: world.snapshot's nations carry MUG → KAR
  select x->>'capital' into v_snap
    from jsonb_array_elements(world.snapshot()->'nations') x
   where x->>'code' = 'MUG';
  if v_snap is distinct from 'KAR' then
    raise exception '0140 self-assert FAIL: world.snapshot serves MUG''s capital as %', coalesce(v_snap, 'NULL');
  end if;

  raise notice '0140 self-assert ok: THE MUGHAL CAPITAL IS KARACHI. MUG''s capital is KAR, a harbour of Mughal India; every one of % nation(s) with a capital names a harbour of its own nation; every other nation row equals its pre-image; world.snapshot serves MUG → KAR. (asserts took % ms)',
    (select count(*) from public.nations where capital_port_code is not null),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $assert$;

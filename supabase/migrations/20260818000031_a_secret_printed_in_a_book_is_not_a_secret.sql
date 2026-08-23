-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0031 — A SECRET PRINTED IN A BOOK IS NOT A SECRET
--        The world secret is born on the database it protects, exists in no file, and the one
--        table that holds it now REFUSES the value every copy of this book carries.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, NAMED ───────────────────────────────────────────────────────────────────────────
--   0001:145 seeds `world_config.world_secret` as a plain-text literal in this repository:
--   'voyage-v0-seed-6f2a91c4'. Its own description says "Never leaves the server". The repository
--   is about to go PUBLIC, at which point that value leaves the server permanently — and it is in
--   git HISTORY, so editing 0001 would not retrieve it. `voyage.rng_raw` (0006:113-125) is
--   md5(voyage:day:stream:secret), published in the same book. Anyone holding both can compute,
--   IN ADVANCE: which days of any voyage are attacked (0007's settle), whether a haggle attempt
--   will succeed before it is spent (0022), and where and when every fair opens (0026). That is a
--   cheat engine against a live world, and no amount of grant lockdown helps — the leak is the
--   seed itself, not access to the row.
--
-- ── WHAT THIS SUPERSEDES, AND WHY A NEW FILE ───────────────────────────────────────────────────
--   It supersedes exactly ONE fact: the VALUE (and description) of the `world_secret` row that
--   0001:145 seeds. Nothing else — not the table, not the reader `wc()`, not `voyage.rng`, whose
--   whole design (the secret arrives as an ARGUMENT so rng_raw can stay IMMUTABLE) is what makes
--   this rotation a one-row UPDATE instead of a function rewrite. 0001 has run in production and
--   is not edited (README §1): its literal remains in the book as the KNOWN-COMPROMISED bootstrap
--   value, which every database rotates away from here, and which the new constraint refuses for
--   ever after. The literal is written out in this file too — deliberately. It is not a secret;
--   it is the WANTED POSTER, and the refusal must name what it refuses.
--
-- ── THE PLAN, BEFORE THE CODE (docs/NO_SPAGHETTI.md §7B) ───────────────────────────────────────
--   * The concept: THE PROVENANCE OF THE WORLD SECRET — where a value that must exist in no file
--     comes from.
--   * Where it lives: here, as one conditional rotation — and, standing after this file is
--     history, as ONE CHECK constraint on `world_config`, because a guard inside a migration's
--     do-block runs once per database and a constraint runs on every write, in every environment,
--     for ever. The constraint is the half that makes "the repo is safe to publish" a property of
--     the DATABASE rather than a hope about future diffs.
--   * The second caller: whoever writes that row next — a future migration, a hand edit in the
--     SQL editor, an agent pasting "the real value" back in to debug something. The constraint is
--     what meets them: the published literal, and any hand-typed value under 64 characters, is
--     refused with a check_violation naming this file's decision.
--   * The wrong shape, and how anyone finds out: rotating on EVERY apply — it would re-dice every
--     unsettled voyage day, every open haggle and every future fair on the live world on every
--     deploy, and it would make "did it rotate" untestable (nothing stable to compare). The
--     self-assert's rejected-write probes are how a regression surfaces: they go red the moment
--     the constraint stops refusing.
--
-- ── THE ROTATION RULE: ONLY IF COMPROMISED — decided, not defaulted ────────────────────────────
--   Rotate if and only if the live value IS the published literal, or is shorter than 64
--   characters (no value this file ever generates is; any hand-typed string is). Consequences:
--   * A FRESH chain (every local apply, every CI run, every browser boot) rotates exactly once,
--     at this file: 0001 seeded the literal, so the compromised branch always fires there — which
--     doubles as the rotation's own positive control, exercised on every apply everywhere.
--   * PRODUCTION rotates once, on deploy, to a value generated on Supabase's own PostgreSQL by
--     pg_strong_random — a value that has never existed in a file, a log, or a terminal.
--   * A database already rotated is LEFT ALONE — re-running this file (or any future re-apply
--     path) must not re-dice a live world's future. Both branches are asserted, so neither is
--     vacuous: the compromised branch proves the value moved, the private branch proves it did
--     not.
--
-- ── THE GENERATOR: CORE gen_random_uuid(), FOUR TIMES — measured, not assumed ──────────────────
--   Four v4 UUIDs, hyphens stripped: 128 hex characters carrying 4 × 122 = 488 bits from
--   PostgreSQL's pg_strong_random. NOT pgcrypto's gen_random_bytes(): PGlite has no pgcrypto —
--   "0001: pgcrypto unavailable" prints on every local apply (measured on this machine,
--   2026-08-23) — so gen_random_bytes would put the local gate and Supabase on different code
--   paths, which is the exact defect 0001 §5b exists to forbid. gen_random_uuid() is core since
--   PostgreSQL 13 and 0001 (h) already asserts it resolves, on every environment this chain runs.
--
-- ── RANDOMNESS AND ASSERTS, KEPT APART ─────────────────────────────────────────────────────────
--   The house rule bans randomness on an assert path (a lottery assert cost four CI rounds).
--   This file NEEDS randomness — for the secret, which is generated once, stored, and never
--   asserted BY CONTENT. What the asserts touch is length (deterministic given the generator),
--   format (likewise), inequality to the known-bad literal (a 128-char value cannot equal a
--   24-char one), rng-composition equalities (deterministic given the stored value), and ONE
--   claim about the random draw itself: at least 12 distinct characters among 128 hex draws.
--   P(11 or fewer distinct) ≤ C(16,11)·(11/16)^128 ≈ 7e-18 — not a lottery in the proof-05 sense
--   (a percent-level band) but a check whose failure genuinely means the RNG is broken, which is
--   precisely the claim. Nothing in this file — no notice, no exception text, no comment — ever
--   prints the value or anything derived from it; every message reports lengths, counts and
--   booleans only. A self-assert that echoed the secret into a CI log would recreate the defect.
--
-- ── WHAT IS DELIBERATELY LEFT ALONE ────────────────────────────────────────────────────────────
--   * The FAIR CALENDAR already drawn. Rows in `active_buffs` drawn under the literal persist,
--     including a season in progress. That is not a residual hole: world.buffs(port) serves every
--     wound window — running AND upcoming, `starts_at` included (0026:383-437) — to any
--     authenticated player, so a drawn season is in-game PUBLIC information; knowing the literal
--     tells an attacker nothing the front door does not. The next season draws under the new
--     secret. Hazard and haggle rolls are computed at settle/attempt time, so those close the
--     instant the rotation commits.
--   * Market drift. It never used the secret — deliberately non-deterministic random()
--     (0010:107-113), so prices do not move on rotation.
--   * `updated_at` on the row moves with the rotation, as the table intends.
--
-- ── WHAT IT SELF-ASSERTS (each provoked red once during authoring; messages in the dev log) ────
--   * The live seed is NOT the published literal, is 128 lowercase-hex characters, and carries at
--     least 12 distinct characters.
--   * The constraint exists, REFUSED the published literal and a hand-typed short value in two
--     real rejected writes, and ACCEPTED a legal rotation-shaped value in a third (discarded), so
--     the refusal is neither absent nor total.
--   * THE CHEAT IS CLOSED, on the three real stream families: voyage.rng() no longer agrees with
--     voyage.rng_raw(..., <the literal>) on 'hazard', 'haggle:…' or 'buff:…' — and still agrees
--     with voyage.rng_raw(..., <the stored secret>), the positive control proving the comparison
--     instrument works.
--   * The new secret is absent from world.snapshot() BY VALUE (0009/0028's own idiom, repointed
--     at the rotated value), and the whole grant family is still at zero.
--
-- Depends ONLY on: 0001 (world_config, wc_text), 0006 (voyage.rng / rng_raw), 0009+0028
--                  (world.snapshot, for the leak re-check), 0018 (client_executable_writers).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  -- The published, known-compromised bootstrap value. Written out because the refusal must name
  -- what it refuses; it has been public since 0001 was first pushed and secret it is not.
  k_published constant text := 'voyage-v0-seed-6f2a91c4';
  k_fix       constant uuid := '00000000-0031-4000-8000-000000000031';
  v_old            text := public.wc_text('world_secret');
  v_rotated        boolean := false;
  v_now            text;
  v_distinct       int;
  v_refusals       int := 0;
  v_accepted       boolean := false;
  v_stream         text;
  v_live           numeric;
  v_grants         int;
  v_exec_writers   int;
  v_wc_priv        int;
  v_snap           text;
begin
  -- ── 1. THE ROTATION — only if compromised ────────────────────────────────────────────────────
  if v_old = k_published or length(v_old) < 64 then
    update public.world_config
       set value       = to_jsonb(replace(gen_random_uuid()::text || gen_random_uuid()::text
                                       || gen_random_uuid()::text || gen_random_uuid()::text,
                                          '-', '')),
           description = 'SECRET. Seeds voyage.rng() with (voyage_id, day_index, stream). '
                         'Generated ON THIS DATABASE by 0031 at apply time; exists in no file, '
                         'no log and no repository, which is what lets the repository be public. '
                         'The table''s own CHECK refuses the retired 0001 literal and any value '
                         'under 64 characters.',
           updated_at  = now()
     where key = 'world_secret';
    v_rotated := true;
    raise notice '0031: world_secret was compromised (the published bootstrap value) — rotated to a value generated on this database and printed nowhere';
  else
    raise notice '0031: world_secret is already private (length %, not the published literal) — left untouched, by the rotate-only-if-compromised rule in this file''s header', length(v_old);
  end if;

  -- ── 2. THE STANDING REFUSAL — the database itself, not a once-run do-block ───────────────────
  if not exists (select 1 from pg_constraint
                  where conname = 'world_config_secret_is_private'
                    and conrelid = 'public.world_config'::regclass) then
    alter table public.world_config
      add constraint world_config_secret_is_private
      check (key <> 'world_secret'
             or (length(value #>> '{}') >= 64
                 and (value #>> '{}') <> 'voyage-v0-seed-6f2a91c4'));
  end if;

  -- ── 3. SELF-ASSERT ───────────────────────────────────────────────────────────────────────────
  v_now := public.wc_text('world_secret');

  -- (a) The book no longer holds the live seed. THE claim this file exists for.
  if v_now = k_published then
    raise exception '0031 self-assert FAIL: the published literal is STILL the live seed — the rotation did not happen and this repository must not be made public';
  end if;
  -- Both branches of the rotation rule are real, never vacuous:
  if v_rotated and v_now = v_old then
    raise exception '0031 self-assert FAIL: the compromised branch fired but the stored value did not move';
  end if;
  if (not v_rotated) and v_now <> v_old then
    raise exception '0031 self-assert FAIL: the value moved on a database that was already private — the rotate-only-if-compromised rule is broken and every re-apply would re-dice a live world';
  end if;

  -- (b) Shape: exactly what the generator emits. Lengths and booleans only — never the value.
  if length(v_now) <> 128 or v_now !~ '^[0-9a-f]{128}$' then
    raise exception '0031 self-assert FAIL: the stored seed has length % and hex-format=% — expected 128 lowercase hex characters from four gen_random_uuid() draws',
      length(v_now), (v_now ~ '^[0-9a-f]{128}$');
  end if;

  -- (c) Entropy: >= 12 distinct characters in 128 hex draws (P of a false red ~ 7e-18; a real
  --     red means pg_strong_random is broken, which is exactly the claim).
  select count(distinct c) into v_distinct from unnest(string_to_array(v_now, null)) c;
  if v_distinct < 12 then
    raise exception '0031 self-assert FAIL: the stored seed carries only % distinct character(s) in 128 — the random source is not producing randomness', v_distinct;
  end if;

  -- (d) THE REFUSAL, proven by REJECTED WRITES, not by reading DDL (0006's idiom).
  begin
    update public.world_config set value = to_jsonb(k_published) where key = 'world_secret';
    raise exception '__0031_NOT_REFUSED__';
  exception
    when check_violation then v_refusals := v_refusals + 1;
    when others then
      if sqlerrm = '__0031_NOT_REFUSED__' then
        raise exception '0031 self-assert FAIL: the constraint did NOT refuse the published literal — pasting the compromised value back in would succeed, and the book is not safe to publish';
      end if;
      raise;
  end;
  begin
    update public.world_config set value = to_jsonb('a-hand-typed-debug-seed'::text) where key = 'world_secret';
    raise exception '__0031_NOT_REFUSED__';
  exception
    when check_violation then v_refusals := v_refusals + 1;
    when others then
      if sqlerrm = '__0031_NOT_REFUSED__' then
        raise exception '0031 self-assert FAIL: the constraint did NOT refuse a hand-typed short value — only the one literal is blocked, and the next paste would be a different string';
      end if;
      raise;
  end;
  -- ...and the refusal is not TOTAL: a legal rotation-shaped value goes through (then is
  -- discarded, so this probe cannot itself rotate the world).
  begin
    update public.world_config
       set value = to_jsonb(replace(gen_random_uuid()::text || gen_random_uuid()::text
                                 || gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
     where key = 'world_secret';
    v_accepted := true;
    raise exception '__0031_DISCARD__';
  exception
    when check_violation then
      raise exception '0031 self-assert FAIL: the constraint refused a LEGAL rotation-shaped value — it would block every future rotation, including this file''s own';
    when others then
      if sqlerrm <> '__0031_DISCARD__' then raise; end if;
  end;
  if not v_accepted or public.wc_text('world_secret') <> v_now then
    raise exception '0031 self-assert FAIL: the legal-value probe did not run clean (accepted=%, value unchanged=%)',
      v_accepted, (public.wc_text('world_secret') = v_now);
  end if;

  -- (e) THE CHEAT IS CLOSED — on the three stream families the game actually rolls:
  --     'hazard' (0006/0007 settle), 'haggle:<port>:<good>:<attempt>' (0022), and
  --     'buff:<kind>' (0026's fair draw). For each: the live path must still agree with
  --     rng_raw(..., stored secret) — the positive control proving this comparison can detect
  --     agreement — and must NOT agree with rng_raw(..., the published literal).
  foreach v_stream in array array['hazard',
                                  'haggle:' || k_fix || ':' || k_fix || ':1',
                                  'buff:FAIR'] loop
    v_live := voyage.rng(k_fix, 1, v_stream);
    if v_live <> voyage.rng_raw(k_fix, 1, v_stream, v_now) then
      raise exception '0031 self-assert FAIL: voyage.rng no longer composes the stored secret on stream % — the comparison instrument itself is broken, so the closure check below would prove nothing', v_stream;
    end if;
    if v_live = voyage.rng_raw(k_fix, 1, v_stream, k_published) then
      raise exception '0031 self-assert FAIL: the published literal STILL predicts a live roll on stream % — the cheat is open', v_stream;
    end if;
  end loop;

  -- (f) The rotated secret does not cross the wire: absent from world.snapshot() BY VALUE —
  --     0009:263/0028:443's own instrument, repointed at the value that matters now. A null or
  --     token payload would make position() vacuous, and position() itself is proven able to find
  --     a string that IS in the payload before its zero is believed about one that must not be.
  v_snap := world.snapshot()::text;
  if v_snap is null or length(v_snap) < 1000 then
    raise exception '0031 self-assert FAIL: world.snapshot() served % character(s) — too small to be the real payload, so the leak check below would be vacuous', coalesce(length(v_snap), 0);
  end if;
  if position('time_compression' in v_snap) = 0 then
    raise exception '0031 self-assert FAIL: position() cannot find time_compression in the snapshot payload, a key 0009 has always served — the leak instrument is broken, so its zero would prove nothing';
  end if;
  if position(v_now in v_snap) > 0 then
    raise exception '0031 self-assert FAIL: the rotated secret appears in the world.snapshot() payload';
  end if;

  -- (g) POSTURE, as every migration since 0001/0018 re-asserts it.
  select count(*) into v_grants from public.client_write_grants();
  select count(*) into v_exec_writers from public.client_executable_writers();
  select count(*) into v_wc_priv
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where n.nspname = 'public' and c.relname = 'world_config'
     and (case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)
         in ('anon', 'authenticated', 'PUBLIC');
  if v_grants <> 0 or v_exec_writers <> 0 or v_wc_priv <> 0 then
    raise exception '0031 self-assert FAIL: posture moved — % client write grant(s), % client-executable writer(s), % client privilege(s) on world_config (all must be 0)',
      v_grants, v_exec_writers, v_wc_priv;
  end if;

  raise notice '0031 self-assert ok: A SECRET PRINTED IN A BOOK IS NOT A SECRET. The live seed is 128 lowercase-hex characters with % distinct symbols, generated on this database (rotated this apply: %), and is NOT the published 0001 literal; the table itself refused that literal and a hand-typed value in % real rejected write(s) and accepted a legal rotation (discarded); on all 3 stream families the literal no longer predicts a live roll while the stored secret still does; the secret is absent from world.snapshot() by value; % client write grants, % client-executable writers, % client privileges on world_config',
    v_distinct, v_rotated, v_refusals, v_grants, v_exec_writers, v_wc_priv;
end $$;

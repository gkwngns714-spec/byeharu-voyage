-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0380 — THE SNAPSHOT NAMES THE PIRATE POWER: world.snapshot's nations carry `pirate`. No table, no knob, no switch, no row, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY (owner row 284, "yes they can"; row 324, "do all, make everything work"; docs/dev-log/2026-11-13-a-pirate-company.md). A company may sail
-- for the Brethren once the owner's knob pirates_joinable is true (0338). Walked lit, the country picker then offers eleven flags and says
-- nothing about the eleventh: that it is at war with every country, so every crown port taxes her profit and charges her dock fee at the war
-- rate, and that her four home ports keep no yard. A player who picks the skull learns it at her first sale. The client cannot tell her before
-- she picks, because nothing it is served says which power is the pirates: `great` is the eleven, `joinable` is the list on the picker.
-- WHAT. world.snapshot RE-CUT (1 hunk on its live body): each row of `nations` gains `pirate`, public.pirate_power (0338's one reader of
--   public.great_powers.pirate). true for the Brethren and false for the other 23. Every key it served is served as it was.
-- NOT TOUCHED: every other function (asserted byte for byte), every table, knob, switch and job; the reader's volatility (STABLE), definer,
--   search_path, owner and ACL. pirates_joinable is NOT set here: the file that lights it is its own (0381).
-- ALTERS NO RULE OF PLAY: a read gains one key. The client reads it as optional, so either side may land first.
-- THE COST. One primary-key read of public.great_powers a nation (24), in a read the client caches with the static world.
-- ROLLBACK (forward, a NEW migration, owner only): reverse the hunk (the OLD text is here verbatim); the draft is
--   scripts/ops/harness/pirate-company/rollback-0380.sql.
-- SELF-ASSERT: the catalog (the hunk once and reversing, attributes unmoved, every other function, knob, relation and job unmoved), then the
--   read itself against a pg_temp copy of the body before this file: the new answer less the new key IS the old answer, on every nation.
--   Reads only; the copy is rolled back. Proof: scripts/db/proofs/69_a_pirate_company.sql.
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s. Its time is printed in a notice.
-- news: none (a read gains a key; what a player sees changes when 0381 lights the knob, and that file posts the news)
-- VERSION: 0380 - prod head 0363 (2026-11-13); 0364 to 0379 are held by other branches and none is known to touch world.snapshot's nations.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_def        text;
  v_pre        text;
  v_meta       text;
  v_n          int;
  v_fn_before  text;
  v_cfg_before text;
  v_rel_before text;
  v_job_before text;
  v_lived      boolean := false;
  v_old        jsonb;
  v_new        jsonb;
  c_fn         constant text := 'world.snapshot()';
  c_old        constant text :=
$h$        'joinable', public.nation_joinable(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
$h$;
  c_new        constant text :=
$h$        'joinable', public.nation_joinable(n.id),                                  -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
        'pirate', public.pirate_power(n.id)) order by n.code), '[]'::jsonb)        -- 0380: THE PIRATE POWER, named once, so the picker can say what the skull costs
$h$;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('public.pirate_power(uuid)') is null or to_regprocedure('public.nation_joinable(uuid)') is null then
    raise exception '0380 refuses: 0338 (the Brethren: public.pirate_power, public.nation_joinable) or the snapshot is not in this world';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = c_fn::regprocedure) like '%0380%' then
    raise exception '0380 refuses: it has been applied once';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.pirate_power(uuid)'::regprocedure) not in ('s', 'i') then
    raise exception '0380 refuses: public.pirate_power is volatile, and the snapshot is a STABLE read';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text || ':' || p.proparallel::text into v_meta
    from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;

  -- ── 2. THE HUNK: once, and reversing ──
  v_n := (length(v_pre) - length(replace(v_pre, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0380 self-assert FAIL: the hunk occurs % time(s), not once: the deployed body is not what this file was written against', v_n;
  end if;
  execute replace(v_pre, c_old, c_new);
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception '0380 self-assert FAIL: the new hunk is not in the live body once';
  end if;
  if replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0380 self-assert FAIL: the snapshot does not reverse to its pre-image';
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text || ':' || p.proparallel::text
        from pg_proc p where p.oid = c_fn::regprocedure) <> v_meta then
    raise exception '0380 self-assert FAIL: the snapshot changed its ACL, volatility, definer, config, owner or parallel mark';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before then
    raise exception '0380 self-assert FAIL: a function other than world.snapshot moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0380 self-assert FAIL: a world_config row moved: this file sets no knob (pirates_joinable is 0381''s)';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0380 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_def;
    if v_def is distinct from v_job_before then
      raise exception '0380 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;

  -- ── 4. THE SELF-ASSERT: old against new. A pg_temp copy of the body BEFORE this file answers beside the live one; the copy is rolled back. Reads only. ──
  begin
    execute replace(v_pre, 'FUNCTION world.snapshot(', 'FUNCTION pg_temp.snapshot_old_0380(');
    v_old := pg_temp.snapshot_old_0380();
    v_new := world.snapshot();
    -- every key but `nations` is the old answer's; `nations` less the new key is the old list, in the old order
    if (v_new - 'nations') is distinct from (v_old - 'nations') then
      raise exception '0380 self-assert FAIL: a key of the snapshot other than nations moved';
    end if;
    if coalesce((select jsonb_agg(e.value - 'pirate' order by e.ord) from jsonb_array_elements(v_new -> 'nations') with ordinality e(value, ord)), '[]'::jsonb)
         is distinct from (v_old -> 'nations') then
      raise exception '0380 self-assert FAIL: the nations less the new key are not the old nations';
    end if;
    -- the new key is a boolean on every row, and it is public.great_powers' own word: one pirate power, a great power
    if exists (select 1 from jsonb_array_elements(v_new -> 'nations') e where jsonb_typeof(e.value -> 'pirate') is distinct from 'boolean')
       or exists (select 1 from jsonb_array_elements(v_new -> 'nations') e join public.nations n on n.code = e.value ->> 'code'
                   where (e.value ->> 'pirate')::boolean is distinct from exists (select 1 from public.great_powers g where g.nation_id = n.id and g.pirate))
       or (select count(*) from jsonb_array_elements(v_new -> 'nations') e where (e.value ->> 'pirate')::boolean) <> (select count(*) from public.great_powers g where g.pirate)
       or exists (select 1 from jsonb_array_elements(v_new -> 'nations') e where (e.value ->> 'pirate')::boolean and not (e.value ->> 'great')::boolean)
       or jsonb_array_length(v_new -> 'nations') <> (select count(*) from public.nations) then
      raise exception '0380 self-assert FAIL: `pirate` is not public.great_powers.pirate on every nation: %', (select jsonb_agg(e.value) from jsonb_array_elements(v_new -> 'nations') e where (e.value ->> 'pirate')::boolean);
    end if;
    raise exception using errcode = 'ZX380', message = 'PROBE_ROLLBACK_0380';
  exception when sqlstate 'ZX380' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0380 self-assert FAIL: the probe did not run to its end';
  end if;
  if to_regprocedure('pg_temp.snapshot_old_0380()') is not null then
    raise exception '0380 self-assert FAIL: the copy of the pre-image outlived the probe';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = c_fn::regprocedure) not like '%0380: THE PIRATE POWER%' then
    raise exception '0380 self-assert FAIL: the re-cut body did not outlive the probe''s rollback';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0380 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0380 self-assert ok: world.snapshot serves `pirate` on % nations (% true), every other key as it was; % ms',
    (select count(*) from public.nations), (select count(*) from public.great_powers g where g.pirate), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;

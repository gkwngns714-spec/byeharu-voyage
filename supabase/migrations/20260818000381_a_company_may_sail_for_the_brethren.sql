-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0381 — A COMPANY MAY SAIL FOR THE BRETHREN: lights pirates_joinable (0338's knob). One world_config row, one news row. No function, no table, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY (owner row 284, 2026-11-05: a player may join the pirates, "yes they can"; row 324, 2026-11-13: "do all, make everything work. open them if
-- everything is built and is workable"). 0338 built the door and shipped it shut; the walk of a company under the skull is in
-- docs/dev-log/2026-11-13-a-pirate-company.md and the proof is scripts/db/proofs/69_a_pirate_company.sql.
-- WHAT. public.world_config: pirates_joinable false -> true. Its one reader is public.nation_joinable (0338): cmd.found_house and
--   cmd.change_country let the Brethren in, and world.snapshot serves the Brethren as `joinable`, so the country picker shows eleven.
-- WHAT A PLAYER SEES. The picker (Start, and Profile > Country) offers The Brethren with the skull flag, and says what it costs before she picks
--   (0380's `pirate` key). A company founded under it starts at Port Royal with the same ship and money as any other, paid by Port Royal.
-- WHAT IT DOES NOT DO. No rule of a company already founded moves. No pirate player attacks a player and no player attacks hers (cmd.attack
--   refuses a company as a target, whoever asks: E_HUMAN_TARGET). Attacks stay behind attack_enabled.
-- NOT UNDONE BY SWITCHING IT OFF: a company that joined stays a company of the Brethren until she changes country herself (once every
--   nation_change_cooldown_days). The influence she gave under the skull stays the Brethren's.
-- ROLLBACK (owner only): update public.world_config set value = 'false'::jsonb where key = 'pirates_joinable'. The picker shows ten again at the
--   next load; nobody new may join; those who joined stay. The draft is scripts/ops/harness/pirate-company/rollback-0381.sql.
-- GUARDS (it refuses, applying nothing): 0338 and 0380 are not both in this world; the knob is not false; the Brethren are not the one pirate
--   power with Port Royal their capital and home; a founding under the skull does not work here and now (the probe below).
-- SELF-ASSERT: on a rolled-back probe, with the knob lit: a probe company is founded under the skull through cmd.found_house, lies at Port Royal,
--   and every purse plus every company holds the gold it held (the founding is paid by Port Royal, nothing is made). Then, kept: the one row is
--   true, public.nation_joinable says so, the snapshot offers every great power, and no other knob, function, relation or job moved.
--   It counts only its own probe rows; it deletes nothing.
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 30 s.
-- NEWS: this file posts its own UPDATE row, public.news_update('0381', 'Pirates: join them', '해적단: 가입 열림') (0347's law).
-- VERSION: 0381 - after 0380. Prod head 0363 (2026-11-13).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  c_uid        constant uuid := '00000000-0381-4000-8000-000000000001';
  c_name       constant text := 'Probe 0381 Brethren';
  v_pir        uuid;
  v_por        uuid;
  v_fn_before  text;
  v_cfg_before text;
  v_rel_before text;
  v_job_before text;
  v_job_after  text;
  v_r          jsonb;
  v_p          uuid;
  v_w0         numeric;
  v_w1         numeric;
  v_lived      boolean := false;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARDS ──
  if to_regprocedure('public.nation_joinable(uuid)') is null or to_regprocedure('public.pirate_power(uuid)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0381 refuses: 0338 (the Brethren) or 0347 (the news) is not in this world';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = 'world.snapshot()'::regprocedure) not like '%0380: THE PIRATE POWER%' then
    raise exception '0381 refuses: 0380 is not in this world, so the picker could not say what the skull costs';
  end if;
  if (select c.value from public.world_config c where c.key = 'pirates_joinable') is distinct from 'false'::jsonb then
    raise exception '0381 refuses: pirates_joinable is not false (it is %): it has been lit, or the row is gone', (select c.value from public.world_config c where c.key = 'pirates_joinable');
  end if;
  select g.nation_id into v_pir from public.great_powers g where g.pirate;
  select p.id into v_por from public.ports p join public.nations n on n.capital_port_code = p.code where n.id = v_pir and p.kind = 'HARBOUR';
  if v_pir is null or (select count(*) from public.great_powers g where g.pirate) <> 1 or v_por is null
     or public.port_nation(v_por) is distinct from v_pir then
    raise exception '0381 refuses: the Brethren are not the one pirate power holding their capital as 0338 left them';
  end if;
  if public.nation_joinable(v_pir) then
    raise exception '0381 refuses: public.nation_joinable already lets the Brethren in';
  end if;

  -- ── 1. THE PRE-IMAGE of everything this file must not move ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c where c.key <> 'pirates_joinable';
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;

  -- ── 2. THE PROBE, rolled back: lit, a company is founded under the skull through the real door, at Port Royal, and no gold is made ──
  begin
    update public.world_config set value = 'true'::jsonb where key = 'pirates_joinable';
    v_w0 := (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric + (select coalesce(sum(pl.ducats), 0) from public.players pl)::numeric;
    perform cmd.assume_identity(c_uid);
    v_r := cmd.found_house(c_name, (select n.code from public.nations n where n.id = v_pir));
    if (v_r ->> 'ok') is distinct from 'true' then
      raise exception '0381 refuses: lit, a founding under the skull is answered % here and now', v_r;
    end if;
    v_p := (v_r ->> 'player_id')::uuid;
    if (select pl.nation_id from public.players pl where pl.id = v_p) is distinct from v_pir
       or (select count(*) from public.fleets f where f.player_id = v_p and f.port_id = v_por and f.status = 'DOCKED') <> 1
       or (select count(*) from public.fleets f where f.player_id = v_p) <> 1 then
      raise exception '0381 self-assert FAIL: the probe company is not a company of the Brethren with one fleet docked at their capital';
    end if;
    v_w1 := (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric + (select coalesce(sum(pl.ducats), 0) from public.players pl)::numeric;
    if public.economy_closed() and public.city_treasury_on() and v_w1 <> v_w0 then
      raise exception '0381 self-assert FAIL: closed, a founding under the skull made or lost gold: % -> %', v_w0, v_w1;
    end if;
    -- no player is a target, whoever asks (the no-PvP law): the rule is read where it is written, the one attack door
    if (select p.prosrc from pg_proc p where p.oid = 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure) not like '%E_HUMAN_TARGET%' then
      raise exception '0381 self-assert FAIL: the attack door no longer refuses a company as a target (E_HUMAN_TARGET)';
    end if;
    raise exception using errcode = 'ZX381', message = 'PROBE_ROLLBACK_0381';
  exception when sqlstate 'ZX381' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0381 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.auth_uid = c_uid or pl.company_name = c_name)
     or (select c.value from public.world_config c where c.key = 'pirates_joinable') <> 'false'::jsonb then
    raise exception '0381 self-assert FAIL: the probe outlived its rollback';
  end if;

  -- ── 3. THE LIGHT ──
  update public.world_config set value = 'true'::jsonb, updated_at = now() where key = 'pirates_joinable';

  -- ── 4. THE SELF-ASSERT, kept ──
  if (select c.value from public.world_config c where c.key = 'pirates_joinable') <> 'true'::jsonb or not public.nation_joinable(v_pir) then
    raise exception '0381 self-assert FAIL: the knob is not true, or public.nation_joinable does not read it';
  end if;
  if (select count(*) from jsonb_array_elements(world.snapshot() -> 'nations') e where (e.value ->> 'joinable')::boolean) <> (select count(*) from public.great_powers)
     or not (select (e.value ->> 'joinable')::boolean and (e.value ->> 'pirate')::boolean from jsonb_array_elements(world.snapshot() -> 'nations') e
              where e.value ->> 'code' = (select n.code from public.nations n where n.id = v_pir)) then
    raise exception '0381 self-assert FAIL: the snapshot does not offer every great power, the Brethren among them and named the pirates';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0381 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'pirates_joinable') <> v_cfg_before then
    raise exception '0381 self-assert FAIL: a world_config row other than pirates_joinable moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0381 self-assert FAIL: a table, view, sequence or index appeared or went';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_after;
    if v_job_after is distinct from v_job_before then
      raise exception '0381 self-assert FAIL: a cron job moved';
    end if;
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key
  perform public.news_update('0381', 'Pirates: join them', '해적단: 가입 열림');
  if (select count(*) from public.world_news w where w.key = 'update:0381') <> 1 then
    raise exception '0381 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0381 self-assert FAIL: the file ran % s, over its 30 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0381 self-assert ok: pirates_joinable is true; a probe company was founded under the skull at the pirate capital and rolled back; % ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;

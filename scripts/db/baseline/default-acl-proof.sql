-- 0018's rule, proven on a database that was LOADED FROM THE BASELINE (chain baseline S1).
--
-- 0018: "a function created from 0019 on is born executable by NOBODY but the owner". It lives in
-- one schema-less pg_default_acl row that a --schema-filtered pg_dump never writes
-- (docs/CHAIN_BASELINE.md §4), so the baseline rebuilds it and this proof checks it BY BEHAVIOUR:
-- a function created now, in a game schema and outside one, must not be executable by PUBLIC,
-- anon or authenticated. Then the positive control: the same check, after a schema-less GRANT to
-- PUBLIC made on purpose, must see the function as executable — so a pass cannot mean "the check
-- is blind". Run inside a transaction the caller rolls back (psql: -c begin -f this -c rollback).
do $$
declare
  v_fn   text;
  v_bad  text;
  v_cnt  int := 0;
begin
  execute 'create function world._baseline_acl_probe() returns int language sql as ''select 1''';
  execute 'create function public._baseline_acl_probe() returns int language sql as ''select 1''';
  execute 'create schema _baseline_acl_elsewhere';
  execute 'create function _baseline_acl_elsewhere._baseline_acl_probe() returns int language sql as ''select 1''';
  foreach v_fn in array array['world._baseline_acl_probe()', 'public._baseline_acl_probe()',
                              '_baseline_acl_elsewhere._baseline_acl_probe()'] loop
    if has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                   where p.oid = v_fn::regprocedure and a.grantee = 0) then
      v_bad := coalesce(v_bad || ', ', '') || v_fn;
    end if;
    v_cnt := v_cnt + 1;
  end loop;
  if v_bad is not null then
    raise exception 'FAIL: BASELINE_DEFAULT_ACL_HOLDS — born executable by PUBLIC or a client: %', v_bad;
  end if;
  raise notice 'PASS: BASELINE_DEFAULT_ACL_HOLDS (% probe functions, none executable by PUBLIC/anon/authenticated)', v_cnt;

  -- positive control: undo the rule on purpose; a new function must now be PUBLIC-executable
  execute 'alter default privileges grant execute on functions to public';
  execute 'create function world._baseline_acl_control() returns int language sql as ''select 1''';
  if not has_function_privilege('anon', 'world._baseline_acl_control()', 'execute')
     or not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                     where p.oid = 'world._baseline_acl_control()'::regprocedure and a.grantee = 0) then
    raise exception 'FAIL: BASELINE_DEFAULT_ACL_CONTROL — with the rule undone on purpose the check still saw no PUBLIC execute; it is blind';
  end if;
  raise notice 'PASS: BASELINE_DEFAULT_ACL_CONTROL (with the rule undone, the same check sees PUBLIC execute)';
end $$;

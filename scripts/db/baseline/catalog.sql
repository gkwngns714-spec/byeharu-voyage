-- The catalog of the four game schemas, one line per object, in one SELECT (chain baseline S1).
--
-- ONE statement, pg_catalog reads and STABLE functions only (pg_get_*def, format_type, aclexplode
-- are 's'), no table rows, no volatile call: it is the query that runs on PROD read-only
-- (`supabase db query --linked -f`), and the same file runs on every CI database the baseline proof
-- builds (the chain, the baseline on Supabase, the baseline on PGlite), so "equal lines" means
-- "equal catalog". The rendered definitions (pg_get_functiondef and friends) qualify names by the
-- session's search_path, so every caller runs it with prod's: `"$user", public, extensions`
-- (read on prod 2026-10-27; the CI callers set `public, extensions`, the same visible set).
--
-- What a line holds, by its first letter:
--   N schema       its ACL and owner
--   R relation     kind, ACL, RLS on/forced, owner, persistence, and the md5 of its definition
--                  (view / index) or its sequence parameters (never a sequence's position: prod's
--                  moved)
--   C column       type, not-null, identity, generated, md5 of its default expression
--   K constraint   type, md5 of pg_get_constraintdef
--   G trigger      enabled state (tgenabled), md5 of pg_get_triggerdef
--   F routine      md5 of pg_get_functiondef, ACL, owner, volatility, security definer
--                  (a timestamptz literal in a body is read as '<applied>': 0076 writes THE INSTANT IT
--                  APPLIED into voyage.assert_paths_water's body — its roadstead cutoff — so every
--                  apply, prod's and each CI run's, carries a different one. contentLines' exact
--                  digest still compares that body byte for byte between D-chain and D-base.)
--   Y type         kind, ACL, owner, enum labels
--   P policy       command, permissive, roles, md5 of USING / WITH CHECK
--   D default ACL  the migration role's own entries, per schema and the schema-less one (0018)
-- Extension members are excluded everywhere (their owner and shape are the platform's).
with s(nspname) as (values ('public'), ('world'), ('cmd'), ('voyage')),
ns as (
  select n.oid, n.nspname from pg_namespace n join s using (nspname)
),
ext(classid, objid) as (
  select classid, objid from pg_depend where deptype = 'e'
),
lines(l) as (
  select format('N %s %s %s', n.nspname, coalesce(n.nspacl::text, '-'), pg_get_userbyid(n.nspowner))
    from pg_namespace n join s using (nspname)
  union all
  select format('R %s.%s %s %s %s %s %s %s %s', ns.nspname, c.relname, c.relkind,
                coalesce(c.relacl::text, '-'), c.relrowsecurity, c.relforcerowsecurity,
                pg_get_userbyid(c.relowner), c.relpersistence,
                case c.relkind
                  when 'v' then md5(pg_get_viewdef(c.oid))
                  when 'm' then md5(pg_get_viewdef(c.oid))
                  when 'i' then md5(pg_get_indexdef(c.oid))
                  when 'I' then md5(pg_get_indexdef(c.oid))
                  when 'S' then (select format('%s/%s/%s/%s/%s/%s/%s', format_type(q.seqtypid, null),
                                                q.seqstart, q.seqincrement, q.seqmax, q.seqmin, q.seqcache, q.seqcycle)
                                   from pg_sequence q where q.seqrelid = c.oid)
                  else '-'
                end)
    from pg_class c join ns on ns.oid = c.relnamespace
   where not exists (select 1 from ext where ext.classid = 'pg_class'::regclass and ext.objid = c.oid)
     and c.relkind <> 't'
  union all
  select format('C %s.%s.%s %s %s %s %s %s', ns.nspname, c.relname, a.attname,
                format_type(a.atttypid, a.atttypmod), a.attnotnull, coalesce(nullif(a.attidentity, ''), '-'),
                coalesce(nullif(a.attgenerated, ''), '-'),
                coalesce(md5(pg_get_expr(d.adbin, d.adrelid)), '-'))
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join ns on ns.oid = c.relnamespace
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attnum > 0 and not a.attisdropped and c.relkind in ('r', 'p', 'v', 'm', 'f', 'c')
     and not exists (select 1 from ext where ext.classid = 'pg_class'::regclass and ext.objid = c.oid)
  union all
  select format('K %s.%s %s %s %s', ns.nspname, coalesce(c.relname, t.typname, '-'), k.conname, k.contype,
                md5(pg_get_constraintdef(k.oid)))
    from pg_constraint k
    join ns on ns.oid = k.connamespace
    left join pg_class c on c.oid = k.conrelid
    left join pg_type t on t.oid = k.contypid
  union all
  select format('G %s.%s %s %s %s', ns.nspname, c.relname, g.tgname, g.tgenabled, md5(pg_get_triggerdef(g.oid)))
    from pg_trigger g
    join pg_class c on c.oid = g.tgrelid
    join ns on ns.oid = c.relnamespace
   where not g.tgisinternal
  union all
  select format('F %s.%s(%s) %s %s %s %s %s %s', ns.nspname, p.proname,
                coalesce((select string_agg(format('%s.%s', tn.nspname, t.typname), ',' order by u.ord)
                            from unnest(p.proargtypes) with ordinality u(toid, ord)
                            join pg_type t on t.oid = u.toid
                            join pg_namespace tn on tn.oid = t.typnamespace), ''),
                p.prokind,
                md5(regexp_replace(
                      case when p.prokind in ('f', 'p', 'w') then pg_get_functiondef(p.oid) else p.prosrc end,
                      '''[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+\+00''::timestamptz', '''<applied>''::timestamptz', 'g')),
                coalesce(p.proacl::text, '-'), pg_get_userbyid(p.proowner), p.provolatile, p.prosecdef)
    from pg_proc p join ns on ns.oid = p.pronamespace
   where not exists (select 1 from ext where ext.classid = 'pg_proc'::regclass and ext.objid = p.oid)
  union all
  select format('Y %s.%s %s %s %s %s', ns.nspname, t.typname, t.typtype, coalesce(t.typacl::text, '-'),
                pg_get_userbyid(t.typowner),
                coalesce((select string_agg(e.enumlabel, ',' order by e.enumsortorder)
                            from pg_enum e where e.enumtypid = t.oid), '-'))
    from pg_type t join ns on ns.oid = t.typnamespace
   where t.typtype in ('e', 'd', 'c', 'r', 'm')
     and not (t.typtype = 'c' and exists (select 1 from pg_class c where c.oid = t.typrelid and c.relkind <> 'c'))
     and not exists (select 1 from ext where ext.classid = 'pg_type'::regclass and ext.objid = t.oid)
  union all
  select format('P %s.%s %s %s %s %s %s %s', ns.nspname, c.relname, pol.polname, pol.polcmd, pol.polpermissive,
                coalesce((select string_agg(case when r = 0 then 'PUBLIC' else pg_get_userbyid(r) end, ',' order by 1)
                            from unnest(pol.polroles) r), '-'),
                coalesce(md5(pg_get_expr(pol.polqual, pol.polrelid)), '-'),
                coalesce(md5(pg_get_expr(pol.polwithcheck, pol.polrelid)), '-'))
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join ns on ns.oid = c.relnamespace
  union all
  select format('D %s %s %s %s', pg_get_userbyid(d.defaclrole), coalesce(n.nspname, '-'), d.defaclobjtype,
                d.defaclacl::text)
    from pg_default_acl d
    left join pg_namespace n on n.oid = d.defaclnamespace
   where d.defaclrole = 'postgres'::regrole
     and (d.defaclnamespace = 0 or n.nspname in (select nspname from s))
)
select l from lines order by l collate "C";

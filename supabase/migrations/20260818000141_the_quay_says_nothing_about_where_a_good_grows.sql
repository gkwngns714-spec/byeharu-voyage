-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0141 — THE QUAY SAYS NOTHING ABOUT WHERE A GOOD GROWS  (the `native` key removed)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"remove native"*. 0084 put `'native', <port region ∈ goods.origin_regions>`
-- beside `'offered'` in every row `world.market(uuid)` serves, for one reader: the trade row's
-- `· native` caption word. No rule reads it — not a price, a refusal, a roster or a schedule. The
-- client drops the caption and the type field in the same slice; this file drops the key, so no dead
-- field is left on the wire.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- SUPERSEDES the deployed body of world.market(uuid) (0032; sliced by 0080, 0084, 0137) by SLICING
-- it, against prod's current body (0137's `tick_market_drift(v_now, p_port)` cut included): ONE
-- hunk — 0084's own — reversed. The `native` key and its comment line go; `offered` closes the row
-- object again exactly as it did before 0084. Asserted to occur exactly once in the live body
-- (LF-normalised), and the new body is asserted to reverse to the pre-image.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
-- Every other key, the drift call, the clock, the join to public.ports (it still feeds range_lo/hi
-- and `available`), goods.origin_regions (0062 still uses it for the roster). No ACL statement is
-- issued: the ACL, volatility, security definer, config and language are asserted unchanged.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION (no table lock); ACCESS SHARE on what the self-assert reads; one
-- world.market read for a sample harbour (its own quay's drift step, idempotent by the slot key —
-- what any read of the quay does). No LOCK TABLE, no set role. Timings by raise notice only.
--
-- ROLLBACK: a forward migration re-applying 0084's hunk (the NEW text below is 0084's OLD text).
-- VERSION: 0141. Applies on prod head 0140 (any head carrying 0137's world.market body).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 1. THE PRE-IMAGE ───────────────────────────────────────────────────────────────────────────
create temp table defs_before_0141 on commit drop as
select replace(pg_get_functiondef(p.oid), E'\r', '') as def,
       coalesce(p.proacl::text, '') as acl,
       p.provolatile as vol,
       p.prosecdef as secdef,
       coalesce(p.proconfig::text, '') as cfg,
       p.proparallel as par,
       l.lanname as lang
  from pg_proc p
  join pg_language l on l.oid = p.prolang
 where p.oid = 'world.market(uuid)'::regprocedure;

create temp table hunk_0141 on commit drop as
select $h$        'offered', public.port_offers(pg.port_id, pg.good_id),
        -- 0084: NATIVE is 0062's own word - the port's region is among the good's origin_regions.
        'native', exists (select 1 from public.regions r where r.id = pr.region_id and r.code = any(g.origin_regions)))$h$ as old_t,
       $h$        'offered', public.port_offers(pg.port_id, pg.good_id))$h$ as new_t;

-- ── 2. THE ONE HUNK ────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_def text := (select def from defs_before_0141);
  v_old text := (select old_t from hunk_0141);
  v_new text := (select new_t from hunk_0141);
  v_n   int;
begin
  if v_def is null then
    raise exception '0141 self-assert FAIL: world.market(uuid) is not deployed';
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then
    raise exception '0141 self-assert FAIL: the native hunk occurs % time(s) in world.market(uuid), expected exactly 1 — the deployed body is not what this migration was cut against', v_n;
  end if;
  execute replace(v_def, v_old, v_new);
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  b        record;
  h        record;
  v_def    text;
  v_acl    text;
  v_vol    "char";
  v_secdef boolean;
  v_cfg    text;
  v_par    "char";
  v_lang   name;
  v_n      int;
  v_port   uuid;
  v_code   text;
  v_rows   int;
  v_keyed  int;
  v_t0     timestamptz;
  v_ms     numeric;
begin
  select * into b from defs_before_0141;
  select * into h from hunk_0141;
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile, p.prosecdef,
         coalesce(p.proconfig::text, ''), p.proparallel, l.lanname
    into v_def, v_acl, v_vol, v_secdef, v_cfg, v_par, v_lang
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = 'world.market(uuid)'::regprocedure;

  -- (a) THE LIVE BODY IS THE PRE-IMAGE WITH EXACTLY THE ONE HUNK SWAPPED, and reverses to it.
  if v_def is distinct from replace(b.def, h.old_t, h.new_t) then
    raise exception '0141 self-assert FAIL: the live world.market body is not the pre-image with the one hunk swapped';
  end if;
  v_n := (length(v_def) - length(replace(v_def, h.new_t, ''))) / length(h.new_t);
  if v_n <> 1 then
    raise exception '0141 self-assert FAIL: the new hunk occurs % time(s) in the live body, expected 1 — it cannot reverse', v_n;
  end if;
  if replace(v_def, h.new_t, h.old_t) is distinct from b.def then
    raise exception '0141 self-assert FAIL: the live body does not reverse to its pre-image';
  end if;
  if strpos(v_def, '''native''') > 0 then
    raise exception '0141 self-assert FAIL: the live world.market body still names a native key';
  end if;

  -- (b) NOTHING BUT THE BODY MOVED.
  if v_acl <> b.acl or v_vol <> b.vol or v_secdef <> b.secdef or v_cfg <> b.cfg or v_par <> b.par or v_lang <> b.lang then
    raise exception '0141 self-assert FAIL: world.market ACL/volatility/definer/config/parallel/language moved (acl % -> %, vol % -> %, secdef % -> %, cfg % -> %)',
      b.acl, v_acl, b.vol, v_vol, b.secdef, v_secdef, b.cfg, v_cfg;
  end if;

  -- (c) NO LIVE BODY SERVES OR READS A `native` KEY (the field is gone, not merely unserved here).
  select count(*) into v_n
    from pg_proc p
   where p.pronamespace <> pg_my_temp_schema()
     and p.pronamespace in (select oid from pg_namespace where nspname in ('public', 'world', 'cmd', 'voyage'))
     and strpos(p.prosrc, '''native''') > 0;
  if v_n <> 0 then
    raise exception '0141 self-assert FAIL: % live bod(ies) still name a native key', v_n;
  end if;

  -- (d) A SERVED ROW CARRIES NO `native` KEY — on the busiest quay (deterministic: count desc, code).
  select pg.port_id into v_port
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
   where p.kind = 'HARBOUR' and public.quay_shows(pg.port_id, pg.good_id)
   group by pg.port_id
   order by count(*) desc, min(p.code)
   limit 1;
  if v_port is null then
    raise exception '0141 self-assert FAIL: no harbour shows a quay row; nothing was examined';
  end if;
  select code into v_code from public.ports where id = v_port;
  v_t0 := clock_timestamp();
  select count(*), count(*) filter (where r ? 'native')
    into v_rows, v_keyed
    from jsonb_array_elements(world.market(v_port)->'goods') r;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1);
  if v_rows = 0 then
    raise exception '0141 self-assert FAIL: world.market(%) served no rows; nothing was examined', v_code;
  end if;
  if v_keyed <> 0 then
    raise exception '0141 self-assert FAIL: world.market(%) served % of % row(s) with a native key', v_code, v_keyed, v_rows;
  end if;
  if exists (select 1 from jsonb_array_elements(world.market(v_port)->'goods') r where not (r ? 'offered')) then
    raise exception '0141 self-assert FAIL: world.market(%) lost the offered key beside native', v_code;
  end if;

  raise notice '0141 self-assert ok: world.market re-cut by one hunk (native key gone, reverses to its pre-image; ACL %, volatility %, definer %, config % unchanged); no live body names a native key; % served % row(s), none with native, in % ms',
    v_acl, v_vol, v_secdef, v_cfg, v_code, v_rows, v_ms;
end $$;

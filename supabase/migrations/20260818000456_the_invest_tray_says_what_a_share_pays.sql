-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0456 - THE INVEST TRAY SAYS WHAT A SHARE PAYS  (the tray showed the price of the shares and nothing of what they give back)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE FAULT (found in play 2026-11-18, docs/dev-log/2026-11-18-play-faults.md fault 2): the Town Hall's Invest tray shows the share count and the
--   cost (cmd.preview_invest, the real public.invest_for rolled back). A share's return is a coupon (public.city_coupons, 0312, re-timed by 0413):
--   works_coupon_day of what was paid, per real day, times public.influence_coupon_mult. Nothing serves it: public.invest_for answers port,
--   kind, shares, price, cost, completed, level, subscribed and purse; world.town_hall reads no rate; no knob is in the snapshot. A rate computed
--   in the client would be a second copy of the rule.
-- THE FIX (one authority):
--   NEW public.coupon_day_of(port, player, paid)   ONE REAL DAY'S COUPON on what was paid: paid x works_coupon_day x
--                                                  public.influence_coupon_mult(port, player). The rule's one home; it was inline in city_coupons.
--   RE-CUT public.city_coupons (2 hunks)           each row's due = round(public.coupon_day_of(port, holder, paid) x the real days since its
--                                                  stamp, capped as before); its v_rate goes (the rate is read by coupon_day_of). Numeric
--                                                  multiplication is exact, so the due is the same figure to the coin (asserted below).
--   RE-CUT public.invest_for (1 hunk)              its answer gains `coupon_day` = round(public.coupon_day_of(port, buyer, cost)): what this buy adds
--                                                  to the buyer's daily coupon (the due is linear in what was paid). cmd.invest and
--                                                  cmd.preview_invest pass it through untouched; the merchants' callers ignore the answer's keys.
-- IT IS AN "UP TO" (city_coupons, read): once a real day the city pays least(sum of dues, city_surplus, its profit since the last coupon), pro
--   rata; the shortfall is not owed. A first day is pro rata to the part of it the stake has been held. The tray says "<= +figure".
-- WHAT A PLAYER SEES CHANGE: the Invest tray's new line, Daily pay / 하루 배당, "<= +N". Nothing that is paid changes.
-- ROWS: none. No table, job, knob or cron. -- budget: none (no table, no job, no index). -- retention: none.
-- COST: one more stable SQL call a holder in city_coupons (a few hundred holders, once a real day); one in invest_for.
-- LOCKS: CREATE OR REPLACE x2 (by hunks), CREATE FUNCTION x1 (server only: no grant). TIME: under 5 s. BUDGET: statement_timeout 45 s,
--   lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): a new migration reversing the 3 hunks (each OLD text is here verbatim), then dropping public.coupon_day_of.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path and owner of the two re-cut bodies unchanged; the new
--   function server only; no other function moved. THE PROBE (rolled back by a raised sentinel; it reads no world_secret and rolls no dice):
--   a probe house buys shares at Lisbon through public.invest_for; its coupon_day is round(cost x works_coupon_day x the multiplier); Lisbon's
--   coupon is then run (its last coupon day set one back, the probe row's stamp a day back): the due city_coupons answers is, to the coin, the
--   sum of 0413's inline formula over the same rows, the probe row is credited no more than its coupon_day, and the city pays no more than
--   the due, its surplus or its profit.
-- VERSION: 0456 = prod head 0454 + 2 (0455 is #761; the lead renumbers at deploy if the order changes).
-- news: none (a figure on the Invest tray: what a share pays a day; nothing that is paid changes)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_def       text;
  v_pre       text;
  v_old       text;
  v_new       text;
  v_n         int;
  v_note      text;
  v_pl        uuid;
  v_lis       uuid;
  v_kind      text;
  v_shares    int;
  v_r         jsonb;
  v_c         jsonb;
  v_want      bigint;
  v_old_due   bigint;
  v_rday      int;
  v_today     int;
  v_surplus   bigint;
  v_profit    bigint;
  v_acc0      bigint;
  v_acc1      bigint;
  x           record;
  c_recut     constant text[] := array['public.invest_for(uuid,uuid,text,integer)', 'public.city_coupons(uuid,timestamp with time zone)'];
  c_new       constant text := 'public.coupon_day_of(uuid,uuid,numeric)';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_recut || array['public.influence_coupon_mult(uuid,uuid)', 'public.city_surplus(uuid)', 'public.real_day(timestamp with time zone)',
                                                    'public.city_offered(uuid,text)', 'cmd.preview_invest(uuid,text,integer)']) f
              where to_regprocedure(f) is null)
     or not exists (select 1 from public.world_config c where c.key = 'works_coupon_day') then
    raise exception '0456 refuses: the coupon (0312, 0413) or the buy (0123) is not in this world';
  end if;
  if to_regprocedure(c_new) is not null then
    raise exception '0456 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0456 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0456
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_recut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut) f));

  -- ── 2. THE RULE'S ONE HOME: one real day's coupon on what was paid ──
  execute $f$
create function public.coupon_day_of(p_port uuid, p_player uuid, p_paid numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0456: ONE REAL DAY'S COUPON on p_paid, held by p_player at p_port: works_coupon_day of what was paid (0312, per REAL day since 0413) times the
  -- holder's multiplier (public.influence_coupon_mult, 0148 D10). Unrounded, before the city's caps. THE rule public.city_coupons pays by (times
  -- the real days since a row's stamp, then capped by the city's surplus and profit) and public.invest_for quotes by (`coupon_day`). Server only.
  select p_paid * public.wc_num('works_coupon_day') * public.influence_coupon_mult(p_port, p_player)
$body$
  $f$;
  revoke all on function public.coupon_day_of(uuid, uuid, numeric) from public, anon, authenticated;

  -- ── 3. THE HUNKS ──
  create temp table hunks_0456 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0456 values
  ('public.city_coupons(uuid,timestamp with time zone)', 1,
$h$  v_rate   numeric := public.wc_num('works_coupon_day');
$h$,
$h$  -- 0456: the rate (works_coupon_day) and the multiplier are read by public.coupon_day_of, the rule's one home
$h$),
  ('public.city_coupons(uuid,timestamp with time zone)', 2,
$h$           round(s.paid * v_rate * least(v_rday - v_last, greatest(0, extract(epoch from public.clock_start('game_day', v_today) - public.clock_start('game_day', s.accrued_day)) / 86400))   -- 0413: the real days between the two day numbers, by the counter's own inverse (it was their difference x the knob)
                 * public.influence_coupon_mult(p_port, s.player_id))::bigint as due   -- 0148 (D10)
$h$,
$h$           round(public.coupon_day_of(p_port, s.player_id, s.paid)   -- 0456: one real day's coupon on what it paid (works_coupon_day x 0148's multiplier)
                 * least(v_rday - v_last, greatest(0, extract(epoch from public.clock_start('game_day', v_today) - public.clock_start('game_day', s.accrued_day)) / 86400)))::bigint as due   -- 0413: the real days between the two day numbers, by the counter's own inverse
$h$),
  ('public.invest_for(uuid,uuid,text,integer)', 1,
$h$                            'purse', v_after);
$h$,
$h$                            'purse', v_after,
                            -- 0456: what this buy adds to the house's daily coupon, by the rule public.city_coupons pays by (public.coupon_day_of).
                            -- An "up to": the city pays it once a real day, only from its surplus and its profit of the day.
                            'coupon_day', round(public.coupon_day_of(p_port, p_player, v_cost))::bigint);
$h$);

  for x in select distinct h.fn from hunks_0456 h loop
    v_pre := (select p.def from pre_0456 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0456 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0456 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0456 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0456 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0456 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0456) <> 3 then
    raise exception '0456 self-assert FAIL: the hunks are not the 3 of the two re-cut bodies';
  end if;
  if position('v_rate' in pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure)) > 0
     or position('influence_coupon_mult' in pg_get_functiondef('public.city_coupons(uuid,timestamp with time zone)'::regprocedure)) > 0 then
    raise exception '0456 self-assert FAIL: public.city_coupons still reads the rate or the multiplier itself';
  end if;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut || array[c_new]) f))) <> v_fn_before then
    raise exception '0456 self-assert FAIL: another function moved';
  end if;
  for x in select p.fn, p.meta,
                  (select coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text
                     from pg_proc q where q.oid = p.fn::regprocedure) as now_meta
             from pre_0456 p loop
    if x.now_meta is distinct from x.meta then
      raise exception '0456 self-assert FAIL: the grants, volatility, definer, search path or owner of % is % and was %', x.fn, x.now_meta, x.meta;
    end if;
  end loop;
  if has_function_privilege('anon', c_new, 'execute') or has_function_privilege('authenticated', c_new, 'execute')
     or (select p.provolatile from pg_proc p where p.oid = c_new::regprocedure) <> 's' then
    raise exception '0456 self-assert FAIL: public.coupon_day_of is reachable by a client or is not stable';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (it reads no world_secret and rolls no dice) ──
  begin
    v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
    if v_lis is null or not exists (select 1 from public.port_treasury t where t.port_id = v_lis) then
      raise exception '0456 self-assert FAIL: no Lisbon, or no purse at Lisbon, in this world';
    end if;
    if not public.city_treasury_on() then
      update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';   -- the probe's own; rolled back
    end if;
    insert into public.players (company_name, nation_id, ducats, is_npc)
    values ('Probe 0456', (select n.id from public.nations n where n.code = 'PRT'), 1000000000, false) returning id into v_pl;
    -- THE BUY: the first work with shares on offer, enough of them to pass the smallest stake
    select k.kind, least(public.city_offered(v_lis, k.kind),
                         greatest(1, ceil(public.wc_int('invest_min_ducats')::numeric / public.works_share_price(coalesce(w.level, 0)))::int))
      into v_kind, v_shares
      from unnest(array['docks', 'market', 'production', 'inn']) with ordinality k(kind, o)
      left join public.city_works w on w.port_id = v_lis and w.kind = k.kind
     where public.city_offered(v_lis, k.kind) > 0
     order by k.o limit 1;
    if v_kind is null then
      raise exception '0456 self-assert FAIL: Lisbon offers no shares in any work';
    end if;
    v_r := public.invest_for(v_pl, v_lis, v_kind, v_shares);
    v_want := round((v_r ->> 'cost')::numeric * public.wc_num('works_coupon_day') * public.influence_coupon_mult(v_lis, v_pl))::bigint;
    if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'coupon_day') is null or (v_r ->> 'coupon_day')::bigint <> v_want then
      raise exception '0456 self-assert FAIL: the buy answers coupon_day % and the rule says % (%)', v_r ->> 'coupon_day', v_want, v_r;
    end if;
    -- THE COUPON: Lisbon's last coupon a real day back, the probe row's stamp a day back; city_coupons' due = 0413's inline formula, to the coin
    v_rday  := public.real_day(now());
    v_today := world.game_day(now());
    update public.port_treasury t set coupon_day = v_rday - 1, profit = greatest(t.profit, 0) where t.port_id = v_lis;
    update public.city_shares s set accrued_day = v_today - 1000 where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
    select s.accrued into v_acc0 from public.city_shares s where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
    select coalesce(sum(round(s.paid * public.wc_num('works_coupon_day')
                                * least(1, greatest(0, extract(epoch from public.clock_start('game_day', v_today) - public.clock_start('game_day', s.accrued_day)) / 86400))
                                * public.influence_coupon_mult(v_lis, s.player_id))::bigint), 0)
      into v_old_due
      from public.city_shares s where s.port_id = v_lis;
    v_surplus := public.city_surplus(v_lis);
    v_profit  := (select t.profit from public.port_treasury t where t.port_id = v_lis);
    v_c := public.city_coupons(v_lis, now());
    select s.accrued into v_acc1 from public.city_shares s where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
    if (v_c ->> 'due')::bigint <> v_old_due or v_old_due < v_want then
      raise exception '0456 self-assert FAIL: city_coupons answers due % and the inline formula of 0413 says % (the probe''s own %)', v_c ->> 'due', v_old_due, v_want;
    end if;
    if (v_c ->> 'paid')::bigint > least((v_c ->> 'due')::bigint, greatest(0, v_surplus), greatest(0, v_profit)) or v_acc1 - v_acc0 > v_want or v_acc1 < v_acc0 then
      raise exception '0456 self-assert FAIL: the city paid % (due %, surplus %, profit %) and the probe was credited % against coupon_day %',
        v_c ->> 'paid', v_c ->> 'due', v_surplus, v_profit, v_acc1 - v_acc0, v_want;
    end if;
    v_note := format('LIS %s x%s for %s: coupon_day %s; Lisbon''s coupon due %s (the inline formula %s), paid %s (surplus %s, profit %s), the probe credited %s',
                     v_kind, v_shares, v_r ->> 'cost', v_want, v_c ->> 'due', v_old_due, v_c ->> 'paid', v_surplus, v_profit, v_acc1 - v_acc0);
    raise exception sqlstate 'BV456' using message = v_note;
  exception when sqlstate 'BV456' then
    get stacked diagnostics v_note = message_text;
  end;
  if exists (select 1 from public.players p where p.company_name = 'Probe 0456') then
    raise exception '0456 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0456 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0456 self-assert ok: THE INVEST TRAY SAYS WHAT A SHARE PAYS. public.coupon_day_of is the coupon rule''s one home; public.city_coupons pays by it (2 hunks) and public.invest_for answers coupon_day by it (1 hunk), each once and reversing; grants and volatility as before; no other function moved. Probe: %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0456;
  drop table pre_0456;
end $m$;

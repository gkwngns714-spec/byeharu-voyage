-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0050 — A REFUSAL IS TWO NUMBERS AND A VERB
--        The server stops writing paragraphs and starts serving FIGURES. Every arithmetic refusal
--        carries {have, need, unit} beside its sentence, all the way to the client, and the
--        sentence shrinks to the one thing the figures cannot say: the REASON.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-08-24, on this sentence:
--
--   "Gaivota carries 2.9 days of stores, and there is no chandler where she is bound — the round
--    trip is 28.7 voyage-days; you need 33.0 — PROVISION first"
--
--   *"too long. make it very concise. This concise concept will have to be applied to all aspects
--    of the game. Always show in graphics, concisely."*
--
-- What the player needs is
--
--       ▁▁▁▂  2.9 / 33 days     [ PROVISION ]
--
-- — a bar, two figures, a verb. src/components/ui/RefusalNote.tsx already draws exactly that from
-- `refusal.figures`, and src/lib/rpc/result.ts already declares the wire shape
-- (`RefusalFigures {have, need, unit}`). Both were written to fall back to the sentence *until the
-- serving migration lands*. This is that migration.
--
-- ── THE LAW THIS FILE EXISTS TO KEEP ───────────────────────────────────────────────────────────
-- THE CLIENT MUST NEVER PARSE A SERVED SENTENCE FOR NUMBERS. A client that regexes "2.9" out of
-- prose is a second author of the refusal, one wording change from lying. The server is the one
-- author of the game's words — the same rule 0030 (crew) and 0033 (shipyard) had to restore after
-- it was broken. So the numbers travel as DATA, from the one place that computed them.
--
-- ── THE MECHANISM, AND WHAT THE ALTERNATIVE WOULD HAVE COST ────────────────────────────────────
-- Two candidates were on the table.
--
--   (a) `voyage.sail_refusal` returns jsonb {code, sentence, figures} and every caller moves.
--   (b) the refusal keeps its text and the RAISE carries the figures separately, in
--       PG_EXCEPTION_DETAIL, which the cmd.* envelope reads.
--
-- NEITHER ALONE IS THE ANSWER, and reading the code is what settles it:
--
--   * (a) alone does not reach the client. `voyage.sail_refusal` RETURNS; `cmd.do_sail` RAISES;
--     the envelope is built in a catch handler (cmd.execute_order, cmd.preview). A returned value
--     does not survive a `raise`. To serve it, `cmd.do_sail` would have to RE-DERIVE have and need
--     for the raise — a second arithmetic, one knob change from disagreeing with the sentence
--     printed beside it. That is the client-regex defect wearing server clothes.
--     And it is narrow: E_HOLD_FULL, E_INSUFFICIENT_FUNDS, E_DAILY_CAP, E_CREW_MAX and the rest
--     are raised straight out of the verb bodies and never pass through sail_refusal at all, so
--     (a) would need a SECOND mechanism for them — two authorities for one concept.
--
--   * (b) alone drifts exactly where the brief warned. `voyage.sail_refusal` must keep RETURNING,
--     because `world.trade_routes` asks it as a silent predicate (`... is null`) and cannot catch
--     an exception per candidate port. So under (b) the author of the sentence and the author of
--     the figures are two different functions, and nothing makes them agree.
--
-- SO: (a) for the AUTHORITY, (b) for the one crossing that already exists.
--   * `voyage.sail_refusal` returns the whole refusal as ONE VALUE — code, sentence and figures
--     from the one function that computed all three. `... is null` still reads the same, so
--     `world.trade_routes` and proof 05 need no change at all: the blast radius is `cmd.do_sail`.
--   * `cmd.refuse(code, sentence, figures)` is the ONE raiser. Three arguments of one statement
--     cannot drift apart. It puts the figures in DETAIL, which is the crossing every refusal
--     already makes.
--   * `cmd.refusal_caught(message, detail)` is its INVERSE, and this is where the file pays for
--     itself: **"split a raised refusal into an envelope" had SIX hand-copied definitions** —
--     cmd.execute_order, cmd.preview (twice), cmd.issue, cmd.provision_preset_save and
--     cmd.run_standing_provision. That is spaghetti, and it is ripped out here rather than copied
--     a seventh time. (FIVE were found by reading; the SIXTH was found by this file's own guard
--     (d), which asks the catalogue instead of my memory — which is the whole reason it asks the
--     catalogue.) All six carried the
--     same latent bug: when the message did NOT start with `E_CODE:`, the code fell back to
--     'E_PARSE' and the sentence was still cut at `length('E_PARSE') + 2`, so an unexpected
--     PostgreSQL error reached the player with its first eight characters shaved off ("division
--     by zero" → "by zero"). One authority, one fix.
--
-- ── THE FIGURES LAW ────────────────────────────────────────────────────────────────────────────
-- `have` is what she HAS or MAY have. `need` is what the order REQUIRES. Same unit, and a refusal
-- always means have < need — so the bar is always have/need and always short. `cmd.figures`
-- ENFORCES that: it raises if have > need, if need is not positive, or if the unit is anything but
-- a bare lower-case NAME. A unit is `days`, `t`, `ducats`, `crew`, `depth` — never a sentence.
--
-- ── THE SENTENCES ──────────────────────────────────────────────────────────────────────────────
-- Shortened, and stripped of two things they should never have carried:
--   * THE ARITHMETIC — it is the bar's job now. E_ENDURANCE's sentence contains no digit at all.
--   * THE FIX — `cmd.fixes()` has been the one author of "→ do this instead" since 0008, and the
--     sentences were repeating it ("— PROVISION first"). A third copy of the verb is deleted.
-- What they KEEP is the REASON, which is the one thing neither a bar nor a fix can say: *no
-- chandler where she is bound* is a real fact about the world and it survives, in the sentence,
-- behind the ⓘ.
--
-- ── WHAT MOVES ─────────────────────────────────────────────────────────────────────────────────
--   NEW      cmd.figures / cmd.refusal / cmd.refuse (2 overloads) / cmd.refusal_caught
--   NEW      public.orders.error_figures jsonb — a failed order is history, and its figures are
--            part of it; cmd.issue and cmd.queue both read the order row, not the exception.
--   DROPPED  voyage.sail_refusal(uuid, uuid, jsonb, numeric) returns text
--   CREATED  voyage.sail_refusal(uuid, uuid, jsonb, numeric) returns jsonb — 0047's body, same
--            gates in the same order, arithmetic unchanged to the character; only the SHAPE of
--            the answer and the wording of the sentences move.
--   SLICED   cmd.do_sail (3 hunks) · cmd.execute_order (2) · cmd.preview (3) · cmd.issue (4) ·
--            cmd.queue (1) · cmd.provision_preset_save (2) · cmd.run_standing_provision (2) ·
--            cmd.do_buy (4) · cmd.do_sell (1) ·
--            cmd.do_provision (2) · cmd.do_hire (3) · cmd.do_repair (1) · public.credit (1) ·
--            public.provision_presets_cap (1)
--   UNTOUCHED, deliberately: world.trade_routes (its `is null` predicate reads a jsonb exactly as
--            it read a text) and scripts/db/proofs/05 (same reason). voyage.path_refusal keeps
--            returning 'E_CODE: sentence' text — E_LAND / E_OFF_COURSE / E_NO_COURSE are not
--            arithmetic, there are no two numbers to draw, and cmd.refusal_caught splits them at
--            the envelope exactly as before.
--
-- ── THE SUPERSEDE, DECLARED ────────────────────────────────────────────────────────────────────
-- The mechanism is argued at length above; the DECLARATION is this paragraph, in the word
-- README §1 uses — "a change goes in a NEW file that supersedes the old one" — because a rule
-- explained is still not a rule declared.
--
-- WHAT IS SUPERSEDED, AND WHY. `voyage.sail_refusal(uuid, uuid, jsonb, numeric)`, cut by 0047,
-- is superseded here. 0047's body could only answer in PROSE, and prose is the one shape the bar
-- cannot be drawn from: to print "2.9 / 33" the client would have to regex the figures back out
-- of the sentence, which is exactly the second author of the refusal this file exists to
-- prevent. The superseding body IS 0047's body — same gates in the same order, arithmetic
-- unchanged to the character — and only the SHAPE of the answer moves, text → jsonb
-- {code, sentence, figures}. 0047 itself is not touched and still proves its own claims when the
-- chain replays in order.
--
-- IT IS A NO-OP WHERE THE NEW INPUT IS ABSENT. `figures` is the whole of what is new, so every
-- caller that does not read it must see what it saw yesterday. `world.trade_routes` and
-- scripts/db/proofs/05 ask the refusal as the silent predicate `... is null`, and a jsonb is null
-- on exactly the voyages a text was null on — neither changes by a character. Self-assert (h)
-- measures that seam as a DELTA instead of claiming it here: the quay must consider MORE ports
-- once her casks are full than it did on thin stores, so the gate is proven still ASKED rather
-- than merely still compiling. `voyage.path_refusal` is deliberately NOT superseded — E_LAND,
-- E_OFF_COURSE and E_NO_COURSE are not arithmetic and have no two numbers to draw.
--
-- EVERYTHING THAT MUST MOVE TOGETHER MOVES IN THIS FILE. That clause is 0017:50-55's scar: do_buy
-- checked room with one function and placed cargo with another function's private copy of the
-- same arithmetic. So the raiser (cmd.refuse), its inverse (cmd.refusal_caught, replacing all six
-- hand-copied splits), the column a failed order keeps its figures in
-- (public.orders.error_figures) and every sliced caller listed under WHAT MOVES land in this one
-- transaction. Nothing is deferred: a chain where the raiser had landed without the reader would
-- serve refusals that nobody downstream could split.
--
-- ── THE SLICES ─────────────────────────────────────────────────────────────────────────────────
-- Every re-cut body is edited by hunks that must occur EXACTLY ONCE in the DEPLOYED definition
-- (pg_get_functiondef), re-asserted at apply time: a drifted deployment refuses rather than
-- half-applies. Nothing is retyped. The hunks were sliced from a locally applied chain on
-- 2026-08-25 and are LF only.
--
-- Depends on: 0007 (execute_order, the verb bodies), 0008 (issue/preview/queue/fixes), 0017/0022
-- (the quay verbs' live bodies), 0030 (the crew are called the crew — the hire sentences below
-- keep that word), 0034 (provision_preset_save, the preset cap), 0047 (sail_refusal, do_sail).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse ─────────────────
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0050 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 1. A failed order keeps its figures ────────────────────────────────────────────────────────
-- The envelope cmd.issue returns is built from the ORDER ROW, not from the exception it caught,
-- so the figures have to survive the write or they never reach the player. They are part of what
-- happened, the same way error_code and error_message are.
alter table public.orders add column if not exists error_figures jsonb;

comment on column public.orders.error_figures is
  '0050: {have, need, unit} for an arithmetic refusal — the two numbers RefusalNote draws as a '
  'bar. Written by cmd.execute_order from the raise''s DETAIL; null for a refusal with no '
  'arithmetic behind it. The client never parses error_message for numbers.';

-- ── 2. THE REFUSAL, as a value ─────────────────────────────────────────────────────────────────
-- WHAT CONCEPT IS THIS: "the game said no, and why, and by how much."
-- WHERE IT LIVES: cmd, because cmd is where a refusal is born, raised, caught and served.
-- WHO THE SECOND CALLER IS: on day one, thirteen — voyage.sail_refusal, six verb bodies, the
--   ledger's debit guard, the preset cap trigger, and the four envelope builders.
-- WHAT WOULD MAKE THIS THE WRONG SHAPE: a refusal that needs THREE numbers, or two units. Then
--   `figures` becomes an array and RefusalNote draws a row of bars — the key stays, the renderer
--   grows. Anyone would find out the day a refusal cannot say what it means with have/need.

create or replace function cmd.figures(p_have numeric, p_need numeric, p_unit text)
returns jsonb
language plpgsql
immutable
as $$
-- THE ONE WRITER of the wire shape. It is deliberately strict: a bar drawn from figures that do
-- not mean have-over-need is worse than no bar, because it is legible and wrong.
begin
  if p_have is null or p_need is null then
    raise exception 'cmd.figures: have and need are both required (got %, %)', p_have, p_need;
  end if;
  if p_need <= 0 then
    raise exception 'cmd.figures: need must be positive — a bar over zero is not a bar (got %)', p_need;
  end if;
  if p_have > p_need then
    raise exception 'cmd.figures: have (%) exceeds need (%) — a refusal means she is SHORT; these two are the wrong way round', p_have, p_need;
  end if;
  if p_unit !~ '^[a-z]+$' then
    raise exception 'cmd.figures: the unit is a NAME, not a sentence (got %)', p_unit;
  end if;
  -- rounded HERE, once, to the digit the client prints — so the number the player reads and the
  -- number the server served are the same number.
  return jsonb_build_object('have', round(p_have, 1), 'need', round(p_need, 1), 'unit', p_unit);
end $$;

comment on function cmd.figures(numeric, numeric, text) is
  '0050: THE one writer of a refusal''s two numbers. have = what she has, need = what the order '
  'requires, same unit, and have < need always. Raises rather than serve a bar that would be '
  'legible and wrong.';

create or replace function cmd.refusal(p_code text, p_sentence text, p_figures jsonb default null)
returns jsonb
language sql
immutable
as $$
  -- THE refusal value. jsonb_strip_nulls so an absent `figures` is absent, not JSON null: the
  -- client reads `figures?` and a null there must degrade to the sentence, never to a NaN bar.
  select jsonb_strip_nulls(jsonb_build_object(
           'code', p_code, 'sentence', btrim(p_sentence), 'figures', p_figures))
$$;

comment on function cmd.refusal(text, text, jsonb) is
  '0050: a refusal as ONE value — {code, sentence, figures}. voyage.sail_refusal returns it; '
  'cmd.refuse raises it; cmd.refusal_caught rebuilds it from what was caught.';

create or replace function cmd.refuse(p_refusal jsonb)
returns void
language plpgsql
volatile
as $$
-- THE one raiser. The wire format stays 'E_CODE: sentence' — every catcher in the chain, and
-- src/lib/rpc/result.ts's RAISED_RE, already read that — and the figures ride in DETAIL, which is
-- structured data PostgreSQL carries beside the message and nobody has to parse out of prose.
begin
  raise exception '%: %', p_refusal->>'code', p_refusal->>'sentence'
    using errcode = 'P0001', detail = coalesce((p_refusal->'figures')::text, '');
end $$;

create or replace function cmd.refuse(p_code text, p_sentence text, p_figures jsonb default null)
returns void
language sql
volatile
as $$
  -- The same act, spelled for a refusal being authored on the spot. It DELEGATES; there is no
  -- second raise in this file.
  select cmd.refuse(cmd.refusal(p_code, p_sentence, p_figures))
$$;

comment on function cmd.refuse(text, text, jsonb) is
  '0050: THE one way a verb refuses. Code, sentence and figures are three arguments of one '
  'statement, so they cannot drift apart. Supersedes thirteen hand-written RAISE sites.';

create or replace function cmd.refusal_caught(p_message text, p_detail text default null)
returns jsonb
language plpgsql
immutable
as $$
-- THE inverse of cmd.refuse, and the retirement of SIX hand-copied splits (cmd.execute_order,
-- cmd.preview x2, cmd.issue, cmd.provision_preset_save). All five also shaved the first eight
-- characters off any message that was NOT 'E_CODE: …' — they fell back to 'E_PARSE' and then cut
-- at length('E_PARSE') + 2 regardless. Fixed here, once: a message with no code is kept WHOLE.
declare
  v_code text := case when p_message ~ '^E_[A-Z0-9_]+:' then split_part(p_message, ':', 1) else null end;
  v_figs jsonb;
begin
  if coalesce(p_detail, '') <> '' then
    begin
      v_figs := p_detail::jsonb;
    exception when others then
      v_figs := null;
    end;
    -- Only the shape cmd.figures writes. A real PostgreSQL DETAIL ("Key (id)=(…) already exists")
    -- is never that shape, so this cannot mistake one for the other.
    if v_figs is null
       or jsonb_typeof(v_figs) is distinct from 'object'
       or jsonb_typeof(v_figs->'have') is distinct from 'number'
       or jsonb_typeof(v_figs->'need') is distinct from 'number'
       or jsonb_typeof(v_figs->'unit') is distinct from 'string' then
      v_figs := null;
    end if;
  end if;
  if v_code is null then
    return cmd.refusal('E_PARSE', p_message, v_figs);
  end if;
  return cmd.refusal(v_code, substr(p_message, length(v_code) + 2), v_figs);
end $$;

comment on function cmd.refusal_caught(text, text) is
  '0050: THE one split of a caught refusal into {code, sentence, figures}. Pass sqlerrm and '
  'PG_EXCEPTION_DETAIL. Retires the six hand-copied copies and the message-truncation bug all '
  'six carried.';

revoke all on function cmd.figures(numeric, numeric, text)   from public, anon, authenticated;
revoke all on function cmd.refusal(text, text, jsonb)        from public, anon, authenticated;
revoke all on function cmd.refuse(jsonb)                     from public, anon, authenticated;
revoke all on function cmd.refuse(text, text, jsonb)         from public, anon, authenticated;
revoke all on function cmd.refusal_caught(text, text)        from public, anon, authenticated;

-- ── 3. THE one answer to "may this fleet sail there?", now carrying its own figures ────────────
drop function voyage.sail_refusal(uuid, uuid, jsonb, numeric);

create function voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_dest_point jsonb, p_nm numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- Supersedes 0047's TEXT body. THE GATES, THEIR ORDER AND THEIR ARITHMETIC ARE UNCHANGED to the
-- character — status, crew, flagship, the berth facts for a harbour, and the stores gate with the
-- no-chandler round trip. What moves is the SHAPE of the answer (cmd.refusal instead of
-- 'E_CODE: sentence') and the WORDING, which sheds the numbers the bar now draws and the fix
-- cmd.fixes already owns.
--
-- `... is null` still means "she may sail", so world.trade_routes' predicate and proof 05 read a
-- jsonb exactly as they read a text: this type change has ONE consumer, cmd.do_sail.
declare
  f       public.fleets%rowtype;
  v_short int;
  v_crew  numeric;
  v_full  numeric;
  v_flag  numeric;
  v_draft int;
  v_maxd  int;
  v_kind  text;
  v_speed numeric;
  v_days  numeric;
  v_end   numeric;
  v_back  numeric := 0;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null then
    return cmd.refusal('E_NO_SUCH_FLEET', 'there is no such fleet');
  end if;
  if f.status not in ('DOCKED', 'ANCHORED') then
    return cmd.refusal('E_NOT_DOCKED',
      format('she is %s — a fleet sails from a quay or from her own anchor', f.status));
  end if;

  -- the same predicate 0047 counted by; the two sums are the figures for the very ships it counts
  select count(*), coalesce(sum(s.crew), 0), coalesce(sum(c.crew_required), 0)
    into v_short, v_crew, v_full
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.crew < c.crew_required;
  if v_short > 0 then
    return cmd.refusal('E_CREW_SHORT', format('%s ship(s) are short of crew', v_short),
                       cmd.figures(v_crew, v_full, 'crew'));
  end if;

  select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;
  if coalesce(v_flag, 0) <= 0 then
    return cmd.refusal('E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail');
  end if;

  if p_dest is not null then
    select kind into v_kind from public.ports where id = p_dest;
    if v_kind = 'HARBOUR' then
      select max(c.draft) into v_draft from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = p_fleet;
      select max_draft into v_maxd from public.ports where id = p_dest;
      if v_draft > v_maxd then
        return cmd.refusal('E_DRAFT', 'her deepest hull draws more than that quay takes',
                           cmd.figures(v_maxd, v_draft, 'depth'));
      end if;
      if (select is_ice_closed from public.ports where id = p_dest) then
        return cmd.refusal('E_PORT_CLOSED', 'ice has closed that port');
      end if;
    end if;
  end if;

  v_speed := voyage.fleet_speed(p_fleet);
  v_end   := voyage.endurance_days(p_fleet);
  if p_dest is not null and (select kind from public.ports where id = p_dest) = 'SEA_PLACE' then
    select min(e.nm::numeric) into v_back
      from public.sea_reaches sr
     cross join lateral jsonb_each_text(sr.reaches) e(code, nm)
      join public.ports hp on hp.code = e.code and hp.kind = 'HARBOUR'
     where sr.port_id = p_dest;
  elsif p_dest is null and p_dest_point is not null then
    v_back := p_nm;
  end if;
  v_days := ((p_nm + coalesce(v_back, 0)) / v_speed) / 24;
  if v_end < v_days * public.wc_num('endurance_margin') then
    if coalesce(v_back, 0) > 0 then
      -- THE REASON SURVIVES. The bar says 2.9 / 33 days; only this sentence can say why 33.
      return cmd.refusal('E_ENDURANCE',
        'no chandler where she is bound — the casks must cover the way home too',
        cmd.figures(v_end, v_days * public.wc_num('endurance_margin'), 'days'));
    end if;
    return cmd.refusal('E_ENDURANCE', 'the passage is longer than her casks',
      cmd.figures(v_end, v_days * public.wc_num('endurance_margin'), 'days'));
  end if;
  return null;
end $$;

comment on function voyage.sail_refusal(uuid, uuid, jsonb, numeric) is
  'THE one answer to "may this fleet sail there, right now?" — status, crew, flagship, berth '
  'facts for harbours, and the stores gate with the no-chandler round trip. Returns the refusal '
  'as a VALUE — {code, sentence, figures} — or null when she may sail. cmd.do_sail raises what '
  'this returns and world.trade_routes refuses to recommend what this refuses. Supersedes 0047''s '
  'text body (0050).';

revoke all on function voyage.sail_refusal(uuid, uuid, jsonb, numeric) from public, anon, authenticated;

-- ── 4. THE MOVER raises the value the gate returned ────────────────────────────────────────────
select pg_temp.recut('cmd.do_sail(uuid, jsonb)'::regprocedure, false,
  $ds0$  v_ref    text;
  v_nm     numeric;$ds0$,
  $ds1$  v_ref    text;
  v_gate   jsonb;
  v_nm     numeric;$ds1$,
  $ds2$  v_ref := voyage.sail_refusal(p_fleet, v_dest, v_point, 0);
  if v_ref is not null then
    raise exception '%', v_ref using errcode = 'P0001';
  end if;$ds2$,
  $ds3$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, 0);
  if v_gate is not null then
    perform cmd.refuse(v_gate);
  end if;$ds3$,
  $ds4$  v_ref := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm);
  if v_ref is not null then
    raise exception '%', v_ref using errcode = 'P0001';
  end if;$ds4$,
  $ds5$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm);
  if v_gate is not null then
    perform cmd.refuse(v_gate);
  end if;$ds5$);
revoke all on function cmd.do_sail(uuid, jsonb) from public, anon, authenticated;

-- ── 5. THE FOUR ENVELOPE BUILDERS, folded onto ONE split ───────────────────────────────────────
-- Each of these caught 'E_CODE: sentence' and split it by hand. They now ask cmd.refusal_caught,
-- which also hands back the figures the raise carried in DETAIL.

select pg_temp.recut('cmd.execute_order(uuid)'::regprocedure, false,
  $eo0$  v_code text;
  v_msg  text;
begin$eo0$,
  $eo1$  v_code text;
  v_msg  text;
  v_det  text;
  v_ref  jsonb;
begin$eo1$,
  $eo2$    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    update public.orders
       set status = 'failed', error_code = v_code,
           error_message = btrim(substr(v_msg, length(v_code) + 2)), executed_at = now()
     where id = o.id;
    return jsonb_build_object('ok', false, 'error_code', v_code,
                              'error_message', btrim(substr(v_msg, length(v_code) + 2)));$eo2$,
  $eo3$    v_msg  := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref  := cmd.refusal_caught(v_msg, v_det);
    v_code := v_ref->>'code';
    update public.orders
       set status = 'failed', error_code = v_code,
           error_message = v_ref->>'sentence', error_figures = v_ref->'figures',
           executed_at = now()
     where id = o.id;
    return jsonb_build_object('ok', false, 'error_code', v_code,
                              'error_message', v_ref->>'sentence',
                              'figures', v_ref->'figures');$eo3$);
revoke all on function cmd.execute_order(uuid) from public, anon, authenticated;

select pg_temp.recut('cmd.preview(uuid, text, jsonb)'::regprocedure, false,
  $pv0$  v_msg    text;
  v_out    jsonb;
begin$pv0$,
  $pv1$  v_msg    text;
  v_out    jsonb;
  v_det    text;
  v_ref    jsonb;
begin$pv1$,
  $pv2$    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    return jsonb_build_object('ok', false, 'error_code', v_code,
                              'error_message', btrim(substr(v_msg, length(v_code) + 2)),
                              'fixes', cmd.fixes(v_code, p_fleet));$pv2$,
  $pv3$    v_msg  := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref  := cmd.refusal_caught(v_msg, v_det);
    v_code := v_ref->>'code';
    return jsonb_build_object('ok', false, 'error_code', v_code,
                              'error_message', v_ref->>'sentence',
                              'figures', v_ref->'figures',
                              'fixes', cmd.fixes(v_code, p_fleet));$pv3$,
  $pv4$    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    return jsonb_build_object('ok', false, 'parsed', v_parsed, 'error_code', v_code,
                              'error_message', btrim(substr(v_msg, length(v_code) + 2)),
                              'fixes', cmd.fixes(v_code, (v_parsed->>'fleet_id')::uuid));$pv4$,
  $pv5$    v_msg  := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref  := cmd.refusal_caught(v_msg, v_det);
    v_code := v_ref->>'code';
    return jsonb_build_object('ok', false, 'parsed', v_parsed, 'error_code', v_code,
                              'error_message', v_ref->>'sentence',
                              'figures', v_ref->'figures',
                              'fixes', cmd.fixes(v_code, (v_parsed->>'fleet_id')::uuid));$pv5$);
revoke all on function cmd.preview(uuid, text, jsonb) from public, anon;
grant execute on function cmd.preview(uuid, text, jsonb) to authenticated;

-- THE SIXTH COPY, and it was found by this file's own guard rather than by reading — the count in
-- the header said FIVE and the catalogue said six. A standing order that a chandler refuses WRITES
-- the refusal into the ledger (0034 decision 4), and that write had its own hand-rolled split. It
-- now records the figures too: "the purse will not cover the stores" is a better line with the two
-- numbers behind it than without, and the event is where a player reads what happened while they
-- were not looking.
select pg_temp.recut('cmd.run_standing_provision(uuid)'::regprocedure, false,
  $rs0$  v_msg    text;
  v_code   text;
begin$rs0$,
  $rs1$  v_msg    text;
  v_code   text;
  v_det    text;
  v_ref    jsonb;
begin$rs1$,
  $rs2$    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    -- The refusal is WRITTEN, or an automatic order that quietly did nothing would be
    -- indistinguishable from a bug (header decision 4). world.ledger serves this row.
    perform public.emit_event(f.player_id, 'PROVISION_REFUSED', jsonb_build_object(
      'fleet', f.name, 'preset', pr.name, 'days', pr.days,
      'code', v_code, 'reason', btrim(substr(v_msg, length(v_code) + 2))));$rs2$,
  $rs3$    v_msg  := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref  := cmd.refusal_caught(v_msg, v_det);
    v_code := v_ref->>'code';
    -- The refusal is WRITTEN, or an automatic order that quietly did nothing would be
    -- indistinguishable from a bug (header decision 4). world.ledger serves this row.
    perform public.emit_event(f.player_id, 'PROVISION_REFUSED',
      jsonb_strip_nulls(jsonb_build_object(
        'fleet', f.name, 'preset', pr.name, 'days', pr.days,
        'code', v_code, 'reason', v_ref->>'sentence', 'figures', v_ref->'figures')));$rs3$);
revoke all on function cmd.run_standing_provision(uuid) from public, anon, authenticated;

select pg_temp.recut('cmd.issue(uuid, text, int, jsonb)'::regprocedure, false,
  $is0$  v_code    text;
  v_msg     text;
begin$is0$,
  $is1$  v_code    text;
  v_msg     text;
  v_det     text;
  v_ref     jsonb;
begin$is1$,
  $is2$    v_msg  := sqlerrm;
    v_code := case when v_msg ~ '^E_[A-Z_]+:' then split_part(v_msg, ':', 1) else 'E_PARSE' end;
    return jsonb_build_object('ok', false, 'error_code', v_code,
      'error_message', btrim(substr(v_msg, length(v_code) + 2)),
      'fixes', cmd.fixes(v_code, p_fleet), 'queue', cmd.queue(p_fleet));$is2$,
  $is3$    v_msg  := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
    v_ref  := cmd.refusal_caught(v_msg, v_det);
    v_code := v_ref->>'code';
    return jsonb_build_object('ok', false, 'error_code', v_code,
      'error_message', v_ref->>'sentence', 'figures', v_ref->'figures',
      'fixes', cmd.fixes(v_code, p_fleet), 'queue', cmd.queue(p_fleet));$is3$,
  $is4$  select jsonb_build_object('id', o.id, 'seq', o.seq, 'status', o.status,
                            'error_code', o.error_code, 'error_message', o.error_message,
                            'result', o.result)
    into v_res from public.orders o where o.id = v_order;$is4$,
  $is5$  select jsonb_build_object('id', o.id, 'seq', o.seq, 'status', o.status,
                            'error_code', o.error_code, 'error_message', o.error_message,
                            'figures', o.error_figures,
                            'result', o.result)
    into v_res from public.orders o where o.id = v_order;$is5$,
  $is6$    'error_code', v_res->>'error_code',
    'error_message', v_res->>'error_message',$is6$,
  $is7$    'error_code', v_res->>'error_code',
    'error_message', v_res->>'error_message',
    'figures', v_res->'figures',$is7$);
revoke all on function cmd.issue(uuid, text, int, jsonb) from public, anon;
grant execute on function cmd.issue(uuid, text, int, jsonb) to authenticated;

select pg_temp.recut('cmd.queue(uuid)'::regprocedure, false,
  $q0$           'status', o.status, 'error_code', o.error_code, 'error_message', o.error_message,
           'result', o.result) order by o.seq), '[]'::jsonb)$q0$,
  $q1$           'status', o.status, 'error_code', o.error_code, 'error_message', o.error_message,
           'figures', o.error_figures,
           'result', o.result) order by o.seq), '[]'::jsonb)$q1$);
revoke all on function cmd.queue(uuid) from public, anon, authenticated;

select pg_temp.recut('cmd.provision_preset_save(uuid, text, int)'::regprocedure, false,
  $pp0$  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
begin$pp0$,
  $pp1$  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
  v_ref    jsonb;
begin$pp1$,
  $pp2$      if sqlerrm ~ '^E_[A-Z_]+:' then
        return jsonb_build_object('ok', false, 'error_code', split_part(sqlerrm, ':', 1),
          'error_message', btrim(substr(sqlerrm, length(split_part(sqlerrm, ':', 1)) + 2)),
          'fixes', jsonb_build_array('(strike an order from the book first)'));
      end if;$pp2$,
  $pp3$      if sqlerrm ~ '^E_[A-Z0-9_]+:' then
        v_ref := cmd.refusal_caught(sqlerrm);
        return jsonb_build_object('ok', false, 'error_code', v_ref->>'code',
          'error_message', v_ref->>'sentence',
          'fixes', jsonb_build_array('(strike an order from the book first)'));
      end if;$pp3$);
revoke all on function cmd.provision_preset_save(uuid, text, int) from public, anon;
grant execute on function cmd.provision_preset_save(uuid, text, int) to authenticated;

-- ── 6. THE ARITHMETIC SIBLINGS ─────────────────────────────────────────────────────────────────
-- Every refusal in the game whose reason is "she is short by this much" now serves the two
-- numbers and says only WHY. Refusals with no arithmetic behind them (E_NO_STOCK, E_NO_CARGO,
-- E_UNAVAILABLE, E_NO_YARD, E_NOT_DOCKED, E_PARSE …) are deliberately untouched: there is no bar
-- to draw, and a sentence is the honest whole of the answer.

select pg_temp.recut('cmd.do_buy(uuid, jsonb)'::regprocedure, false,
  $b0$    raise exception 'E_HOLD_FULL: there is no room aboard for %', g.name using errcode = 'P0001';$b0$,
  $b1$    perform cmd.refuse('E_HOLD_FULL', format('no room aboard for %s', g.name));$b1$,
  $b2$    raise exception 'E_HOLD_FULL: the fleet has room for % tuns of % and you asked for %',
      v_free, g.name, v_qty using errcode = 'P0001';$b2$,
  $b3$    perform cmd.refuse('E_HOLD_FULL', format('more %s than the hold will take', g.name),
      cmd.figures(v_free, v_qty, 't'));$b3$,
  $b4$    raise exception 'E_DAILY_CAP: you may take % more tuns of % here today', floor(v_cap), g.name using errcode = 'P0001';$b4$,
  $b5$    perform cmd.refuse('E_DAILY_CAP', format('the day''s allowance of %s is spent', g.name),
      cmd.figures(floor(v_cap), v_qty, 't'));$b5$,
  $b6$    raise exception 'E_INSUFFICIENT_FUNDS: % tuns of % cost % d. and you hold %',
      q.units, g.name, q.total, v_purse using errcode = 'P0001';$b6$,
  $b7$    perform cmd.refuse('E_INSUFFICIENT_FUNDS', format('the purse will not cover that much %s', g.name),
      cmd.figures(v_purse, q.total, 'ducats'));$b7$);
revoke all on function cmd.do_buy(uuid, jsonb) from public, anon, authenticated;

select pg_temp.recut('cmd.do_sell(uuid, jsonb)'::regprocedure, false,
  $s0$    raise exception 'E_DAILY_CAP: you may move % more tuns of % here today', floor(v_cap), g.name using errcode = 'P0001';$s0$,
  $s1$    perform cmd.refuse('E_DAILY_CAP', format('the day''s allowance of %s is spent', g.name),
      cmd.figures(floor(v_cap), v_qty, 't'));$s1$);
revoke all on function cmd.do_sell(uuid, jsonb) from public, anon, authenticated;

select pg_temp.recut('cmd.do_provision(uuid, jsonb)'::regprocedure, false,
  $pr0$    raise exception 'E_HOLD_FULL: there is no room for more stores' using errcode = 'P0001';$pr0$,
  $pr1$    perform cmd.refuse('E_HOLD_FULL', 'the casks are already full');$pr1$,
  $pr2$    raise exception 'E_INSUFFICIENT_FUNDS: stores cost % d. and you hold %', v_cost, v_purse using errcode = 'P0001';$pr2$,
  $pr3$    perform cmd.refuse('E_INSUFFICIENT_FUNDS', 'the purse will not cover the stores',
      cmd.figures(v_purse, v_cost, 'ducats'));$pr3$);
revoke all on function cmd.do_provision(uuid, jsonb) from public, anon, authenticated;

select pg_temp.recut('cmd.do_hire(uuid, jsonb)'::regprocedure, false,
  $h0$    raise exception 'E_CREW_MAX: the fleet has berths for % more crew', v_room using errcode = 'P0001';$h0$,
  $h1$    perform cmd.refuse('E_CREW_MAX', 'more crew than she has berths',
      cmd.figures(v_room, v_count, 'crew'));$h1$,
  $h2$    raise exception 'E_CREW_POOL: there is no crew to be had in this port' using errcode = 'P0001';$h2$,
  $h3$    perform cmd.refuse('E_CREW_POOL', 'no crew to be had in this port',
      cmd.figures(0, v_count, 'crew'));$h3$,
  $h4$    raise exception 'E_INSUFFICIENT_FUNDS: % crew cost % d. and you hold %', v_count, v_cost, v_purse using errcode = 'P0001';$h4$,
  $h5$    perform cmd.refuse('E_INSUFFICIENT_FUNDS', 'the purse will not cover that much crew',
      cmd.figures(v_purse, v_cost, 'ducats'));$h5$);
revoke all on function cmd.do_hire(uuid, jsonb) from public, anon, authenticated;

select pg_temp.recut('cmd.do_repair(uuid, jsonb)'::regprocedure, false,
  $rp0$    raise exception 'E_INSUFFICIENT_FUNDS: the repair costs % d. and you hold %', v_cost, v_purse using errcode = 'P0001';$rp0$,
  $rp1$    perform cmd.refuse('E_INSUFFICIENT_FUNDS', 'the purse will not cover the repair',
      cmd.figures(v_purse, v_cost, 'ducats'));$rp1$);
revoke all on function cmd.do_repair(uuid, jsonb) from public, anon, authenticated;

-- The ledger's own debit guard. Its sentence printed a raw player UUID at the player — a number
-- nobody can defend and nobody asked for.
select pg_temp.recut('public.credit(uuid, text, bigint, uuid)'::regprocedure, false,
  $cr0$    raise exception 'E_INSUFFICIENT_FUNDS: % has % ducats and the order costs %',
      p_player, v_before, -p_delta using errcode = 'P0001';$cr0$,
  $cr1$    perform cmd.refuse('E_INSUFFICIENT_FUNDS', 'the purse will not cover it',
      cmd.figures(v_before, -p_delta, 'ducats'));$cr1$);
revoke all on function public.credit(uuid, text, bigint, uuid) from public, anon, authenticated;

-- The preset cap. NO FIGURES, deliberately: "0 slots free of 1 needed" is a bar that tells the
-- player nothing they cannot read in three words, and the one number that matters — the cap — is
-- in the sentence.
select pg_temp.recut('public.provision_presets_cap()'::regprocedure, false,
  $pc0$    raise exception 'E_PRESET_CAP: the book holds % standing orders already, which is all it holds',
      v_max using errcode = 'P0001';$pc0$,
  $pc1$    perform cmd.refuse('E_PRESET_CAP', format('the book is full at %s standing orders', v_max));$pc1$);


-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe constant uuid := '00000000-0050-4000-8000-000000000001';
  v_course_pt constant jsonb := '[[38.71,-9.14],[33,-15]]'::jsonb;
  v_player uuid; v_fleet uuid; v_lis uuid; v_good text; v_room int;
  v_res jsonb; v_prev jsonb; v_q jsonb; v_f jsonb; v_ref jsonb;
  v_end numeric; v_need numeric; v_msg text; v_det text; v_copies text;
  v_routes jsonb; v_thin int; v_fat int;
  v_sentence text; v_fixes int; v_hold_msg text;
  v_bit boolean;
begin
  -- (a) THE FIGURES SHAPE IS ONE SHAPE — the owner's own spelling, "2.9 / 33 days".
  if cmd.figures(2.9, 33, 'days') is distinct from '{"have": 2.9, "need": 33.0, "unit": "days"}'::jsonb then
    raise exception '0050 self-assert FAIL: cmd.figures did not write the owner''s own shape, got %',
      cmd.figures(2.9, 33, 'days');
  end if;

  -- POSITIVE CONTROL, four separate blocks so no CASE can fold them into one. A guard that
  -- cannot be shown to bite is decoration.
  v_bit := false;
  begin perform cmd.figures(33, 2.9, 'days');    exception when others then v_bit := true; end;
  if not v_bit then raise exception '0050 self-assert FAIL: cmd.figures accepted have > need — the bar would be legible and wrong'; end if;
  v_bit := false;
  begin perform cmd.figures(0, 0, 'days');       exception when others then v_bit := true; end;
  if not v_bit then raise exception '0050 self-assert FAIL: cmd.figures accepted need = 0 — a bar over zero is not a bar'; end if;
  v_bit := false;
  begin perform cmd.figures(2.9, 33, 'days of stores'); exception when others then v_bit := true; end;
  if not v_bit then raise exception '0050 self-assert FAIL: cmd.figures accepted a SENTENCE as a unit'; end if;
  v_bit := false;
  begin perform cmd.figures(null, 33, 'days');   exception when others then v_bit := true; end;
  if not v_bit then raise exception '0050 self-assert FAIL: cmd.figures accepted a null have'; end if;

  -- (b) RAISE AND CATCH ARE INVERSES. The figures survive the crossing as DATA — nobody parses
  --     prose for a number, on either side of it.
  v_bit := false;
  begin
    perform cmd.refuse('E_ENDURANCE', 'the passage is longer than her casks', cmd.figures(2.9, 33, 'days'));
  exception when sqlstate 'P0001' then
    v_bit := true;
    v_msg := sqlerrm;
    get stacked diagnostics v_det = pg_exception_detail;
  end;
  if not v_bit then
    raise exception '0050 self-assert FAIL: cmd.refuse returned instead of raising';
  end if;
  v_ref := cmd.refusal_caught(v_msg, v_det);
  if v_ref->>'code' <> 'E_ENDURANCE'
     or v_ref->>'sentence' <> 'the passage is longer than her casks'
     or v_ref->'figures' is distinct from cmd.figures(2.9, 33, 'days') then
    raise exception '0050 self-assert FAIL: the round trip through RAISE lost something — got % (message "%", detail "%")',
      v_ref, v_msg, v_det;
  end if;

  -- (c) A MESSAGE THAT IS NOT A REFUSAL KEEPS ITS FIRST EIGHT CHARACTERS. All five hand-copied
  --     splits fell back to 'E_PARSE' and then cut at length('E_PARSE') + 2 regardless, so
  --     "division by zero" reached the player as "by zero". That is the bug the fold fixed.
  if cmd.refusal_caught('division by zero')->>'sentence' <> 'division by zero'
     or cmd.refusal_caught('division by zero')->>'code' <> 'E_PARSE' then
    raise exception '0050 self-assert FAIL: a non-refusal message was mangled — got %',
      cmd.refusal_caught('division by zero');
  end if;
  -- and a real PostgreSQL DETAIL is never mistaken for figures
  if cmd.refusal_caught('E_X: y', 'Key (id)=(1) already exists.') ? 'figures'
     or cmd.refusal_caught('E_X: y', '{"have": 1}') ? 'figures'
     or cmd.refusal_caught('E_X: y', '{"have": 1, "need": 2, "unit": 7}') ? 'figures' then
    raise exception '0050 self-assert FAIL: cmd.refusal_caught accepted a DETAIL that is not figures';
  end if;

  -- (d) THE FIVE COPIES ARE GONE. Probe CODE, not prose: comments are stripped first, because a
  --     comment naming the old regex would pass this while the code still carried it (0303's
  --     lesson, recorded again in 0305).
  select string_agg(n.nspname || '.' || p.proname, ', ') into v_copies
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'voyage', 'cmd', 'world')
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') like '%^E\_[A-Z\_]+:%';
  if v_copies is not null then
    raise exception '0050 self-assert FAIL: a hand-copied refusal split still stands in % — cmd.refusal_caught is meant to be the only one', v_copies;
  end if;

  select id into v_lis from public.ports where code = 'LIS';

  begin
    -- THE PROBE OWNS ITS WEATHER. 0031 rotates the world secret on every apply, so hazards differ
    -- run to run; three migrations have been broken by a probe that sailed into its own dice.
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';

    v_player := public.new_house(c_probe, 'Casa das Duas Cifras', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id into v_fleet from public.fleets where player_id = v_player;
    -- and its own crew, so the gate under test is the STORES gate and not the crew one
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - sh.crew from public.ships sh
         join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));
    -- and its own larder: thin stores (0047's own idiom) so the round-trip gate must bite
    update public.ships set water_t = 1, food_t = 1 where fleet_id = v_fleet;
    v_end := round(voyage.endurance_days(v_fleet), 1);

    -- (e) THE REAL REFUSAL, through the one door the client uses.
    v_res := cmd.issue(v_fleet, 'SAIL TO 33,-15', null, v_course_pt);
    v_f := v_res->'figures';
    v_sentence := v_res->>'error_message';
    v_fixes := jsonb_array_length(v_res->'fixes');
    if v_res->>'error_code' is distinct from 'E_ENDURANCE' then
      raise exception '0050 self-assert FAIL: a thin-stores pinpoint SAIL was not refused E_ENDURANCE (got [%: %])',
        v_res->>'error_code', v_sentence;
    end if;
    if v_f is null or jsonb_typeof(v_f) <> 'object' or v_f->>'unit' <> 'days'
       or (v_f->>'have')::numeric >= (v_f->>'need')::numeric then
      raise exception '0050 self-assert FAIL: E_ENDURANCE reached the client without usable figures — got %', v_f;
    end if;
    v_need := (v_f->>'need')::numeric;
    -- THE SERVED NUMBER IS THE AUTHORITY'S OWN. If these two ever differ, some second arithmetic
    -- has been written, which is the whole defect this file exists to make impossible.
    if (v_f->>'have')::numeric <> v_end then
      raise exception '0050 self-assert FAIL: the served have (%) is not voyage.endurance_days (%)',
        v_f->>'have', v_end;
    end if;
    -- THE OWNER'S LAW, MADE ASSERTABLE. The sentence no longer carries the arithmetic (the bar's
    -- job) nor repeats the fix (cmd.fixes' job); it carries the REASON, which is the one thing
    -- neither of those can say.
    if v_sentence ~ '[0-9]' then
      raise exception '0050 self-assert FAIL: the E_ENDURANCE sentence still carries a number — that is the bar''s job now: "%"', v_sentence;
    end if;
    if length(v_sentence) > 80 then
      raise exception '0050 self-assert FAIL: the E_ENDURANCE sentence is % characters — "very concise" it is not: "%"', length(v_sentence), v_sentence;
    end if;
    if position('chandler' in v_sentence) = 0 then
      raise exception '0050 self-assert FAIL: the E_ENDURANCE sentence lost its REASON — no chandler where she is bound is a real fact and must survive: "%"', v_sentence;
    end if;
    if v_fixes < 1 then
      raise exception '0050 self-assert FAIL: the refusal arrived with no fix to press';
    end if;

    -- (f) THE FAILED ORDER KEEPS THEM: the queue the client renders carries the same two numbers,
    --     so a halted fleet shows the bar too and not a second, prose-only rendering.
    select jsonb_agg(x) into v_q from jsonb_array_elements(v_res->'queue') x
     where x->>'status' = 'failed';
    if v_q is null or jsonb_array_length(v_q) <> 1 or v_q->0->'figures' is distinct from v_f then
      raise exception '0050 self-assert FAIL: the halted order in the served queue does not carry the refusal''s figures — got %', v_q;
    end if;

    perform cmd.clear(v_fleet, true);

    -- (g) AND THE DRY RUN AGREES. cmd.preview catches the raise directly; cmd.issue reads it back
    --     off the order row. Two different paths to the same two numbers, and they must not
    --     disagree by so much as a digit.
    v_prev := cmd.preview(v_fleet, 'SAIL TO 33,-15', v_course_pt);
    if v_prev->>'error_code' is distinct from 'E_ENDURANCE'
       or v_prev->'figures' is distinct from v_f
       or v_prev->>'error_message' is distinct from v_sentence then
      raise exception '0050 self-assert FAIL: preview and issue disagree about the same refusal — [%: % / %] vs [%: % / %]',
        v_prev->>'error_code', v_prev->>'error_message', v_prev->'figures',
        v_res->>'error_code', v_sentence, v_f;
    end if;

    -- (h) THE SEAM THAT DID NOT MOVE, measured as a DELTA. world.trade_routes asks sail_refusal
    --     as a silent predicate and never catches an exception, so the return-type change must be
    --     invisible to it — and it must still be ASKING: filling her casks has to open ports the
    --     thin larder closed.
    v_routes := world.trade_routes(v_lis, v_fleet, null, 3, null);
    if v_routes is null or not (v_routes ? 'basis') then
      raise exception '0050 self-assert FAIL: world.trade_routes no longer composes with the jsonb gate — got %', v_routes;
    end if;
    v_thin := (v_routes->'basis'->>'ports_considered')::int;
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    v_routes := world.trade_routes(v_lis, v_fleet, null, 3, null);
    v_fat := (v_routes->'basis'->>'ports_considered')::int;
    if v_fat <= v_thin then
      raise exception '0050 self-assert FAIL: the quay considered % port(s) on thin stores and % on full — the gate is not being asked', v_thin, v_fat;
    end if;

    -- (i) AN ARITHMETIC SIBLING, through the same door: BUY more than the hold will take. The
    --     figures must be the HOLD'S OWN, not a proxy for them.
    select g.code into v_good
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis
       and not ((select p.culture from public.ports p where p.id = v_lis) = any(g.culture_mask))
     order by g.code limit 1;
    select floor(public.fleet_free_hold(v_fleet) / g.bulk)::int into v_room
      from public.goods g where g.code = v_good;
    v_res := cmd.issue(v_fleet, 'BUY ' || v_good || ' ' || (v_room + 20)::int);
    v_f := v_res->'figures';
    v_hold_msg := v_res->>'error_message';
    if v_res->>'error_code' is distinct from 'E_HOLD_FULL' then
      raise exception '0050 self-assert FAIL: BUY % % on a % tun hold was not refused E_HOLD_FULL (got [%: %])',
        v_good, v_room + 20, v_room, v_res->>'error_code', v_hold_msg;
    end if;
    if v_f is null or v_f->>'unit' <> 't'
       or (v_f->>'have')::numeric <> v_room
       or (v_f->>'need')::numeric <> (v_room + 20) then
      raise exception '0050 self-assert FAIL: E_HOLD_FULL served figures that are not the hold''s own (% free, % asked) — got %',
        v_room, v_room + 20, v_f;
    end if;
    if v_hold_msg ~ '[0-9]' then
      raise exception '0050 self-assert FAIL: the E_HOLD_FULL sentence still carries a number: "%"', v_hold_msg;
    end if;
    perform cmd.clear(v_fleet, true);

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if (select count(*) from public.players where auth_uid = c_probe) <> 0 then
    raise exception '0050 self-assert FAIL: the probe house survived the subtransaction';
  end if;

  -- (j) THE POSTURE IS UNMOVED: five new leaves, none of them reachable by a client.
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn is null)
     or has_function_privilege('authenticated', 'cmd.refuse(text, text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'cmd.refusal_caught(text, text)', 'execute')
     or has_function_privilege('anon', 'cmd.figures(numeric, numeric, text)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.issue(uuid, text, int, jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.preview(uuid, text, jsonb)', 'execute') then
    raise exception '0050 self-assert FAIL: the posture moved — a grant, an entry point or the read wall';
  end if;

  raise notice '0050 self-assert ok: A REFUSAL IS TWO NUMBERS AND A VERB — cmd.figures writes the owner''s own shape and BIT on all four malformed argument sets; cmd.refuse and cmd.refusal_caught are inverses across a real RAISE, carrying {have,need,unit} through PG_EXCEPTION_DETAIL as DATA with nobody parsing prose on either side, and three DETAILs that are not figures were refused; the SIX hand-copied refusal splits are GONE and the eight-character truncation all six carried ("division by zero" -> "by zero") is fixed; a real house on thin stores was refused a pinpoint round trip E_ENDURANCE through cmd.issue with % / % days, whose HAVE is voyage.endurance_days itself rather than a second arithmetic, a sentence of % characters carrying no digit and no repeated verb ("%") and % fix(es) to press; the halted order in the served queue carries the same figures, and cmd.preview — which catches the raise where issue reads the order row — agreed with it exactly; the quay considered % ports on thin stores and % once her casks were full, so the gate it now reads as jsonb is still being asked; and an oversized BUY was refused E_HOLD_FULL with the hold''s own % free against % asked, in tuns, and no digit in its sentence either',
    v_end, v_need, length(v_sentence), v_sentence, v_fixes, v_thin, v_fat, v_room, v_room + 20;
end $$;

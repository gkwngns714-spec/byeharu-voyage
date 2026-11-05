// mini-world.mjs: a small PGlite world holding only what a fight reads: world_config with prod's fight knobs, the classes a fight names (prod's figures, read 2026-11-06), the knob readers,
// voyage.rng, public.armour_soak, and the old voyage.fight_resolve taken whole from proof 28. It stands in for a cached chain, which this machine does not keep past 0096, and it is not a world:
// CI's proof 28 runs on the real one. Nothing here touches prod.
import { readFileSync } from 'node:fs'
import { PGlite } from '@electric-sql/pglite'

const PROOF = 'scripts/db/proofs/28_fight_sides.sql'

export const CLASSES = [
  ['xebec', 'Şebek (xebec)', 60, 35, 2, 530, 38, 26, 12, 11], ['nau', 'Nau / Carrack', 120, 60, 3, 1800, 55, 70, 30, 14],
  ['navire', 'Navire marchand', 130, 60, 3, 1800, 59, 70, 30, 15], ['galion', 'Galion', 250, 130, 4, 2800, 64, 78, 40, 15],
]

export function preImage() {
  const t = readFileSync(PROOF, 'utf8')
  return t.slice(t.indexOf('$pre$') + 5, t.lastIndexOf('$pre$'))
}

export async function miniWorld() {
  const db = await PGlite.create()
  await db.exec(`
    create role anon; create role authenticated;
    create schema voyage; create schema world; create schema cmd;
    create table public.world_config (key text primary key, value jsonb not null, description text, updated_at timestamptz not null default now());
    insert into public.world_config (key, value) values
      ('armour_turns_pct','0.5'),('combat_bite','true'),('fight_board_bands','[1.2,0.7,0.3]'),('fight_damage_per_attack','0.7'),('fight_evade_max','0.3'),
      ('fight_evade_per_sighting','0.03'),('fight_hand_value','0.15'),('fight_raider_break','0.15'),('fight_raider_class','"xebec"'),
      ('fight_ranges','[["LONG",0.6],["LONG",0.6],["LONG",0.6],["MEDIUM",0.8],["MEDIUM",0.8],["CLOSE",1]]'),('fight_standoff_ratio','2'),('world_secret','"harness"');
    create table public.ship_classes (id uuid primary key default gen_random_uuid(), code text unique, name text, attack int, crew_required int, tier int, durability int, accuracy int, reach int, armour int, sighting int);
    create function public.wc(p_key text) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
      declare v jsonb; begin select value into v from public.world_config where key = p_key; if v is null then raise exception 'world_config key % does not exist', p_key; end if; return v; end $$;
    create function public.wc_num(p_key text) returns numeric language sql stable begin atomic select (public.wc(p_key))::text::numeric; end;
    create function public.wc_text(p_key text) returns text language sql stable security definer set search_path = public, pg_temp as $$ select (public.wc(p_key)) #>> '{}' $$;
    create function voyage.rng_raw(p_voyage uuid, p_day int, p_stream text, p_secret text) returns numeric language sql immutable parallel safe as $$
      select (('x' || substr(md5(p_voyage::text || ':' || p_day::text || ':' || p_stream || ':' || p_secret), 1, 15))::bit(60)::bigint)::numeric / 1152921504606846976::numeric $$;
    create function voyage.rng(p_voyage uuid, p_day int, p_stream text default 'hazard') returns numeric language sql stable security definer set search_path = public, pg_temp as
      $$ select voyage.rng_raw(p_voyage, p_day, p_stream, public.wc_text('world_secret')) $$;
    create function public.armour_soak(p_armour numeric, p_loss numeric) returns numeric language plpgsql stable security definer set search_path = public, pg_temp as $$
      declare v_k numeric := public.wc_num('armour_turns_pct');
      begin if v_k <= 0 then return p_loss; end if; return round(p_loss * greatest(0, 1 - coalesce(p_armour, 0) / 100.0 * v_k), 2); end $$;
  `)
  for (const c of CLASSES) {
    await db.query('insert into public.ship_classes (code, name, attack, crew_required, tier, durability, accuracy, reach, armour, sighting) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)', c)
  }
  await db.exec(preImage())
  await db.exec(`revoke all on function voyage.fight_resolve(uuid, int, numeric, numeric, jsonb) from public, anon, authenticated;`)
  return db
}

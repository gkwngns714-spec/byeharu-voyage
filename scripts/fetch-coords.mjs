// Resolve every roster entry to a Wikidata item and pull its coordinate (P625)
// and country (P17 -> P297 ISO 3166-1 alpha-2). Writes scripts/coords.cache.json.
//
// Source: Wikidata (https://www.wikidata.org), CC0 1.0 Universal public domain dedication.
// Run: node scripts/fetch-coords.mjs
//
// A roster entry may pin its item with `qid:` when the enwiki title is ambiguous.
// Entries whose enwiki title resolves to a disambiguation page are reported, not guessed at.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import europe from './roster/europe.mjs';
import afrIo from './roster/africa-indian-ocean.mjs';
import easia from './roster/east-asia.mjs';
import americas from './roster/americas.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CACHE = join(HERE, 'coords.cache.json');
export const roster = [...europe, ...afrIo, ...easia, ...americas];

const API = 'https://www.wikidata.org/w/api.php';
const UA = 'byeharu-voyage-dataset/0.1 (one-off game dataset build)';
const DISAMBIG = 'Q4167410';
const sleep = ms => new Promise(r => setTimeout(r, ms));

const ATTEMPTS = 7;
const backoff = n => Math.min(60_000, 4_000 * 2 ** n);   // 4s, 8s, 16s, 32s, 60s, 60s

async function api(params, { optional = false } = {}) {
  const url = `${API}?${new URLSearchParams({ format: 'json', formatversion: '2', ...params })}`;
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json', Connection: 'close' } });
      if (res.ok) return res.json();
      if (res.status === 429 || res.status >= 500) {
        process.stderr.write(`HTTP ${res.status}, backing off ${backoff(attempt) / 1000}s\n`);
        await sleep(backoff(attempt));
        continue;
      }
      throw new Error(`HTTP ${res.status} for ${url}`);
    } catch (err) {
      // transient socket drops and truncated bodies are common on long batch runs
      if (attempt === ATTEMPTS - 1) break;
      process.stderr.write(`retrying after ${err.cause?.code ?? err.name}: ${err.message}\n`);
      await sleep(backoff(attempt));
    }
  }
  if (optional) return null;
  throw new Error(`gave up on ${url}`);
}

const chunk = (a, n) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
const BATCH = 25;   // small batches: long keep-alive runs against the API drop sockets mid-body

const isoCache = new Map();

function readEntity(ent) {
  const coord = ent.claims?.P625?.find(c => c.rank !== 'deprecated')?.mainsnak?.datavalue?.value ?? null;
  const isDisambig = (ent.claims?.P31 ?? []).some(c => c.mainsnak?.datavalue?.value?.id === DISAMBIG);
  const p17 = ent.claims?.P17 ?? [];
  const cQid = p17.find(c => c.rank === 'preferred')?.mainsnak?.datavalue?.value?.id
    ?? p17.filter(c => c.rank !== 'deprecated').at(-1)?.mainsnak?.datavalue?.value?.id
    ?? p17[0]?.mainsnak?.datavalue?.value?.id ?? null;
  return { coord, isDisambig, cQid };
}

const out = {};
const problems = [];

async function ingest(port, ent) {
  if (!ent || ent.missing !== undefined || !ent.id) {
    problems.push({ id: port.id, wiki: port.wiki, problem: 'no wikidata item' });
    return null;
  }
  const { coord, isDisambig, cQid } = readEntity(ent);
  if (isDisambig) { problems.push({ id: port.id, wiki: port.wiki, qid: ent.id, problem: 'resolves to a disambiguation page — pin a qid' }); return null; }
  if (!coord) { problems.push({ id: port.id, wiki: port.wiki, qid: ent.id, problem: 'no P625 coordinate' }); return null; }
  out[port.id] = {
    qid: ent.id,
    wikiResolved: ent.sitelinks?.enwiki?.title ?? port.wiki,
    label: ent.labels?.en?.value ?? null,
    lat: coord.latitude,
    lon: coord.longitude,
    precision: coord.precision ?? null,
    countryQid: cQid,
  };
  return cQid;
}

const PROPS = 'claims|labels|sitelinks';
const countryQids = new Set();

// --- pass 1: entries pinned to a QID ---
const pinned = roster.filter(p => p.qid);
for (const batch of chunk(pinned, BATCH)) {
  const j = await api({ action: 'wbgetentities', ids: batch.map(p => p.qid).join('|'), props: PROPS, languages: 'en', sitefilter: 'enwiki' });
  for (const p of batch) {
    const c = await ingest(p, j.entities?.[p.qid]);
    if (c) countryQids.add(c);
  }
  await sleep(400);
}

// --- pass 2: entries resolved through their enwiki title ---
const byTitleRoster = roster.filter(p => !p.qid);
for (const batch of chunk(byTitleRoster, BATCH)) {
  const j = await api({ action: 'wbgetentities', sites: 'enwiki', titles: batch.map(p => p.wiki).join('|'), props: PROPS, languages: 'en', sitefilter: 'enwiki' });
  const norm = new Map((j.normalized ?? []).map(n => [n.from, n.to]));
  const byTitle = new Map();
  for (const ent of Object.values(j.entities ?? {})) {
    const t = ent.sitelinks?.enwiki?.title;
    if (t) byTitle.set(t, ent);
  }
  for (const p of batch) {
    const ent = byTitle.get(norm.get(p.wiki) ?? p.wiki) ?? byTitle.get(p.wiki);
    const c = await ingest(p, ent);
    if (c) countryQids.add(c);
  }
  process.stderr.write(`resolved ${Object.keys(out).length}/${roster.length}\n`);
  await sleep(400);
}

// --- country QID -> ISO 3166-1 alpha-2 ---
// Country items carry thousands of statements each; asking wbgetentities for their full
// claims pulls megabytes per item and drops the socket. Take the labels in one cheap batch
// and the single P297 claim one item at a time through wbgetclaims, which returns a few
// hundred bytes.
for (const batch of chunk([...countryQids], BATCH)) {
  const j = await api({ action: 'wbgetentities', ids: batch.join('|'), props: 'labels', languages: 'en' });
  for (const [qid, ent] of Object.entries(j.entities ?? {})) {
    isoCache.set(qid, { iso: null, label: ent.labels?.en?.value ?? null });
  }
  await sleep(250);
}
let isoUnresolved = 0;
for (const qid of countryQids) {
  // `optional` — this is a QA cross-check, not data. If the API will not answer, report the
  // gap rather than failing the run or silently implying the codes agree.
  const j = await api({ action: 'wbgetclaims', entity: qid, property: 'P297' }, { optional: true });
  if (j === null) { isoUnresolved++; continue; }
  const claims = j.claims?.P297 ?? [];
  // Prefer a live statement, but fall back to a deprecated one rather than reporting no code
  // at all. Wikidata deprecates P297 = NL on Q55 (Netherlands) because the code formally
  // belongs to the Kingdom of the Netherlands; the code is still the right answer here.
  const pick = claims.find(c => c.rank === 'preferred') ?? claims.find(c => c.rank === 'normal') ?? claims[0];
  isoCache.set(qid, {
    iso: pick?.mainsnak?.datavalue?.value ?? null,
    isoRank: pick?.rank ?? null,
    label: isoCache.get(qid)?.label ?? null,
  });
  await sleep(150);
}
process.stderr.write(`ISO cross-check: ${countryQids.size - isoUnresolved}/${countryQids.size} country items resolved\n`);
if (isoUnresolved) console.log(`\nWARNING: ${isoUnresolved} country items could not be re-checked (API unavailable); their ports are omitted from the cross-check below.`);

for (const rec of Object.values(out)) {
  const c = rec.countryQid ? isoCache.get(rec.countryQid) : null;
  rec.wikidataCountryIso = c?.iso ?? null;
  rec.wikidataCountryLabel = c?.label ?? null;
}

writeFileSync(CACHE, JSON.stringify({
  fetchedAt: new Date().toISOString(),
  source: 'Wikidata wbgetentities API; coordinate property P625, country property P17 -> P297',
  licence: 'CC0 1.0 Universal (Wikidata data)',
  count: Object.keys(out).length,
  entries: out,
}, null, 2) + '\n');

console.log(`\nwrote ${CACHE}`);
console.log(`resolved ${Object.keys(out).length} of ${roster.length}`);
if (problems.length) {
  console.log(`\nPROBLEMS (${problems.length}):`);
  for (const p of problems) console.log('  ', JSON.stringify(p));
} else {
  console.log('PROBLEMS: none — every roster entry resolved to a Wikidata coordinate.');
}

const mismatches = [];
for (const p of roster) {
  const r = out[p.id];
  if (!r) continue;
  if (r.wikidataCountryIso !== p.country) {
    mismatches.push(`  ${p.id.padEnd(24)} roster=${p.country}  wikidata=${r.wikidataCountryIso ?? '<none>'} (${r.wikidataCountryLabel ?? r.countryQid})`);
  }
}
if (mismatches.length) {
  console.log(`\nCOUNTRY CROSS-CHECK — ${mismatches.length} disagree with Wikidata's P17 and need an editorial decision:`);
  console.log(mismatches.join('\n'));
} else {
  console.log('\nCOUNTRY CROSS-CHECK — all roster ISO codes agree with Wikidata.');
}

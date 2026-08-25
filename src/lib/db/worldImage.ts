// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PRE-BUILT WORLD — where the image lives, and how the browser asks for it
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ── THE DEFECT THIS CLOSES (docs/RESUME.md:125, docs/DEV_LOG.md:177) ────────────────────────────
// "Cold boot 78.8 s measured with 243 goods. The world builds in the player's tab." Every first
// visit replayed 45 migrations — deriving 52,002 price rows, re-measuring the sea — to arrive at
// a world that is a pure function of the repository and is therefore the SAME world every time.
// That work belongs to the build, once, not to every player.
//
// ── THE FILE NAME IS HALF THE SAFETY ────────────────────────────────────────────────────────────
// The image is served at `db/world-<fingerprint>.tar.gz`, and the fingerprint in that name is
// `fingerprintChain(files)` over the chain the app SHIPPED with — computed at run time by the
// client, not read from anywhere. So a client can only ever ask for the image of its own chain:
// if the chain moved and the image did not, the fetch is a 404 and the boot applies the chain, as
// it always did. There is no code path in which a client downloads an image built from a chain it
// does not carry.
//
// That is the CHEAP half. The authoritative half is `imageRefusal()` in appLocal.ts, which reads
// the fingerprint written INSIDE the image and refuses it out loud if it disagrees. Both must
// pass. Two independent locks, because DEV_LOG D23's divergence "stayed green" through every
// check the project had at the time.
//
// ── NO SECOND COPY ON DISK ──────────────────────────────────────────────────────────────────────
// The image is never committed. scripts/db/build-image.mjs generates it during `npm run build`
// from the chain in the repository at that moment, keyed by fingerprint, and vite.config.ts emits
// it into dist/. A human cannot forget to regenerate it, because nothing is stored under a name
// that outlives the chain it was built from.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The directory, under the site base, the image is served from. Shared with the build script. */
export const WORLD_IMAGE_DIR = 'db'

/** `world-<fingerprint>.tar.gz`. The ONE naming rule; the builder and the client both call it. */
export function worldImageFileName(fingerprint: string): string {
  return `world-${fingerprint}.tar.gz`
}

/** Where this build's image would be served from, given the site base (`import.meta.env.BASE_URL`). */
export function worldImageUrl(fingerprint: string, base: string): string {
  const root = base.endsWith('/') ? base : `${base}/`
  return `${root}${WORLD_IMAGE_DIR}/${worldImageFileName(fingerprint)}`
}

/** What a fetch attempt reports back, so the boot log can say WHY it is applying the chain. */
export interface WorldImageFetch {
  blob: Blob | null
  url: string
  /** Present when there is no usable image: the sentence to log. Never thrown. */
  note: string | null
  /** Bytes downloaded, when there was an image. */
  bytes: number
}

/** gzip's magic number. PGlite decides whether to inflate from the FILE'S NAME AND TYPE, not from
 *  the bytes, so this is sniffed here and the name is set to match what actually arrived. A proxy
 *  that inflates the body itself (Content-Encoding: gzip on a .gz file) would otherwise hand
 *  PGlite a plain tar wearing a .tar.gz name, and the inflate it then attempts throws. */
function isGzip(bytes: Uint8Array): boolean {
  return bytes.length > 2 && bytes[0] === 0x1f && bytes[1] === 0x8b
}

/** Wrap downloaded bytes as the File PGlite's `loadDataDir` expects, named for what they ARE. */
export function asWorldImageFile(bytes: Uint8Array): File {
  return isGzip(bytes)
    ? new File([bytes as BlobPart], 'world.tar.gz', { type: 'application/gzip' })
    : new File([bytes as BlobPart], 'world.tar', { type: 'application/x-tar' })
}

/**
 * Ask for this build's image. NEVER THROWS — the chain apply is the fallback for every failure
 * mode here (no image emitted, offline, a proxy serving HTML for a 404, a truncated body), and a
 * boot that dies because an OPTIMISATION was unavailable would be a worse bug than the slow boot.
 */
export async function fetchWorldImage(fingerprint: string, base: string): Promise<WorldImageFetch> {
  const url = worldImageUrl(fingerprint, base)
  try {
    const res = await fetch(url, { cache: 'force-cache' })
    if (!res.ok) {
      return {
        blob: null,
        url,
        bytes: 0,
        note: `no pre-built world at ${url} (${res.status}) — this build shipped without one`,
      }
    }
    // A MISSING IMAGE DOES NOT ALWAYS ARRIVE AS A 404. A single-page-app fallback — `vite preview`
    // does exactly this, and so does every static host configured to serve index.html for unknown
    // paths — answers 200 with a PAGE. Without this check the boot hands PGlite an HTML document
    // and reports "the compressed data was not valid", which is a true sentence about the wrong
    // thing. (Seen 2026-08-25, measuring the fallback path.)
    const type = res.headers.get('Content-Type') ?? ''
    if (type.includes('text/html')) {
      return {
        blob: null,
        url,
        bytes: 0,
        note: `no pre-built world at ${url} — the server answered with a page, not an image`,
      }
    }
    const bytes = new Uint8Array(await res.arrayBuffer())
    if (bytes.length === 0) {
      return { blob: null, url, bytes: 0, note: `the pre-built world at ${url} is empty` }
    }
    return { blob: asWorldImageFile(bytes), url, bytes: bytes.length, note: null }
  } catch (err) {
    return {
      blob: null,
      url,
      bytes: 0,
      note: `the pre-built world at ${url} could not be fetched (${
        err instanceof Error ? err.message : String(err)
      })`,
    }
  }
}

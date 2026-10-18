/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string
  readonly VITE_SUPABASE_ANON_KEY: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

/** The id of THIS build — `<7-char commit>+<ISO build time>` — substituted at build time by
 *  vite.config.ts's `byeharu:build-version` plugin (`define`). The same value is written to
 *  `version.json` beside index.html; src/lib/version.ts is the only reader of either. */
declare const __BUILD_ID__: string

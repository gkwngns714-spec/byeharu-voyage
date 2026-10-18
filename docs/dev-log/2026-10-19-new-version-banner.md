# 2026-10-19 — a stale tab learns a newer build is live — `osn-new-version-banner` (client only, no migration)

**Why.** The owner kept a tab open across deploys, so he was playing an old build and reported a
defect that had already been fixed. Nothing in the app knew which build it was, so nothing could
tell him. He should always know when a newer version is live.

**The concept and where it lives** (docs/NO_SPAGHETTI.md §7B, planned before the code):

| piece | file | why there |
|---|---|---|
| the build id, stamped once per build | `vite.config.ts` — `byeharu:build-version` | the build is the only place that knows the commit and the moment; one value goes to both the bundle (`define` → `__BUILD_ID__`) and `dist/version.json`, so they cannot disagree |
| the running id and the published id | `src/lib/version.ts` | a leaf: reads a constant and one 60-byte file, nothing from the world; a second reader (a build line on Profile) takes `BUILD_ID` from here |
| the sentence | `src/app/NewVersionToast.tsx` | mounted in `App.tsx` over every route, outside `RequireAuth` and the shell, because a stale tab is stale on the sign-in page too |
| the words | `docs/WORDS.md` row; `docs/UI_DIRECTION.md` §6 Shell | the vocabulary law and the one toast the shell is allowed |

**The id.** `<7-char commit>+<ISO build time>`, e.g. `db7c956+2026-10-19T02:14:09.512Z`. The commit
is `GITHUB_SHA` on a runner, `git rev-parse HEAD` on a dev machine; neither available throws rather
than stamping `unknown` (§7C: a build that cannot be named cannot be told apart from the next one).

**The check.** Every 5 minutes, on `focus`, and on `visibilitychange` to visible — not on mount (a
tab that just loaded is the published build; a mount check would only catch a CDN edge still
handing out the previous index.html, which a reload cannot fix). Focus and visibilitychange fire
together on a tab switch; one in-flight question at a time.

**Beating GitHub Pages' cache.** Pages serves everything with `max-age=600`. The fetch uses
`cache: 'no-store'` (the browser's cache stays out of it) AND `?t=<now>` (every check is a URL the
CDN edge has never seen, so it goes to origin). One without the other serves a ten-minute-old
answer — the very stale tab this exists to end.

**On screen.** UI_DIRECTION §4.3's floating corner glass, `fixed right-3 top-10 z-60`, one line of
`t-label` — *New version — tap to refresh* — the whole glass a button, plus a 44-px ✕ (**Dismiss**).
Fixed, so it is outside the flow and moves nothing on the page. Tapping reloads. Dismiss keeps the
dismissed id in `sessionStorage`, so a reload does not bring it back and a newer build after that
does. A failed check (offline, a 404 mid-deploy, a body that is not the file) shows nothing,
throws nothing, and writes one `console.debug` line.

**Proof — `tests/version.banner.spec.ts`** (on `/ui`, outside the world, so it pays no chain and
does not skip on a cloud build; the toast is mounted over every route, so what is proven there holds
on every tab):

1. the served build publishes `version.json` in the stamped shape, and a tab running that build,
   asked to check, shows nothing;
2. each focus asks once, with a fresh `?t=` every time;
3. with `version.json` swapped to B (a route), focus brings the banner: `position: fixed`, within
   16 px of the right edge and 48 px of the top, ≥ 44 px tall, and the first forty gallery boxes
   have the same geometry before and after (nothing reflowed); a tap on it reloads (a marker set on
   the old document is gone);
4. ✕ dismisses it; asked again, still gone; reloaded, still gone; a third id brings it back;
5. offline, a 404 and an HTML body each show nothing and leave the console and the page without an
   error;
6. at 1440×731, `visibilitychange` brings it too; screenshots at DPR 2 at both widths are in
   `docs/dev-log/2026-10-19-new-version-banner/`.

**CI selection.** The spec is picked by rule C when it changes, rule A for anything under
`src/app/**`, rule I through `data-testid="new-version"` when the toast changes, and rule N through
the quoted `version.ts` when the leaf changes. `vite.config.ts` is rule F (full suite) and chain
machinery for the growth rule, as before. Weight 10 s in `tests/shard-weights.json`.

**Not done.** No build id is printed anywhere a player reads (WORDS: nothing but the sentence).
The Profile screen could show it under a *Build* row for bug reports; that is one line reading
`BUILD_ID` from `src/lib/version.ts` when the owner wants it.

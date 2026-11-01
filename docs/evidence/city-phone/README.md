# Evidence for the HQ-on-a-phone slice (2026-11-02) — screenshots only, never to be merged

Headless Chromium, English, the canary world, 390x844 and 320x640. `before-*` is `main` before the slice; `after-*` is `main` after #456-#462 (and #464).
`after-parked-*` is what the PARKED branch `city-phone-pane` does (the HQ Market's trade pane and the Inn's guest tray) — it is NOT on main.

| state | files |
|---|---|
| HQ Market, Warehouse (storage), Inn | `*-{390,320}-{market,warehouse,inn}.png` |
| the desk's City board, its Requests | `*-{390,320}-{desk-city,requests}.png` |
| Profile | `*-{390,320}-profile.png` |
| the HQ with no city in hand | `*-{390,320}-no-city.png` |
| the Requests face's open request (Cancel past the panel's edge, then inside it) | `after-{390,320,1280}-open-request-cancel.png` |
| the trade pane (Buy / Bargain open / Sell) and the Inn's guest tray — before, and after on the parked branch | `before-*` / `after-parked-*` `-trade-pane-*` and `-inn-guest-tray` |

Dev-logs: `docs/dev-log/2026-11-02-city-phone*.md`. Delete this branch when the redesign supersedes the slice.

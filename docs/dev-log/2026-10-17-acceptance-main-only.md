# 2026-10-17 — acceptance runs on main only

Owner: "always make CI fast". Required checks are build + disposable-chain; acceptance no longer runs on pull requests (it held runners the required checks queued behind). Main runs the full suite after each merge as the net. Manual run: workflow_dispatch.

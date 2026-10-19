#!/bin/bash
# Commit and push docs/WORK_QUEUE.md to main so another computer sees the live list. [skip ci]: docs only, no CI or Pages run.
cd ~/dev/byeharu-voyage || exit 1
git diff --quiet -- docs/WORK_QUEUE.md && exit 0
git pull -q --rebase --autostash origin main && git add docs/WORK_QUEUE.md && git commit -qm "docs: work queue $(date -u +%H:%M) UTC [skip ci]" && git push -q origin main && echo "queue pushed"

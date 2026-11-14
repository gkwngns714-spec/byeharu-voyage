#!/usr/bin/env bash
# bv-deploy.sh <pr> -- deploy a migration PR to prod; merge ONLY if the push landed.
# The deploy copy is origin/main + the PR's migration files that main lacks (a PR behind main still deploys cleanly).
# THE GATES (docs/DATABASE_BUDGET.md, 2026-11-15). Before the clock is stopped it REFUSES, nothing pushed, when the PR's `build` check
# (it runs tests/db.budget.spec.ts) is not green, or when ONE read of scripts/ops/harness/db-health/gate.sql says the beat is slow
# (mean over 2 s), the database is over its 1,500 MB ceiling, or more than 5 sessions wait on the disk. The override is never silent:
#   BV_DEPLOY_FORCE=1 BV_DEPLOY_REASON="why" ~/bin/bv-deploy.sh <pr>     (the reason goes into the push log)
# After the push and the wind it prints the same read ONCE: the after-check. No loops.
set -u
mkdir -p ~/bv-push-logs  # push logs live outside the repo
PR=$1; cd ~/dev/byeharu-voyage && git fetch -q || exit 1
M=supabase/migrations; H=$(gh pr view $PR --json headRefOid --jq .headRefOid)
new=$(git diff --name-only --diff-filter=AM origin/main...$H -- $M | grep '/2026[0-9]*_.*\.sql$')
[ -z "$new" ] && { echo "PR adds no migration"; exit 1; }
want=$(echo "$new" | grep -o '2026[0-9]*' | sort | tail -1)
git worktree remove --force ~/dev/bv-deploy 2>/dev/null
git worktree add -q --detach ~/dev/bv-deploy origin/main || exit 1
cd ~/dev/bv-deploy && for f in $new; do git show $H:$f > $f; done && cp -r ~/dev/byeharu-voyage/supabase/.temp supabase/
# a migration already LIVE on prod but not yet on main (its PR still merging) must be present locally, or db push refuses
for v in $(npx --yes supabase@2.120.0 db query --linked "select version from supabase_migrations.schema_migrations where version > '20260818000100'" 2>&1 | grep -o '"version": "[0-9]*"' | grep -o '[0-9]*'); do
  ls $M/${v}_*.sql >/dev/null 2>&1 && continue
  for b in $(git -C ~/dev/byeharu-voyage branch -r --format='%(refname:short)'); do f=$(git -C ~/dev/byeharu-voyage ls-tree -r --name-only $b $M | grep "/${v}_" | head -1); [ -n "$f" ] && { git -C ~/dev/byeharu-voyage show $b:$f > $f; echo "added live $v from $b"; break; }; done
done
echo "deploying: $(echo $new | tr ' ' '\n' | xargs -n1 basename | tr '\n' ' ')"
Q(){ npx --yes supabase@2.120.0 db query --linked "$1" 2>&1; }
# ── THE GATE (docs/DATABASE_BUDGET.md): before anything is stopped or pushed ──
LOG=~/bv-push-logs/push-$want.log; : > $LOG
force=${BV_DEPLOY_FORCE:-0}; reason=${BV_DEPLOY_REASON:-}
bail(){ cd ~/dev/byeharu-voyage && git worktree remove --force ~/dev/bv-deploy; exit 4; }
[ "$force" = 1 ] && [ -z "$reason" ] && { echo 'REFUSED: BV_DEPLOY_FORCE=1 needs BV_DEPLOY_REASON="why"'; bail; }
G=~/dev/bv-deploy/scripts/ops/harness/db-health/gate.sql
node "$HOME/dev/bv-deploy/scripts/ops/harness/db-health/../read-only.mjs" "$G" || exit 3   # the one judge of "read only"
gate(){ npx --yes supabase@2.120.0 db query --linked --output-format json -f "$(cygpath -w "$G" 2>/dev/null || echo "$G")" 2>&1; }
gline(){ echo "$1" | grep -o '"gate_line": *"[^"]*"' | sed 's/.*: *"//; s/"$//'; }
red=""
b=$(gh pr view $PR --json statusCheckRollup --jq '[.statusCheckRollup[]|select(.name=="build")|.conclusion][0]')
[ "$b" = SUCCESS ] || red="the PR's build check is ${b:-missing} (it runs the budget spec tests/db.budget.spec.ts)"
g=$(gate); echo "$g" > ~/bv-push-logs/gate-$want.log
echo "GATE before: $(gline "$g")"
if ! echo "$g" | grep -q '"gate_ok": *true'; then
  why=$(echo "$g" | grep -o '"gate_why": *"[^"]*"' | sed 's/.*: *"//; s/"$//')
  red="${red:+$red; }the database gate is red: ${why:-its read failed: $(echo "$g" | tail -2 | cut -c1-200)}"
fi
if [ -n "$red" ]; then
  if [ "$force" = 1 ]; then echo "FORCED past a red gate (BV_DEPLOY_FORCE=1): $red. Reason: $reason" | tee -a $LOG
  else echo "REFUSED, nothing pushed, the clock untouched: $red. Wait for it to clear (docs/DATABASE_BUDGET.md), or BV_DEPLOY_FORCE=1 BV_DEPLOY_REASON=\"why\"."; bail; fi
fi
echo "gate before: $(gline "$g")" >> $LOG
Q "select public.unwind_the_clock()" >/dev/null
for i in $(seq 1 30); do r=$(Q "select count(*) n from cron.job_run_details where status in ('running','starting')" | grep -o '"n": [0-9]*' | grep -o '[0-9]*$'); [ "$r" = 0 ] && break; sleep 10; done
echo Y | npx --yes supabase@2.120.0 db push --linked >> $LOG 2>&1; rc=$?
grep -viE "^\s*$|new version|recommend updating|Skipping migration|Initialising|^gate before|^FORCED" $LOG | tail -3 | cut -c1-400
head=$(Q "select max(version) head from supabase_migrations.schema_migrations" | grep -o '"head": "[0-9]*"' | grep -o '[0-9]*')
Q "select public.wind_the_clock()" >/dev/null
echo "push_rc=$rc head=$head want=$want jobs=$(Q "select count(*) filter (where active) n from cron.job where jobname like 'byeharu-voyage:%'" | grep -o '"n": [0-9]*' | grep -o '[0-9]*$')"
g=$(gate); echo "GATE after (the one after-check): $(gline "$g") ok=$(echo "$g" | grep -o '"gate_ok": *[a-z]*' | grep -o '[a-z]*$')"
echo "gate after: $(gline "$g")" >> $LOG
cd ~/dev/byeharu-voyage && git worktree remove --force ~/dev/bv-deploy
if [ "$rc" = 0 ] && [ "$head" = "$want" ]; then gh pr merge $PR --squash 2>&1 | tail -1; gh pr merge $PR --squash --auto >/dev/null 2>&1; sleep 5; gh pr view $PR --json state --jq '"merged: "+.state'; else echo "NOT MERGING: push failed or head != $want"; exit 2; fi
# AFTER THE MERGE, MAIN'S OWN NET (2026-10-25: 0218 merged green on its scoped PR run and turned main red on
# desk.plan; the PR run is not main's full suite). Wait for main's Acceptance on the merge commit and say it.
sha=$(gh pr view $PR --json mergeCommit --jq .mergeCommit.oid 2>/dev/null)
if [ -n "$sha" ]; then
  for i in $(seq 1 20); do id=$(gh run list --workflow acceptance.yml --branch main --limit 8 --json databaseId,headSha --jq ".[]|select(.headSha==\"$sha\")|.databaseId" | head -1); [ -n "$id" ] && break
    # 2026-11-02: THIS MERGE FIRES NO PUSH WORKFLOW (gh's own token), so nothing would ever appear here and a migration PR's client would stay unpublished
    # (0294's class meter did, until it was started by hand). After ~30 s with no run for the merge commit, start BOTH on main once.
    if [ "$i" = 3 ]; then gh workflow run deploy-pages.yml --ref main >/dev/null 2>&1; gh workflow run acceptance.yml --ref main >/dev/null 2>&1; echo "no workflow fired for ${sha:0:7}: dispatched deploy-pages.yml and acceptance.yml on main"; fi
    sleep 15; done
  if [ -n "$id" ]; then gh run watch $id --exit-status >/dev/null 2>&1; echo "MAIN ACCEPTANCE on ${sha:0:7}: $(gh run view $id --json conclusion --jq .conclusion) $(gh run view $id --json jobs --jq '.jobs[]|select(.conclusion=="failure")|.name' | tr '\n' ';')"; else echo "MAIN ACCEPTANCE on ${sha:0:7}: no run found — CHECK BY HAND"; fi
fi

#!/usr/bin/env bash
# bv-deploy.sh <pr> -- deploy a migration PR to prod; merge ONLY if the push landed.
# The deploy copy is origin/main + the PR's migration files that main lacks (a PR behind main still deploys cleanly).
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
Q "select public.unwind_the_clock()" >/dev/null
for i in $(seq 1 30); do r=$(Q "select count(*) n from cron.job_run_details where status in ('running','starting')" | grep -o '"n": [0-9]*' | grep -o '[0-9]*$'); [ "$r" = 0 ] && break; sleep 10; done
echo Y | npx --yes supabase@2.120.0 db push --linked > ~/bv-push-logs/push-$want.log 2>&1; rc=$?
grep -viE "^\s*$|new version|recommend updating|Skipping migration|Initialising" ~/bv-push-logs/push-$want.log | tail -3 | cut -c1-400
head=$(Q "select max(version) head from supabase_migrations.schema_migrations" | grep -o '"head": "[0-9]*"' | grep -o '[0-9]*')
Q "select public.wind_the_clock()" >/dev/null
echo "push_rc=$rc head=$head want=$want jobs=$(Q "select count(*) filter (where active) n from cron.job where jobname like 'byeharu-voyage:%'" | grep -o '"n": [0-9]*' | grep -o '[0-9]*$')"
cd ~/dev/byeharu-voyage && git worktree remove --force ~/dev/bv-deploy
if [ "$rc" = 0 ] && [ "$head" = "$want" ]; then gh pr merge $PR --squash 2>&1 | tail -1; gh pr merge $PR --squash --auto >/dev/null 2>&1; sleep 5; gh pr view $PR --json state --jq '"merged: "+.state'; else echo "NOT MERGING: push failed or head != $want"; exit 2; fi

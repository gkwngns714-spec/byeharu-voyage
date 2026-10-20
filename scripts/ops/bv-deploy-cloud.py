#!/usr/bin/env python3
"""bv-deploy-cloud.py <pr> -- deploy a migration PR to prod from a cloud session.

The cloud counterpart to bv-deploy.sh. Same gates, different transport: a cloud
container cannot open a Postgres connection (libpq does not speak the agent's
HTTP proxy), so the SQL goes through the Supabase Management API instead of
`supabase db push`. The proxy supplies the credential.

It keeps every gate the shell script has:
  unwind the clock -> wait for the cron jobs to drain -> apply the migration and
  record its version in ONE transaction -> read the head -> wind the clock back
  -> merge the PR ONLY if the head is the version we meant to push.

On any doubt it stops and says so. It never guesses whether a push landed: the
head is read back from the database, so a dropped HTTP call is still decidable.

Usage:  python3 -I scripts/ops/bv-deploy-cloud.py <pr> [--dry-run]
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPO = "gkwngns714-spec/byeharu-voyage"
REF = "olaquvizoavjeiricyxk"
API = f"https://api.supabase.com/v1/projects/{REF}/database/query"
MIGRATIONS = "supabase/migrations"


# ── the database ────────────────────────────────────────────────────────────

def sql(query: str, timeout: int = 900):
    """Run SQL on prod. Returns parsed rows, or raises."""
    body = json.dumps({"query": query}).encode()
    req = urllib.request.Request(
        API, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def read(query: str):
    """A read-only query, wrapped so it cannot write."""
    return sql("begin transaction read only;\n" + query + "\nrollback;", timeout=120)


def head() -> str | None:
    rows = read("select max(version) as head from supabase_migrations.schema_migrations;")
    return rows[0]["head"] if rows else None


def clock() -> tuple[int, int]:
    """(active, defined). Every job the chain defines should be active after a wind.

    The total is read, never assumed: a migration may add a job of its own, and
    since 0078 every job lands INACTIVE and wind_the_clock() is what lights it.
    So the number grows legitimately — what must hold is active == defined.
    """
    rows = read(
        "select count(*) filter (where active) as active, count(*) as defined"
        " from cron.job where jobname like 'byeharu-voyage:%';"
    )
    return int(rows[0]["active"]), int(rows[0]["defined"])


def busy_jobs() -> int:
    rows = read(
        "select count(*) as n from cron.job_run_details"
        " where status in ('running','starting');"
    )
    return int(rows[0]["n"])


# ── git / github ────────────────────────────────────────────────────────────

def run(*args: str) -> str:
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        die(f"command failed: {' '.join(args)}\n{p.stderr.strip()}")
    return p.stdout.strip()


def die(msg: str) -> None:
    print(f"\nSTOPPING: {msg}")
    sys.exit(2)


def pr_head(pr: str) -> str:
    return json.loads(run("gh", "api", f"repos/{REPO}/pulls/{pr}"))["head"]["sha"]


def migration_of(pr: str, sha: str) -> tuple[str, str, str]:
    """The one migration this PR adds that main lacks: (path, version, name)."""
    run("git", "fetch", "-q", "--depth=1", "origin", "main")
    files = json.loads(run("gh", "api", f"repos/{REPO}/pulls/{pr}/files?per_page=100"))
    added = [
        f["filename"]
        for f in files
        if f["status"] in ("added", "modified")
        and re.match(rf"^{MIGRATIONS}/2026\d+_.*\.sql$", f["filename"])
    ]
    if len(added) != 1:
        die(f"expected exactly one new migration, found {len(added)}: {added}")
    path = added[0]
    base = path.rsplit("/", 1)[1]
    version = base.split("_", 1)[0]
    name = base.split("_", 1)[1].removesuffix(".sql")
    return path, version, name


# ── the deploy ──────────────────────────────────────────────────────────────

def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 1:
        die("usage: bv-deploy-cloud.py <pr> [--dry-run]")
    pr = args[0]

    sha = pr_head(pr)
    path, want, name = migration_of(pr, sha)
    # A cloud clone is shallow, so the PR's own commit is usually not here yet.
    run("git", "fetch", "-q", "--depth=1", "origin", f"pull/{pr}/head")
    body = run("git", "show", f"{sha}:{path}")

    tag = "$bv_cloud_deploy$"
    if tag in body:
        die("the dollar-quote tag appears in the migration; pick another")

    print(f"PR #{pr} head {sha[:7]}")
    print(f"migration  {path.rsplit('/', 1)[1]}  ({len(body):,} bytes)")

    before = head()
    print(f"prod head  {before}")
    if before is None:
        die("could not read the prod head")
    if want <= before:
        die(f"this migration is {want}, not above the head {before} — renumber it first")
    if int(want) != int(before) + 1:
        die(f"strict number order: {want} is not {int(before) + 1}")
    active, defined = clock()
    before_defined = defined
    print(f"clock      {active}/{defined} jobs active")
    if active != defined:
        die(f"the clock is not whole ({active} of {defined} active) — look before deploying")

    if dry:
        print("\n--dry-run: stopping before the clock is touched.")
        return

    # 1. unwind the clock, then let whatever is mid-run finish
    print("\nunwinding the clock...")
    sql("select public.unwind_the_clock();", timeout=120)
    for _ in range(30):
        n = busy_jobs()
        if n == 0:
            break
        print(f"  {n} job(s) still running...")
        time.sleep(10)
    else:
        print("  WARNING: jobs still running after 5 min; going ahead (lock_timeout guards us)")

    # 2. apply and record the version in ONE transaction
    print(f"applying {want}...")
    push_ok, push_err = True, ""
    statement = (
        "begin;\n"
        f"{body}\n"
        "insert into supabase_migrations.schema_migrations (version, name, statements)\n"
        f"values ('{want}', '{name}', array[{tag}{body}{tag}]);\n"
        "commit;"
    )
    try:
        sql(statement)
    except Exception as exc:  # noqa: BLE001
        push_ok = False
        detail = getattr(exc, "read", None)
        push_err = detail().decode()[:2000] if detail else str(exc)
        print(f"  push reported an error:\n{push_err}")

    # 3. THE HEAD DECIDES, NOT THE HTTP CALL — and it must be given time to say so.
    #
    # 2026-10-20, 0215: the call returned "upstream request failed" (the API gateway gave up on a
    # long migration) and a single head read straight afterwards still said 0214. It was read too
    # early: the transaction was still committing, and 0215 landed seconds later. The script
    # reported "NOT MERGING", so prod went to 0215 while main stayed behind — exactly the
    # half-deployed state the merge gate exists to prevent.
    #
    # A dropped connection says nothing about the transaction's fate. So when the push errors,
    # poll: either the head becomes the version we pushed, or it is still the old head after the
    # database has gone quiet, and only then is it really a failure.
    after = head()
    if after != want and not push_ok:
        print("  the call dropped; polling the head (a dropped connection does not mean a rollback)")
        for i in range(24):  # up to ~4 minutes
            time.sleep(10)
            after = head()
            busy = busy_jobs()
            print(f"  +{(i + 1) * 10}s head={after} busy={busy}")
            if after == want:
                print("  it landed after all — the call dropped, the transaction committed")
                break
    print(f"head after {after}  (wanted {want})")

    # 4. wind the clock back whatever happened
    print("winding the clock...")
    sql("select public.wind_the_clock();", timeout=120)
    active, defined = clock()
    print(f"clock      {active}/{defined} jobs active")
    if defined > before_defined:
        print(
            f"  note: this migration added {defined - before_defined} job(s); "
            "wind_the_clock() lit them, which is how a job defined INACTIVE goes live (0078)."
        )

    landed = after == want
    print(f"\npush_ok={push_ok} landed={landed} head={after} want={want} jobs={active}/{defined}")
    if active != defined:
        print("WARNING: the clock did not come back whole — fix this before anything else.")

    # 5. merge ONLY if the push landed at the version we meant
    if not landed:
        die(
            "NOT MERGING: the head is not the version we pushed. Nothing was merged. "
            "Prod is unchanged if the transaction rolled back; read the error above to its last line."
        )
    print(f"merging #{pr}...")
    out = run(
        "gh", "api", "-X", "PUT", f"repos/{REPO}/pulls/{pr}/merge",
        "-f", "merge_method=squash",
    )
    print(out)

    # GitHub does not let a push made with this session's token trigger a workflow, so the merge
    # above fires NOTHING: no Acceptance on main, and — the one that bites — no Pages deploy, which
    # means the client half of the migration never reaches the site. 0214 sat server-live and
    # client-stale for 17 minutes this way, and the Korean merge before it had to be dispatched by
    # hand too. Dispatch them explicitly instead.
    # NOT migrations-apply-proof.yml: a workflow_dispatch sets FROM_ZERO there, which rebuilds the
    # world from scratch and takes hours.
    for wf in ("deploy-pages.yml", "acceptance.yml"):
        try:
            run("gh", "api", "-X", "POST",
                f"repos/{REPO}/actions/workflows/{wf}/dispatches", "-f", "ref=main")
            print(f"dispatched {wf} on main")
        except SystemExit:
            print(f"COULD NOT dispatch {wf} — do it by hand, or the site stays stale")

    print(f"\n0{want[-4:]} is live and #{pr} is merged. Run the 30-minute after-check.")


if __name__ == "__main__":
    main()

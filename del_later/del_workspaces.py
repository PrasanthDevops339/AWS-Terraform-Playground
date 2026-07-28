#!/usr/bin/env python3
"""
tfe_delete_workspaces.py
Deletes TFE workspaces listed by name in a text file (one name per line).

Safety model:
  - Defaults to TFE's "safe-delete" action, which REFUSES to delete a
    workspace that still has resources under management.
  - --force switches to a hard delete (deletes regardless of resources).
    Hard delete requires an extra typed confirmation.
  - --dry-run resolves and prints what WOULD happen with no API calls
    that mutate anything.
  - Without --yes, you get one interactive confirmation before deletion.

Usage:
    export TFE_TOKEN="xxxxxxxx.atlasv1.xxxxxxxx"

    # See what would happen, no changes made
    python3 tfe_delete_workspaces.py <org-name> workspaces.txt --dry-run

    # Safe-delete (blocked if a workspace still manages resources)
    python3 tfe_delete_workspaces.py <org-name> workspaces.txt

    # Hard delete (skips the resource check) — use with care
    python3 tfe_delete_workspaces.py <org-name> workspaces.txt --force

    # Non-interactive (e.g. CI) — skip the confirmation prompt
    python3 tfe_delete_workspaces.py <org-name> workspaces.txt --yes

Input file format (workspaces.txt):
    prod-network
    staging-ecs
    # lines starting with # are ignored, blank lines are ignored

Requires: requests  (pip install requests)
"""

from __future__ import annotations

import argparse
import csv
import logging
import os
import sys
from datetime import datetime, timezone

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

TFE_HOSTNAME = "tfe.prasanth.com"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
log = logging.getLogger("tfe-delete-workspaces")


def build_session(token: str) -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/vnd.api+json",
        }
    )
    retry = Retry(
        total=5,
        backoff_factor=1.0,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "DELETE", "POST"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    return session


def load_workspace_names(path: str) -> list[str]:
    names: list[str] = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            names.append(line)

    # de-dupe, preserve order
    seen = set()
    deduped = []
    for name in names:
        if name not in seen:
            seen.add(name)
            deduped.append(name)

    if not deduped:
        log.error("No workspace names found in %s", path)
        sys.exit(1)

    return deduped


def lookup_workspace(session: requests.Session, org: str, name: str) -> dict | None:
    """Return workspace attributes (incl. resource-count) or None if not found."""
    url = f"https://{TFE_HOSTNAME}/api/v2/organizations/{org}/workspaces/{name}"
    resp = session.get(url, timeout=30)
    if resp.status_code == 404:
        return None
    if not resp.ok:
        raise RuntimeError(f"lookup failed ({resp.status_code}): {resp.text[:300]}")
    return resp.json().get("data", {})


def delete_workspace(session: requests.Session, org: str, name: str, force: bool) -> tuple[bool, str]:
    """Returns (success, message)."""
    if force:
        url = f"https://{TFE_HOSTNAME}/api/v2/organizations/{org}/workspaces/{name}"
        resp = session.delete(url, timeout=30)
    else:
        url = (
            f"https://{TFE_HOSTNAME}/api/v2/organizations/{org}"
            f"/workspaces/{name}/actions/safe-delete"
        )
        resp = session.post(url, timeout=30)

    if resp.status_code in (200, 202, 204):
        return True, "deleted"
    if resp.status_code == 404:
        return False, "not found (already deleted?)"
    if resp.status_code == 409:
        return False, "blocked: workspace still manages resources (use --force to override)"
    if resp.status_code == 403:
        return False, "forbidden: token lacks permission on this workspace"
    return False, f"API error {resp.status_code}: {resp.text[:300]}"


def write_report(results: list[dict], org: str) -> str:
    outfile = f"tfe_delete_report_{org}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.csv"
    with open(outfile, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "resource_count", "status", "detail"])
        writer.writeheader()
        writer.writerows(results)
    return outfile


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete TFE workspaces listed in a text file.")
    parser.add_argument("org", help="TFE organization name")
    parser.add_argument("file", help="Text file with one workspace name per line")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Hard delete instead of safe-delete (deletes even if resources are still managed)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Resolve and print what would happen, make no destructive API calls",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the interactive confirmation prompt (for CI use)",
    )
    args = parser.parse_args()

    token = os.environ.get("TFE_TOKEN")
    if not token:
        log.error("TFE_TOKEN environment variable not set.")
        sys.exit(1)

    names = load_workspace_names(args.file)
    session = build_session(token)

    log.info("Resolving %s workspace name(s) against org '%s'...", len(names), args.org)
    plan = []
    for name in names:
        try:
            ws = lookup_workspace(session, args.org, name)
        except RuntimeError as exc:
            plan.append({"name": name, "resource_count": "", "found": False, "error": str(exc)})
            continue

        if ws is None:
            plan.append({"name": name, "resource_count": "", "found": False, "error": "not found"})
        else:
            rc = ws.get("attributes", {}).get("resource-count", 0)
            plan.append({"name": name, "resource_count": rc, "found": True, "error": None})

    print("\nPlanned action:", "HARD DELETE" if args.force else "SAFE DELETE (resource-managed workspaces skipped)")
    print(f"{'NAME':30} {'RESOURCES':10} {'STATE'}")
    for item in plan:
        if not item["found"]:
            state = f"NOT FOUND ({item['error']})"
        elif args.force:
            state = "will hard-delete"
        elif item["resource_count"]:
            state = f"WILL BE SKIPPED — {item['resource_count']} resources managed"
        else:
            state = "will safe-delete (0 resources)"
        print(f"{item['name']:30} {str(item['resource_count']):10} {state}")

    if args.dry_run:
        log.info("Dry run complete. No changes made.")
        return

    to_delete = [i for i in plan if i["found"]]
    if not to_delete:
        log.info("Nothing resolvable to delete. Exiting.")
        return

    if args.force:
        print(
            "\n⚠️  --force is set: this performs a HARD DELETE and will destroy workspaces "
            "even if they still manage live resources. This does NOT run 'terraform destroy' "
            "first — any real infrastructure under those workspaces becomes unmanaged state."
        )

    if not args.yes:
        confirm_word = "HARD-DELETE" if args.force else "delete"
        answer = input(f"\nType '{confirm_word}' to proceed with {len(to_delete)} workspace(s): ")
        if answer.strip() != confirm_word:
            log.info("Confirmation not received. Aborted, no changes made.")
            return

    results = []
    for item in to_delete:
        name = item["name"]
        success, detail = delete_workspace(session, args.org, name, args.force)
        status = "deleted" if success else "skipped/failed"
        log.info("%s: %s (%s)", name, status, detail)
        results.append(
            {
                "name": name,
                "resource_count": item["resource_count"],
                "status": status,
                "detail": detail,
            }
        )

    outfile = write_report(results, args.org)
    deleted_count = sum(1 for r in results if r["status"] == "deleted")
    log.info("Done. %s/%s deleted. Report written to %s", deleted_count, len(results), outfile)


if __name__ == "__main__":
    main()
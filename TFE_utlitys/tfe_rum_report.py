#!/usr/bin/env python3
"""
tfe_rum_report.py
Builds a Resources-Under-Management (RUM) report for a TFE organization so you
can walk into a licensing conversation with your own number.

Pulls from up to three independent sources and reconciles them:

  1. EXPLORER API   /api/v2/organizations/<org>/explorer?type=workspaces
     -> per-workspace RUM field (e.g. current_rum_count).
        Requires TFE v202503-1 or later. This is the closest thing to what
        HashiCorp/IBM meters. Cheap: paginated, ~1 call per 100 workspaces.

  2. WORKSPACES API /api/v2/organizations/<org>/workspaces
     -> "resource-count" attribute. Available on every TFE version. Good
        cross-check and a usable proxy if Explorer is unavailable.

  3. STATE VERSION  /api/v2/workspaces/<id>/current-state-version   (--state-version)
     -> "billable-rum-count" attribute per workspace. Most authoritative
        per-workspace figure, but costs 1 API call per workspace. Threaded.

Field names differ across TFE versions, so this script does NOT hardcode them:
it scans each record's attributes for any key containing "rum" and reports
which key it actually found. Use --probe to dump raw attribute keys first.

Outputs:
  - CSV: one row per workspace, all three numbers side by side
  - Console summary replicating the fields TFE reports in its own license
    telemetry payload: total, avg, median, 80th percentile, max, min

Usage:
    export TFE_TOKEN="xxxxxxxx.atlasv1.xxxxxxxx"

    # fast path - Explorer + workspaces resource-count
    python3 tfe_rum_report.py tfe.example.com my-org

    # add the per-workspace state-version billable RUM (slower, most accurate)
    python3 tfe_rum_report.py tfe.example.com my-org --state-version

    # inspect what your TFE version actually returns before trusting anything
    python3 tfe_rum_report.py tfe.example.com my-org --probe

    # narrow to a subset while testing
    python3 tfe_rum_report.py tfe.example.com my-org --limit 25 --state-version

Token resolution (checked in order):
    1. TFE_TOKEN env var - always wins
    2. TF_TOKEN_<host> using Terraform's CLI credentials convention:
       dots -> "_", hyphens -> "__"
       e.g. tfe-dev.example.com -> TF_TOKEN_tfe__dev_example_com

Requires: requests
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import os
import statistics
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("tfe-rum")

PAGE_SIZE = 100
API_MEDIA_TYPE = "application/vnd.api+json"


# --------------------------------------------------------------------------
# Session / auth
# --------------------------------------------------------------------------
def normalize_host(host: str) -> str:
    """Strip scheme and trailing slash so callers can paste a URL or a hostname."""
    return host.replace("https://", "").replace("http://", "").rstrip("/")


def resolve_token(host: str) -> str:
    """TFE_TOKEN wins; otherwise fall back to Terraform's TF_TOKEN_<host> convention."""
    token = os.environ.get("TFE_TOKEN")
    if token:
        return token

    encoded = host.replace("-", "__").replace(".", "_")
    var_name = f"TF_TOKEN_{encoded}"
    token = os.environ.get(var_name)
    if token:
        log.info("Using token from %s", var_name)
        return token

    log.error(
        "No token found. Set TFE_TOKEN, or %s.\n"
        "Generate one at: https://%s/app/settings/tokens",
        var_name,
        host,
    )
    sys.exit(1)


def build_session(token: str) -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {token}",
            "Content-Type": API_MEDIA_TYPE,
        }
    )
    retry = Retry(
        total=5,
        backoff_factor=1.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_connections=32, pool_maxsize=32)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


# --------------------------------------------------------------------------
# Generic helpers
# --------------------------------------------------------------------------
def find_rum_key(attributes: dict[str, Any]) -> str | None:
    """
    Locate the RUM field without hardcoding a name.

    TFE has used several spellings across versions (current_rum_count,
    current-rum-count, billable-rum-count, billable_rum_count). Rather than
    guess, find any numeric attribute whose key mentions 'rum'.
    """
    candidates = [
        k
        for k, v in attributes.items()
        if "rum" in k.lower() and isinstance(v, (int, float))
    ]
    if not candidates:
        return None
    # Prefer a "current" or "billable" flavour if several exist.
    for preferred in ("current", "billable"):
        for k in candidates:
            if preferred in k.lower():
                return k
    return candidates[0]


def paginate(session: requests.Session, url: str, params: dict[str, Any]) -> list[dict]:
    """Walk a JSON:API paginated collection and return all data records."""
    results: list[dict] = []
    page = 1
    while True:
        params_page = dict(params)
        params_page["page[number]"] = page
        params_page["page[size]"] = PAGE_SIZE

        resp = session.get(url, params=params_page, timeout=60)
        if resp.status_code == 404:
            raise FileNotFoundError(f"404 from {url}")
        if not resp.ok:
            raise RuntimeError(f"{resp.status_code} from {url}: {resp.text[:400]}")

        payload = resp.json()
        if "errors" in payload:
            detail = payload["errors"][0].get("detail") or payload["errors"][0].get("title")
            raise RuntimeError(f"API error from {url}: {detail}")

        batch = payload.get("data", [])
        results.extend(batch)

        pagination = payload.get("meta", {}).get("pagination", {})
        next_page = pagination.get("next-page")
        if not next_page:
            break
        page = next_page
        log.info("  ... fetched %d records", len(results))

    return results


# --------------------------------------------------------------------------
# Source 1: Explorer API
# --------------------------------------------------------------------------
def fetch_explorer(session: requests.Session, host: str, org: str) -> tuple[dict[str, int], str | None]:
    """
    Returns ({workspace_name: rum_count}, rum_field_name).
    Returns ({}, None) if the Explorer API or the RUM field is unavailable.
    """
    url = f"https://{host}/api/v2/organizations/{org}/explorer"
    log.info("Source 1: Explorer API (per-workspace RUM)")
    try:
        records = paginate(session, url, {"type": "workspaces"})
    except FileNotFoundError:
        log.warning(
            "  Explorer API not found (404). Your TFE predates v202503-1, "
            "or the endpoint is disabled. Falling back to resource-count."
        )
        return {}, None
    except RuntimeError as exc:
        log.warning("  Explorer API unavailable: %s", exc)
        return {}, None

    if not records:
        log.warning("  Explorer returned no records.")
        return {}, None

    attrs = records[0].get("attributes", {})
    rum_key = find_rum_key(attrs)
    if not rum_key:
        log.warning(
            "  No RUM field in Explorer output. Available keys: %s",
            ", ".join(sorted(attrs.keys())),
        )
        return {}, None

    name_key = next(
        (k for k in ("workspace_name", "name", "workspace-name") if k in attrs),
        None,
    )
    if not name_key:
        log.warning("  Could not identify the workspace name field in Explorer output.")
        return {}, None

    out: dict[str, int] = {}
    for rec in records:
        a = rec.get("attributes", {})
        name = a.get(name_key)
        value = a.get(rum_key)
        if name is not None and isinstance(value, (int, float)):
            out[name] = int(value)

    log.info("  Found field '%s' across %d workspaces", rum_key, len(out))
    return out, rum_key


# --------------------------------------------------------------------------
# Source 2: Workspaces API
# --------------------------------------------------------------------------
def fetch_workspaces(session: requests.Session, host: str, org: str) -> list[dict]:
    """Returns a list of {id, name, resource_count, terraform_version, updated_at}."""
    url = f"https://{host}/api/v2/organizations/{org}/workspaces"
    log.info("Source 2: Workspaces API (resource-count)")
    records = paginate(session, url, {})

    out = []
    for rec in records:
        a = rec.get("attributes", {})
        out.append(
            {
                "id": rec.get("id"),
                "name": a.get("name"),
                "resource_count": a.get("resource-count"),
                "terraform_version": a.get("terraform-version"),
                "execution_mode": a.get("execution-mode"),
                "updated_at": a.get("updated-at"),
            }
        )
    log.info("  Retrieved %d workspaces", len(out))
    return out


# --------------------------------------------------------------------------
# Source 3: Current state version (billable RUM)
# --------------------------------------------------------------------------
def fetch_state_version_rum(
    session: requests.Session, host: str, workspace_id: str
) -> tuple[int | None, str | None]:
    """Returns (billable_rum_count, field_name) for one workspace, or (None, None)."""
    url = f"https://{host}/api/v2/workspaces/{workspace_id}/current-state-version"
    resp = session.get(url, timeout=60)
    if resp.status_code == 404:
        return None, None  # no state yet
    if not resp.ok:
        return None, None

    attrs = resp.json().get("data", {}).get("attributes", {})
    key = find_rum_key(attrs)
    if not key:
        return None, None
    value = attrs.get(key)
    return (int(value) if isinstance(value, (int, float)) else None), key


def fetch_all_state_version_rum(
    session: requests.Session, host: str, workspaces: list[dict], threads: int
) -> tuple[dict[str, int], str | None]:
    log.info(
        "Source 3: current-state-version billable RUM across %d workspaces (%d threads)",
        len(workspaces),
        threads,
    )
    out: dict[str, int] = {}
    found_key: str | None = None
    done = 0

    with ThreadPoolExecutor(max_workers=threads) as pool:
        futures = {
            pool.submit(fetch_state_version_rum, session, host, ws["id"]): ws
            for ws in workspaces
            if ws.get("id")
        }
        for fut in as_completed(futures):
            ws = futures[fut]
            done += 1
            if done % 100 == 0:
                log.info("  ... %d/%d", done, len(futures))
            try:
                value, key = fut.result()
            except Exception as exc:  # noqa: BLE001
                log.debug("  %s: %s", ws["name"], exc)
                continue
            if key and not found_key:
                found_key = key
            if value is not None:
                out[ws["name"]] = value

    if found_key:
        log.info("  Found field '%s' on %d workspaces", found_key, len(out))
    else:
        log.warning(
            "  No RUM field on state versions. This org may not be on a "
            "RUM-metered plan yet, in which case resource-count is your proxy."
        )
    return out, found_key


# --------------------------------------------------------------------------
# Probe mode
# --------------------------------------------------------------------------
def probe(session: requests.Session, host: str, org: str) -> None:
    """Dump raw attribute keys from each API so field names can be verified."""
    log.info("PROBE MODE - showing raw attributes so you can verify field names\n")

    print("=" * 78)
    print("EXPLORER API  /api/v2/organizations/%s/explorer?type=workspaces" % org)
    print("=" * 78)
    try:
        resp = session.get(
            f"https://{host}/api/v2/organizations/{org}/explorer",
            params={"type": "workspaces", "page[size]": 1},
            timeout=60,
        )
        print(f"HTTP {resp.status_code}")
        if resp.ok:
            data = resp.json().get("data", [])
            if data:
                print(json.dumps(data[0].get("attributes", {}), indent=2)[:3000])
            else:
                print("(no records returned)")
        else:
            print(resp.text[:800])
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}")

    print("\n" + "=" * 78)
    print("WORKSPACES API  /api/v2/organizations/%s/workspaces" % org)
    print("=" * 78)
    ws_id = None
    try:
        resp = session.get(
            f"https://{host}/api/v2/organizations/{org}/workspaces",
            params={"page[size]": 1},
            timeout=60,
        )
        print(f"HTTP {resp.status_code}")
        if resp.ok:
            data = resp.json().get("data", [])
            if data:
                ws_id = data[0].get("id")
                print(json.dumps(data[0].get("attributes", {}), indent=2)[:3000])
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}")

    print("\n" + "=" * 78)
    print("STATE VERSION  /api/v2/workspaces/<id>/current-state-version")
    print("=" * 78)
    if not ws_id:
        print("(skipped - no workspace id resolved)")
        return
    try:
        resp = session.get(
            f"https://{host}/api/v2/workspaces/{ws_id}/current-state-version", timeout=60
        )
        print(f"workspace {ws_id} -> HTTP {resp.status_code}")
        if resp.ok:
            print(json.dumps(resp.json().get("data", {}).get("attributes", {}), indent=2)[:3000])
        else:
            print(resp.text[:800])
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}")


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------
def percentile(values: list[int], pct: float) -> float:
    """Nearest-rank percentile - matches how TFE reports its 80th percentile."""
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, int(round(pct / 100.0 * len(ordered))))
    return float(ordered[min(rank, len(ordered)) - 1])


def summarize(label: str, values: list[int]) -> None:
    if not values:
        print(f"\n{label}: no data")
        return
    print(f"\n{label}")
    print("-" * len(label))
    print(f"  workspaces with data     : {len(values):>12,}")
    print(f"  TOTAL RUM                : {sum(values):>12,}")
    print(f"  average per workspace    : {statistics.mean(values):>12,.1f}")
    print(f"  median per workspace     : {statistics.median(values):>12,.1f}")
    print(f"  80th percentile          : {percentile(values, 80):>12,.1f}")
    print(f"  max                      : {max(values):>12,}")
    print(f"  min                      : {min(values):>12,}")


def write_csv(rows: list[dict], outfile: str) -> None:
    fields = [
        "name",
        "id",
        "explorer_rum",
        "resource_count",
        "state_billable_rum",
        "terraform_version",
        "execution_mode",
        "updated_at",
    ]
    with open(outfile, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    log.info("Wrote %s (%d rows)", outfile, len(rows))


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Report Resources Under Management (RUM) across a TFE organization.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("host", help="TFE hostname, e.g. tfe.example.com")
    parser.add_argument("org", help="TFE organization name")
    parser.add_argument(
        "--state-version",
        action="store_true",
        help="Also query current-state-version per workspace for billable RUM (slower)",
    )
    parser.add_argument(
        "--probe",
        action="store_true",
        help="Dump raw API attributes so you can verify field names, then exit",
    )
    parser.add_argument(
        "--threads", type=int, default=8, help="Concurrency for --state-version (default 8)"
    )
    parser.add_argument(
        "--limit", type=int, default=None, help="Only process the first N workspaces (testing)"
    )
    parser.add_argument("-o", "--output", default=None, help="Output CSV path")
    args = parser.parse_args()

    host = normalize_host(args.host)
    token = resolve_token(host)
    session = build_session(token)

    if args.probe:
        probe(session, host, args.org)
        return

    explorer_rum, explorer_key = fetch_explorer(session, host, args.org)
    workspaces = fetch_workspaces(session, host, args.org)

    if args.limit:
        workspaces = workspaces[: args.limit]
        log.info("Limited to first %d workspaces", len(workspaces))

    state_rum: dict[str, int] = {}
    state_key: str | None = None
    if args.state_version:
        state_rum, state_key = fetch_all_state_version_rum(
            session, host, workspaces, args.threads
        )

    rows = []
    for ws in workspaces:
        name = ws["name"]
        rows.append(
            {
                **ws,
                "explorer_rum": explorer_rum.get(name),
                "state_billable_rum": state_rum.get(name),
            }
        )
    rows.sort(
        key=lambda r: (
            r.get("explorer_rum") or r.get("state_billable_rum") or r.get("resource_count") or 0
        ),
        reverse=True,
    )

    outfile = args.output or (
        f"tfe_rum_{args.org}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.csv"
    )
    write_csv(rows, outfile)

    # ---- console summary ----
    print("\n" + "=" * 78)
    print(f"RUM REPORT  -  org '{args.org}' on {host}")
    print(f"generated {datetime.now(timezone.utc):%Y-%m-%d %H:%M:%S} UTC")
    print("=" * 78)
    print(f"\nTotal workspaces: {len(workspaces):,}")

    if explorer_rum:
        summarize(f"EXPLORER API  (field: {explorer_key})", list(explorer_rum.values()))
    if state_rum:
        summarize(f"STATE VERSION (field: {state_key})", list(state_rum.values()))

    rc = [r["resource_count"] for r in rows if isinstance(r.get("resource_count"), int)]
    summarize("WORKSPACE resource-count (proxy / cross-check)", rc)

    # ---- reconciliation ----
    totals = {}
    if explorer_rum:
        totals["explorer"] = sum(explorer_rum.values())
    if state_rum:
        totals["state-version"] = sum(state_rum.values())
    if rc:
        totals["resource-count"] = sum(rc)

    if len(totals) > 1:
        print("\nRECONCILIATION")
        print("--------------")
        for k, v in totals.items():
            print(f"  {k:<18}: {v:>12,}")
        spread = max(totals.values()) - min(totals.values())
        base = max(totals.values()) or 1
        print(f"  spread            : {spread:>12,}  ({spread / base * 100:.1f}%)")
        if spread:
            print(
                "\n  A gap between these is normal (empty/errored states, data sources,\n"
                "  null_resource exclusions) - but any gap is a question worth asking\n"
                "  the vendor, since it is the difference between your number and theirs."
            )

    print("\nTop 20 workspaces by RUM:")
    print(f"  {'WORKSPACE':<45} {'EXPLORER':>10} {'STATE':>10} {'RES_COUNT':>10}")
    for r in rows[:20]:
        print(
            f"  {str(r['name'])[:45]:<45} "
            f"{str(r.get('explorer_rum') if r.get('explorer_rum') is not None else '-'):>10} "
            f"{str(r.get('state_billable_rum') if r.get('state_billable_rum') is not None else '-'):>10} "
            f"{str(r.get('resource_count') if r.get('resource_count') is not None else '-'):>10}"
        )

    print(f"\nFull detail: {outfile}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
tfe_list_workspaces.py
Exports all workspaces in a TFE organization to a CSV file.

Usage:
    export TFE_TOKEN="xxxxxxxx.atlasv1.xxxxxxxx"
    python3 tfe_list_workspaces.py <org-name> [-o output.csv]

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
PAGE_SIZE = 100

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
log = logging.getLogger("tfe-list-workspaces")


def build_session(token: str) -> requests.Session:
    """Session with retry/backoff for transient TFE API failures."""
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
        allowed_methods=["GET"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    return session


def fetch_all_workspaces(session: requests.Session, org: str) -> list[dict]:
    """Paginate through /organizations/:org/workspaces and return raw records."""
    workspaces: list[dict] = []
    page = 1

    while True:
        url = f"https://{TFE_HOSTNAME}/api/v2/organizations/{org}/workspaces"
        params = {"page[size]": PAGE_SIZE, "page[number]": page}

        resp = session.get(url, params=params, timeout=30)

        if resp.status_code == 401:
            log.error("Authentication failed — check TFE_TOKEN.")
            sys.exit(1)
        if resp.status_code == 404:
            log.error("Organization '%s' not found on %s.", org, TFE_HOSTNAME)
            sys.exit(1)
        if not resp.ok:
            log.error("TFE API error %s: %s", resp.status_code, resp.text[:500])
            sys.exit(1)

        body = resp.json()
        data = body.get("data", [])
        workspaces.extend(data)

        pagination = body.get("meta", {}).get("pagination", {})
        total_pages = pagination.get("total-pages", 1)
        log.info("Fetched page %s/%s (%s workspaces so far)", page, total_pages, len(workspaces))

        next_page = pagination.get("next-page")
        if not next_page:
            break
        page = next_page

    return workspaces


def write_csv(workspaces: list[dict], outfile: str) -> None:
    fieldnames = [
        "id",
        "name",
        "terraform_version",
        "execution_mode",
        "auto_apply",
        "resource_count",
        "locked",
        "updated_at",
    ]

    rows = []
    for ws in workspaces:
        attrs = ws.get("attributes", {})
        rows.append(
            {
                "id": ws.get("id", ""),
                "name": attrs.get("name", ""),
                "terraform_version": attrs.get("terraform-version", ""),
                "execution_mode": attrs.get("execution-mode", ""),
                "auto_apply": attrs.get("auto-apply", ""),
                "resource_count": attrs.get("resource-count", ""),
                "locked": attrs.get("locked", ""),
                "updated_at": attrs.get("updated-at", ""),
            }
        )

    rows.sort(key=lambda r: r["name"].lower())

    with open(outfile, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(rows)

    log.info("Wrote %s workspaces to %s", len(rows), outfile)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export TFE workspaces to CSV.")
    parser.add_argument("org", help="TFE organization name")
    parser.add_argument(
        "-o",
        "--output",
        help="Output CSV path (default: workspaces_<org>_<timestamp>.csv)",
        default=None,
    )
    args = parser.parse_args()

    token = os.environ.get("TFE_TOKEN")
    if not token:
        log.error("TFE_TOKEN environment variable not set.")
        log.error("Generate one at: https://%s/app/settings/tokens", TFE_HOSTNAME)
        sys.exit(1)

    outfile = args.output or (
        f"workspaces_{args.org}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.csv"
    )

    session = build_session(token)
    workspaces = fetch_all_workspaces(session, args.org)
    write_csv(workspaces, outfile)


if __name__ == "__main__":
    main()
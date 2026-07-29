#!/usr/bin/env python3
"""
tfe_list_workspaces.py
Exports all workspaces in a TFE organization to a CSV file.

Usage:
    # token via TFE_TOKEN, or auto-detected from TF_TOKEN_<host> (see below)
    python3 tfe_list_workspaces.py <host> <org-name> [-o output.csv]

Examples:
    python3 tfe_list_workspaces.py tfe-dev.prasanth.com 
    python3 tfe_list_workspaces.py tfe.prasanth.com  -o prod.csv

Token resolution (checked in order):
    1. TFE_TOKEN env var, if set — always wins.
    2. TF_TOKEN_<host>, using Terraform's own CLI credentials convention:
       dots -> "_", hyphens -> "__".
       e.g. host "tfe-dev.prasanth.com" -> TF_TOKEN_tfe__dev_prasanth_com
       This lets you keep one token per TFE instance exported (or set in your
       CI secrets) without re-exporting TFE_TOKEN every time you switch hosts.

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

PAGE_SIZE = 100

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
log = logging.getLogger("tfe-list-workspaces")


def normalize_host(host: str) -> str:
    """Strip a scheme if the user passed one (e.g. 'https://tfe-dev.prasanth.com')."""
    return host.replace("https://", "").replace("http://", "").rstrip("/")


def token_env_var_name(host: str) -> str:
    """Terraform CLI convention: TF_TOKEN_<host>, dots -> '_', hyphens -> '__'."""
    encoded = host.replace(".", "_").replace("-", "__")
    return f"TF_TOKEN_{encoded}"


def resolve_token(host: str) -> str:
    token = os.environ.get("TFE_TOKEN")
    if token:
        return token

    env_var = token_env_var_name(host)
    token = os.environ.get(env_var)
    if token:
        log.info("Using token from %s", env_var)
        return token

    log.error("No token found. Set TFE_TOKEN or %s in your environment.", env_var)
    sys.exit(1)


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
        allowed_methods=["GET"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    return session


def fetch_all_workspaces(session: requests.Session, host: str, org: str) -> list[dict]:
    """Paginate through /organizations/:org/workspaces and return raw records."""
    workspaces: list[dict] = []
    page = 1

    while True:
        url = f"https://{host}/api/v2/organizations/{org}/workspaces"
        params = {"page[size]": PAGE_SIZE, "page[number]": page}

        resp = session.get(url, params=params, timeout=30)

        if resp.status_code == 401:
            log.error("Authentication failed against %s — check the token.", host)
            sys.exit(1)
        if resp.status_code == 404:
            log.error("Organization '%s' not found on %s.", org, host)
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
    parser.add_argument("host", help="TFE hostname, e.g. tfe-dev.prasanth.com")
    parser.add_argument("org", help="TFE organization name")
    parser.add_argument(
        "-o",
        "--output",
        help="Output CSV path (default: workspaces_<org>_<timestamp>.csv)",
        default=None,
    )
    args = parser.parse_args()

    host = normalize_host(args.host)
    token = resolve_token(host)

    outfile = args.output or (
        f"workspaces_{args.org}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.csv"
    )

    session = build_session(token)
    workspaces = fetch_all_workspaces(session, host, args.org)
    write_csv(workspaces, outfile)


if __name__ == "__main__":
    main()
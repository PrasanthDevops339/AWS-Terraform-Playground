"""Validate public CA and dnf configuration before Terraform reads their content."""
import argparse
import configparser
import pathlib
import ssl
from urllib.parse import urlsplit


def validate(certificate, repositories):
    pem = pathlib.Path(certificate).read_text()
    if "PRIVATE KEY" in pem:
        raise ValueError("A private key must never enter component data or Terraform state")
    ssl.create_default_context(cadata=pem)
    config = configparser.ConfigParser(interpolation=None)
    config.read(repositories)
    if not config.sections():
        raise ValueError("At least one approved repository is required")
    for name in config.sections():
        repo = config[name]
        if repo.get("enabled", "1") != "1":
            continue
        if repo.get("gpgcheck") != "1" or repo.get("sslverify", "1") != "1":
            raise ValueError(f"{name}: require gpgcheck=1 and sslverify=1")
        urls = repo.get("baseurl", "").split()
        if not urls or repo.get("mirrorlist") or repo.get("metalink"):
            raise ValueError(f"{name}: supply explicit reviewed baseurl URLs")
        for url in urls:
            parsed = urlsplit(url)
            if parsed.scheme != "https" or parsed.username or parsed.password:
                raise ValueError(f"{name}: require credential-free HTTPS baseurl")
        if not repo.get("gpgkey"):
            raise ValueError(f"{name}: declare the approved signing key")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("certificate")
    parser.add_argument("repositories")
    args = parser.parse_args()
    validate(args.certificate, args.repositories)


if __name__ == "__main__":
    main()

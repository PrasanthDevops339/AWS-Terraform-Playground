import hashlib
from pathlib import Path
import sys


def main():
    archive, checksums, name = sys.argv[1:]
    expected = next(line.split()[0] for line in Path(checksums).read_text().splitlines() if line.endswith(name))
    if hashlib.sha256(Path(archive).read_bytes()).hexdigest() != expected:
        raise ValueError("Trivy release checksum mismatch")


if __name__ == "__main__":
    main()

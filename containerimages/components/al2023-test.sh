set -euo pipefail
. /etc/os-release
test "$ID" = amzn
test "$VERSION_ID" = 2023
test "$(uname -m)" = x86_64
test "$(id -u app)" = 10001
test "$(id -g app)" = 10001
test -s /etc/pki/ca-trust/source/anchors/enterprise.pem
test -s /etc/pki/tls/certs/ca-bundle.crt
test -s /usr/local/share/containerimages/packages.tsv
test -s /usr/local/share/containerimages/sbom.spdx.json
test -z "$(find /usr /bin /sbin -xdev -type f -perm /6000 -print -quit)"
# Representative downstream startup with the documented identity and writable path.
runuser -u app -- python3 -c 'import json, pathlib, ssl; ssl.create_default_context(); p=pathlib.Path("/app/smoke"); p.write_text("ready"); assert p.read_text()=="ready"; p.unlink(); assert json.load(open("/usr/local/share/containerimages/sbom.spdx.json"))["packages"]'
runuser -u app -- test ! -w /etc/passwd

#!/usr/bin/env bash
# dartec_bootstrap installs the pinned HACS archive and nothing else.
#
# Builds the real add-on image and runs its real run.sh against a fake
# Supervisor (fake_supervisor.py), with a fresh run_token, the way the
# provisioner starts it. Then does the same with the archive swapped for the
# ones an attacker who controlled the release asset would serve, and checks
# that nothing is unpacked, the config entries are untouched and Core is never
# stopped. Finally checks that the image cannot be built around a wrong pin.
#
# Needs docker and python3 (python on Windows: set PYTHON=python). Uses docker
# cp rather than bind mounts, so it runs the same from Git Bash on Windows.
#
#   bash tests/bootstrap_hacs_test.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1

# pwd -W: Git Bash, where docker.exe needs a Windows path. Plain pwd elsewhere.
here="$(cd "$(dirname "$0")" && { pwd -W 2>/dev/null || pwd; })"
repo="$(cd "${here}/.." && { pwd -W 2>/dev/null || pwd; })"
PYTHON="${PYTHON:-python3}"
ARCH="${ARCH:-amd64}"
BASE="$(sed -n "s|^  ${ARCH}:[[:space:]]*||p" "${repo}/dartec_bootstrap/build.yaml")"
IMAGE="dartec-bootstrap-test:local"
NET="dartec-bootstrap-test-$$"
SUP="dartec-fake-supervisor-$$"
work="$(mktemp -d)"
failures=0

cleanup() {
    docker rm -f "${SUP}" >/dev/null 2>&1 || true
    docker ps -aq --filter "name=dartec-bootstrap-run-$$" | xargs -r docker rm -f >/dev/null 2>&1 || true
    docker network rm "${NET}" >/dev/null 2>&1 || true
    rm -rf "${work}"
}
trap cleanup EXIT

json() { "${PYTHON}" -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
pass() { echo "  PASS  $*"; }
# A failed check shows what the add-on said and which Supervisor calls it made,
# once per run: a failure in CI is otherwise a guess.
shown=""
fail() {
    echo "  FAIL  $*"; failures=$((failures + 1))
    if [ -n "${current:-}" ] && [ "${shown}" != "${current}" ] && [ -f "${current}.log" ]; then
        shown="${current}"
        echo "        --- ${current}: add-on log (last 25 lines)"
        tail -25 "${current}.log" | sed 's/^/        /'
        echo "        --- ${current}: Supervisor calls"
        sed 's/^/        /' "${current}.calls" 2>/dev/null || true
    fi
}
check() { local what="$1"; shift; if "$@"; then pass "${what}"; else fail "${what}"; fi; }

cd "${work}"

echo "== build the add-on image (${ARCH}, from ${BASE})"
docker build -q --build-arg "BUILD_FROM=${BASE}" --build-arg "BUILD_ARCH=${ARCH}" \
    -t "${IMAGE}" "${repo}/dartec_bootstrap" >/dev/null
pass "image builds with the pinned HACS archive"

# shellcheck source=../dartec_bootstrap/hacs.pin
. "${repo}/dartec_bootstrap/hacs.pin"

# --- the archives -------------------------------------------------------------
docker create --name "dartec-bootstrap-run-$$-extract" "${IMAGE}" >/dev/null
docker cp "dartec-bootstrap-run-$$-extract:/opt/dartec/hacs.zip" genuine.zip
docker rm "dartec-bootstrap-run-$$-extract" >/dev/null
"${PYTHON}" - <<'EOF'
import shutil, zipfile
# The advisory's proof of concept: a HACS-shaped archive carrying other code.
with zipfile.ZipFile("forged.zip", "w") as z:
    z.writestr("manifest.json", '{"domain":"hacs","version":"2.0.5"}')
    z.writestr("__init__.py", "MARKER = 'untrusted archive code'\n")
# The quieter version of the same attack: the genuine release, working as
# normal, with one module added to it.
shutil.copy("genuine.zip", "backdoored.zip")
with zipfile.ZipFile("backdoored.zip", "a") as z:
    z.writestr("payload.py", "MARKER = 'untrusted archive code'\n")
EOF
: > empty.zip

# --- one provisioning run ---------------------------------------------------------
docker network create --internal "${NET}" >/dev/null
docker create --name "${SUP}" --network "${NET}" --network-alias supervisor \
    python:3.12-alpine sh -c 'mkdir -p /log && python /fake_supervisor.py' >/dev/null
docker cp "${here}/fake_supervisor.py" "${SUP}:/fake_supervisor.py"
docker start "${SUP}" >/dev/null
# The add-on finds it through /etc/hosts, not Docker's DNS: on GitHub's runners
# the alias did not resolve on an --internal network, the add-on read no
# options, and every run took the clean-up-only path.
SUP_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${SUP}")"
for _ in $(seq 1 30); do
    docker exec "${SUP}" python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1/ready')" \
        >/dev/null 2>&1 && break
    sleep 1
done

mkdir -p config/.storage data
cat > config/.storage/core.config_entries <<'EOF'
{"version":1,"minor_version":5,"key":"core.config_entries","data":{"entries":[
 {"entry_id":"01TESTENTRY0000000000000000","version":1,"minor_version":1,"domain":"sun",
  "title":"Sun","data":{},"options":{},"source":"import","unique_id":null,"disabled_by":null}
]}}
EOF

# run <name> [archive]: one run of the add-on with a fresh config directory and
# a fresh fake Supervisor log. Leaves out/<name>/ and out/<name>.calls behind.
run() {
    local name="$1" archive="${2:-}" cont="dartec-bootstrap-run-$$-$1" code=0
    docker exec "${SUP}" sh -c ': > /log/calls'
    docker create --name "${cont}" --network "${NET}" --add-host "supervisor:${SUP_IP}" \
        -e SUPERVISOR_TOKEN=test "${IMAGE}" >/dev/null
    docker cp config/. "${cont}:/homeassistant"
    docker cp data/. "${cont}:/data"     # the Supervisor mounts /data; nothing else creates it
    if [ -n "${archive}" ]; then
        docker cp "${archive}" "${cont}:/opt/dartec/hacs.zip"
    fi
    docker start -a "${cont}" > "${name}.log" 2>&1 || code=$?
    mkdir -p "out/${name}"
    docker cp "${cont}:/homeassistant/." "out/${name}"
    docker exec "${SUP}" cat /log/calls > "${name}.calls"
    docker rm "${cont}" >/dev/null
    echo "${code}" > "${name}.code"
    current="${name}"
}

no_core_stop() { ! grep -q '/core/stop' "$1.calls"; }
entries_untouched() { cmp -s config/.storage/core.config_entries "out/$1/.storage/core.config_entries"; }
nothing_unpacked() { [ ! -e "out/$1/custom_components/hacs" ] && [ ! -e "out/$1/.dartec-bootstrap-hacs" ]; }
refused_in_log() { grep -q 'Refused the HACS archive' "$1.log"; }
failed() { [ "$(cat "$1.code")" != "0" ]; }
# A run that never got its run_token does nothing and exits 0; that is not a pass.
provisioning_run() { grep -q "GET /addons/self/options/config" "$1.calls" && ! grep -q "clean-up only" "$1.log"; }

# The network is --internal: the add-on reaches the fake Supervisor and nothing
# else, so a run that tried to fetch anything from GitHub would fail here.
echo "== the genuine, pinned archive, with no route to the internet"
run genuine
check "the add-on read a fresh run_token"      provisioning_run genuine
check "run succeeds"                          [ "$(cat genuine.code)" = "0" ]
[ "$(cat genuine.code)" = "0" ] || tail -20 genuine.log | sed "s/^/        /"
check "HACS ${HACS_VERSION} is in custom_components/hacs" \
    [ "$(json out/genuine/custom_components/hacs/manifest.json 'd["version"]')" = "${HACS_VERSION}" ]
check "no staging directory is left behind"   [ ! -e out/genuine/.dartec-bootstrap-hacs ]
check "the hacs config entry was written" \
    [ "$(json out/genuine/.storage/core.config_entries 'any(e["domain"] == "hacs" for e in d["data"]["entries"])')" = "True" ]
check "Core was stopped and started" \
    bash -c 'grep -q "POST /core/stop" genuine.calls && grep -q "POST /core/start" genuine.calls'

for attack in forged backdoored empty; do
    echo "== a ${attack} archive in place of the release"
    run "${attack}" "${attack}.zip"
    check "the add-on read a fresh run_token"     provisioning_run "${attack}"
    check "run fails"                             failed "${attack}"
    check "the log says the archive was refused"  refused_in_log "${attack}"
    check "nothing is unpacked"                   nothing_unpacked "${attack}"
    check "no payload anywhere in the config"     bash -c "! grep -rqs 'untrusted archive code' out/${attack}"
    check "the config entries are untouched"      entries_untouched "${attack}"
    check "Core was never stopped"                no_core_stop "${attack}"
done
grep -h 'Refused the HACS archive' forged.log | sed 's/^/        /'

echo "== the pin itself"
pin_refused() {
    docker run --rm --entrypoint bash "${IMAGE}" -c \
        ". /opt/dartec/hacs.sh; HACS_REPO='$1' HACS_VERSION='$2' HACS_SHA256='$3'; ! hacs_check_pin >/dev/null"
}
good_sha="${HACS_SHA256}"
check "a branch is refused as a version"       pin_refused hacs/integration main "${good_sha}"
check "a version with a v prefix is refused"   pin_refused hacs/integration v2.0.5 "${good_sha}"
check "another repository is refused"          pin_refused someone/integration 2.0.5 "${good_sha}"
check "a short checksum is refused"            pin_refused hacs/integration 2.0.5 "${good_sha:0:40}"
check "an uppercase checksum is refused"       pin_refused hacs/integration 2.0.5 "$(echo "${good_sha}" | tr a-f A-F)"

echo "== the image cannot be built around a wrong pin"
bad_build() {
    rm -rf ctx && cp -r "${repo}/dartec_bootstrap" ctx
    sed -i "s|^$1=.*|$1=\"$2\"|" ctx/hacs.pin
    ! docker build -q --no-cache --build-arg "BUILD_FROM=${BASE}" --build-arg "BUILD_ARCH=${ARCH}" \
        -t dartec-bootstrap-test:bad ctx >/dev/null 2>&1
}
check "a checksum that is not the release's stops the build" \
    bad_build HACS_SHA256 "$(printf '%064d' 0)"
check "a branch name stops the build"          bad_build HACS_VERSION main
docker rmi dartec-bootstrap-test:bad >/dev/null 2>&1 || true

echo
if [ "${failures}" -eq 0 ]; then
    echo "all checks passed"
else
    echo "${failures} check(s) failed"; exit 1
fi

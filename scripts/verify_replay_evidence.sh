#!/bin/sh
# verify_replay_evidence.sh [EVIDENCE]: verdict on the kernel replay of the alpo.ge archive, read only from each
# host's own files under EVIDENCE (default: the evidence/ directory beside this script's parent).
# FAIL line for each check that does not hold:
#  - modules/leaves.txt + modules/parents.txt hold 175,187 distinct names, equal to the module set of
#    olean-manifest.sha256.xz;
#  - every results line reads "PASS NAME" or "FAIL NAME rc=N";
#  - every module has a PASS line on at least one host (results.txt or recheck/results.txt);
#  - no err file (one per module a host replayed in its last loop, empty on a pass) mentions "(kernel)", and no FAIL
#    line names a listed module; a FAIL line naming no listed module is reported as a harness artifact;
#  - each host's manifest-digest.txt (the line the host wrote after hashing its own .olean files) names 175,187 files
#    and the sha256 of olean-manifest.sha256.xz's content;
#  - each host's driver-switch.txt records "calibration ok" for alpocheck ad3ec835...c60 and an agreement line with
#    equal counts.
# Prints per-host counts and the leanchecker/driver split, then VERDICT PASS (exit 0) or VERDICT FAIL (exit 1).
set -eu
R=${1:-$(cd "$(dirname "$0")/.." && pwd)/evidence}
DRV=ad3ec835ff683763d7c431ae67b752899ebb30e5a9404270fc674bfd6f4b7c60
N=175187
T=$(mktemp -d); trap 'rm -r "$T"' EXIT
bad=0
fail() { echo "FAIL $*"; bad=1; }
cat "$R/modules/leaves.txt" "$R/modules/parents.txt" | sort > "$T/mods"
[ "$(wc -l < "$T/mods")" -eq "$N" ] || fail "module list has $(wc -l < "$T/mods") lines, expected $N"
[ "$(uniq "$T/mods" | wc -l)" -eq "$N" ] || fail "module list holds duplicates"
xz -dc "$R/olean-manifest.sha256.xz" > "$T/manifest"
MD=$(sha256sum "$T/manifest" | cut -c1-64)
sed -e 's|^[0-9a-f]*  \./||' -e 's|\.olean$||' -e 's|/|.|g' "$T/manifest" | sort > "$T/manmods"
cmp -s "$T/mods" "$T/manmods" || fail "module list differs from the manifest's module set ($(comm -3 "$T/mods" "$T/manmods" | wc -l) names)"
echo "olean manifest: $(wc -l < "$T/manifest") files, sha256 $MD"
: > "$T/pass"; : > "$T/fails"; : > "$T/lpass"; : > "$T/kern"
for d in "$R"/hosts/*/; do
  d=${d%/}; name=$(basename "$d")
  for f in results.txt driver-results.txt driver-switch.txt manifest-digest.txt; do [ -s "$d/$f" ] || fail "$name: missing or empty $f"; done
  files="$d/results.txt"; [ -f "$d/recheck/results.txt" ] && files="$files $d/recheck/results.txt"
  # shellcheck disable=SC2086
  if cat $files | grep -v -E '^(PASS [^ ]+|FAIL [^ ]+ rc=[0-9]+)$' > "$T/odd"; then fail "$name: $(wc -l < "$T/odd") malformed results lines, first: $(head -1 "$T/odd")"; fi
  # shellcheck disable=SC2086
  cat $files | awk '$1=="PASS"{print $2}' >> "$T/pass"
  # shellcheck disable=SC2086
  cat $files | awk -v h="$name" '$1=="FAIL"{print $2, h}' >> "$T/fails"
  awk '$1=="PASS"{print $2}' "$d/driver-results.txt" | sort -u > "$T/dr"
  awk '$1=="PASS"{print $2}' "$d/results.txt" | sort -u | comm -23 - "$T/dr" >> "$T/lpass"
  ne=0; nn=0
  if [ -d "$d/err" ]; then
    ne=$(find "$d/err" -type f | wc -l); nn=$(find "$d/err" -type f -size +0 | wc -l)
    find "$d/err" -type f -size +0 -exec grep -l -F '(kernel)' {} + 2> /dev/null | sed "s|^|$name |" >> "$T/kern" || true
  fi
  p=$(awk '$1=="PASS"' "$d/results.txt" | sort -u | wc -l); dp=$(wc -l < "$T/dr")
  # shellcheck disable=SC2086
  echo "host $name: PASS $p (driver $dp, leanchecker $((p - dp))), FAIL $(awk '$1=="FAIL"' $files | wc -l), err files $ne (nonempty $nn)"
  grep -q "calibration ok: .*alpocheck sha256 $DRV" "$d/driver-switch.txt" || fail "$name: no calibration ok line for alpocheck $DRV"
  ag=$(grep -E 'agreement' "$d/driver-switch.txt" | head -1)
  echo "$ag" | grep -q -E ' ([0-9]+) of \1 ' || fail "$name: agreement line missing or unequal: $ag"
  grep -q -E "^olean manifest $N files sha256 $MD( |$)" "$d/manifest-digest.txt" || fail "$name: manifest digest differs: $(head -1 "$d/manifest-digest.txt")"
done
sort -u "$T/pass" > "$T/passu"
comm -23 "$T/mods" "$T/passu" > "$T/missing"
[ -s "$T/missing" ] && fail "$(wc -l < "$T/missing") modules without a PASS line, first: $(head -1 "$T/missing")"
comm -13 "$T/mods" "$T/passu" > "$T/extra"
[ -s "$T/extra" ] && fail "$(wc -l < "$T/extra") PASS names outside the module list, first: $(head -1 "$T/extra")"
echo "coverage: $(comm -12 "$T/mods" "$T/passu" | wc -l) of $N modules have a PASS line"
sort -u "$T/lpass" > "$T/lpassu"
echo "split: $(comm -12 "$T/mods" "$T/lpassu" | wc -l) modules with a leanchecker PASS, $(comm -23 "$T/passu" "$T/lpassu" | comm -12 "$T/mods" - | wc -l) with driver PASS lines only"
if [ -s "$T/kern" ]; then while read -r h f; do fail "kernel message in $h err file $(basename "$f")"; done < "$T/kern"; fi
sort -u "$T/fails" > "$T/failu"
while read -r m h; do
  if grep -qxF "$m" "$T/mods"; then fail "FAIL line for listed module $m on $h"
  else echo "harness artifact: FAIL line for $m on $h, a name outside the module list"; fi
done < "$T/failu"
[ "$bad" = 0 ] && { echo "VERDICT PASS"; exit 0; }
echo "VERDICT FAIL"; exit 1

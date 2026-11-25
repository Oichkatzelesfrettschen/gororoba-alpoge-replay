#!/bin/sh
# verify_module_records.sh [EVIDENCE]: verdict on the per-module record table of the alpo.ge archive replay,
# evidence/module-records.tsv.xz, against the files it summarizes. FAIL line for each check that does not hold:
#  - the header is the documented ten columns, and the table has one row per module, sorted and distinct, equal
#    to the module list of modules/leaves.txt + modules/parents.txt (175,187 names), with kind matching the list;
#  - every field has its type: build_status in {ok, warn, info, replayed}, job_seconds a decimal or "-", the
#    counts digits, errors 0;
#  - replay_hosts, replay_driver_hosts and replay_fail_lines equal what each host's results.txt, recheck/results.txt,
#    driver-results.txt and recheck/driver-results.txt give, recomputed here, and every module has a PASS host;
#  - build/build-log-summary.txt agrees with the table (module count, Built headers per status, no sorry warning)
#    and build/warning-classes.tsv sums to the table's warning count.
# Prints the counts, then VERDICT PASS (exit 0) or VERDICT FAIL (exit 1).
set -eu
LC_ALL=C
export LC_ALL
R=${1:-$(cd "$(dirname "$0")/.." && pwd)/evidence}
N=175187
T=$(mktemp -d); trap 'rm -r "$T"' EXIT
bad=0
fail() { echo "FAIL $*"; bad=1; }
TAB=$(printf '\t')
HEAD="module${TAB}kind${TAB}build_status${TAB}job_seconds${TAB}warnings${TAB}infos${TAB}errors${TAB}replay_hosts${TAB}replay_driver_hosts${TAB}replay_fail_lines"
xz -dc "$R/module-records.tsv.xz" > "$T/rec"
[ "$(head -1 "$T/rec")" = "$HEAD" ] || fail "unexpected header: $(head -1 "$T/rec")"
tail -n +2 "$T/rec" > "$T/body"
rows=$(wc -l < "$T/body")
[ "$rows" -eq "$N" ] || fail "table has $rows rows, expected $N"
cut -f1 "$T/body" > "$T/names"
sort -c -u "$T/names" 2> /dev/null || fail "module column is not sorted and distinct"
cat "$R/modules/leaves.txt" "$R/modules/parents.txt" | sort > "$T/mods"
cmp -s "$T/mods" "$T/names" || fail "module column differs from the module list ($(comm -3 "$T/mods" "$T/names" | wc -l) names)"
awk -F'\t' 'FNR == NR { p[$1] = 1; next }
  { k = ($1 in p) ? "parent" : "leaf"; if ($2 != k) print $1 " has kind " $2 ", expected " k }' \
  "$R/modules/parents.txt" "$T/body" > "$T/kindbad"
[ -s "$T/kindbad" ] && fail "$(wc -l < "$T/kindbad") kind mismatches, first: $(head -1 "$T/kindbad")"
awk -F'\t' '
  NF != 10 { print "line " NR " has " NF " fields"; next }
  $3 !~ /^(ok|warn|info|replayed)$/ { print $1 ": build_status " $3 }
  $4 !~ /^(-|[0-9]+(\.[0-9])?)$/ { print $1 ": job_seconds " $4 }
  $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ || $7 !~ /^[0-9]+$/ || $10 !~ /^[0-9]+$/ { print $1 ": a count is not digits" }
  $7 != 0 { print $1 ": build errors " $7 }
  $8 == "-" { print $1 ": no replay PASS host" }
  { st[$3]++; w += $5 }
  END { printf "STATUS ok %d warn %d info %d replayed %d warnings %d\n", st["ok"], st["warn"], st["info"], st["replayed"], w > "/dev/stderr" }
' "$T/body" > "$T/fieldbad" 2> "$T/status"
[ -s "$T/fieldbad" ] && fail "$(wc -l < "$T/fieldbad") field problems, first: $(head -1 "$T/fieldbad")"
: > "$T/rp"
for d in "$R"/hosts/*/; do
  d=${d%/}; h=$(basename "$d")
  for f in results.txt recheck/results.txt; do
    if [ -f "$d/$f" ]; then awk -v h="$h" '$1 == "PASS" { print $2 "\t" h "\tP" } $1 == "FAIL" { print $2 "\t" h "\tF" }' "$d/$f" >> "$T/rp"; fi
  done
  for f in driver-results.txt recheck/driver-results.txt; do
    if [ -f "$d/$f" ]; then awk -v h="$h" '$1 == "PASS" { print $2 "\t" h "\tD" }' "$d/$f" >> "$T/rp"; fi
  done
done
sort "$T/rp" | awk -F'\t' '
  function flush() { if (m != "") print m "\t" (ph == "" ? "-" : ph) "\t" (dh == "" ? "-" : dh) "\t" nf }
  $1 != m { flush(); m = $1; ph = ""; dh = ""; nf = 0; lp = ""; ld = "" }
  $3 == "P" && $2 != lp { ph = ph (ph == "" ? "" : ",") $2; lp = $2 }
  $3 == "D" && $2 != ld { dh = dh (dh == "" ? "" : ",") $2; ld = $2 }
  $3 == "F" { nf++ }
  END { flush() }' > "$T/grp"
awk -F'\t' 'FNR == NR { ph[$1] = $2; dh[$1] = $3; nf[$1] = $4; next }
  { print $1 "\t" ($1 in ph ? ph[$1] : "-") "\t" ($1 in dh ? dh[$1] : "-") "\t" ($1 in nf ? nf[$1] : 0) }' "$T/grp" "$T/names" > "$T/want"
cut -f1,8,9,10 "$T/body" > "$T/have"
cmp -s "$T/want" "$T/have" || fail "replay columns differ from the host files in $(diff "$T/want" "$T/have" | grep -c '^<') rows, first: $(diff "$T/want" "$T/have" | grep -m1 '^<' || true)"
S=$R/build/build-log-summary.txt
val() { awk -v k="$1" '$0 ~ "^" k " " { sub("^" k " ", ""); print; exit }' "$S"; }
[ "$(val modules)" = "$N" ] || fail "summary modules is $(val modules), expected $N"
[ "$(val sorry_warnings)" = 0 ] || fail "summary records $(val sorry_warnings) sorry warnings"
okn=$(awk '$1 == "STATUS" { print $3 }' "$T/status"); warnn=$(awk '$1 == "STATUS" { print $5 }' "$T/status")
infon=$(awk '$1 == "STATUS" { print $7 }' "$T/status"); repn=$(awk '$1 == "STATUS" { print $9 }' "$T/status")
wsum=$(awk '$1 == "STATUS" { print $11 }' "$T/status")
[ "$(val 'headers ok Built')" = "$okn" ] || fail "summary ok Built headers $(val 'headers ok Built'), table $okn"
[ "$(val 'headers warn Built')" = "$warnn" ] || fail "summary warn Built headers $(val 'headers warn Built'), table $warnn"
[ "$(val 'headers info Built')" = "$infon" ] || fail "summary info Built headers $(val 'headers info Built'), table $infon"
cls=$(awk -F'\t' 'NR > 1 { s += $2 } END { print s + 0 }' "$R/build/warning-classes.tsv")
[ "$cls" = "$wsum" ] || fail "warning-classes.tsv sums to $cls, table to $wsum"
echo "records: $rows modules; build status ok $okn, warn $warnn, info $infon, replayed-only $repn; $wsum warnings in $(($(wc -l < "$R/build/warning-classes.tsv") - 1)) classes"
echo "replay: $(awk -F'\t' '$8 != "-"' "$T/body" | wc -l) modules with a PASS host, $(awk -F'\t' '$9 != "-"' "$T/body" | wc -l) with a driver PASS host"
[ "$bad" = 0 ] && { echo "VERDICT PASS"; exit 0; }
echo "VERDICT FAIL"; exit 1

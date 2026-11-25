#!/bin/sh
# cal_module_records.sh [EVIDENCE]: calibrates verify_module_records.sh. The evidence must give VERDICT PASS; six
# mutants, each a symlink copy with one defect, must give VERDICT FAIL with the matching message. Ends with
# CAL-PASS or CAL-FAIL.
set -eu
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")" && pwd); R=${1:-$HERE/../evidence}; R=$(cd "$R" && pwd); V=$HERE/verify_module_records.sh
T=$(mktemp -d); trap 'rm -r "$T"' EXIT
ok=1
expect() {
  c=$1; want=$2; pat=$3
  if sh "$V" "$T/$c" > "$T/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ] && grep -q -e "$pat" "$T/out"; then echo "ok $c: $got ($(grep -m1 -e "$pat" "$T/out"))"
  else echo "BAD $c: got $got, wanted $want with /$pat/"; tail -5 "$T/out"; ok=0; fi
}
mk() { cp -as "$R" "$T/$1"; }
edit_table() {
  c=$1; shift
  xz -dc "$R/module-records.tsv.xz" | awk -F'\t' -v OFS='\t' "$@" | xz -1 -c > "$T/table.xz"
  rm "$T/$c/module-records.tsv.xz"; mv "$T/table.xz" "$T/$c/module-records.tsv.xz"
}
edit_file() {
  c=$1; f=$2; shift 2
  awk "$@" "$R/$f" > "$T/edit.txt"
  rm "$T/$c/$f"; mv "$T/edit.txt" "$T/$c/$f"
}
m=$(sed -n 5p "$R/modules/leaves.txt")
mk real; expect real pass 'VERDICT PASS'
mk host; edit_table host -v m="$m" '$1 == m { $8 = "workstation,cloud-vm-4" } { print }'
expect host fail 'replay columns differ'
mk nopass; edit_table nopass -v m="$m" '$1 == m { $8 = "-" } { print }'
expect nopass fail 'no replay PASS host'
mk builderr; edit_table builderr -v m="$m" '$1 == m { $7 = 1 } { print }'
expect builderr fail 'build errors 1'
mk droprow; edit_table droprow -v m="$m" '$1 != m { print }'
expect droprow fail 'table has 175186 rows'
mk sorry; edit_file sorry build/build-log-summary.txt '$1 == "sorry_warnings" { $2 = 1 } { print }'
expect sorry fail 'summary records 1 sorry warnings'
mk classes; edit_file classes build/warning-classes.tsv -F'\t' -v OFS='\t' '$1 == "other" { $2 = $2 + 1 } { print }'
expect classes fail 'warning-classes.tsv sums to'
[ "$ok" = 1 ] && echo CAL-PASS || { echo CAL-FAIL; exit 1; }

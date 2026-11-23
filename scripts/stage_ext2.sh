#!/bin/sh
# stage_ext2.sh: independent-kernel check of the closure of the five Main theorems on one 256 GB GCP VM.
# Order: failsafe power-off timer; tools; calibration, which stops the run unless every checker rejects the known-bad
# export and accepts the known-good one; the export, sampled every 30 s into profile.tsv; an export gate (exit 0 and a
# final line that parses as JSON); then con-leche --verified and nanoda_bin (strict, three permitted axioms), together
# when 2.3 x the export size fits in MemAvailable and one after the other otherwise, with the name, line-count and
# digest checks beside them. con-ron is left out: its u32 arena declined a 13.3 GB export (exit 2). Every step logs
# to $E/summary.txt; the evidence (exports excluded) goes to the bucket, the summary ends with EXT-END, and the VM
# powers off.
set -u
B=gs://BUCKET; E=$HOME/alpo/stage-ext; S=$E/summary.txt; P=$E/profile.tsv
FAILSAFE_MIN=${FAILSAFE_MIN:-600}
THMS="riemannHypothesis riemannZeta_eq_zero_re LFunction_ne_zero_of_half_lt_re LFunction_eq_zero_re LFunction_eq_zero_re_of_isPrimitive"
export PATH=$HOME/.elan/bin:$PATH
mkdir -p "$E/cal"
NP=$(nproc)
log() { echo "$(date -u +%FT%TZ) $*" >> "$S"; }
finish() {
  gcloud storage rsync -r -x '.*\.ndjson$' "$E" "$B/evidence/stage-ext2" > /dev/null 2>&1 && log "evidence copied to evidence/stage-ext2" || log "FAIL evidence copy"
  echo EXT-END >> "$S"
  gcloud storage cp "$S" "$B/evidence/stage-ext2/summary.txt" > /dev/null 2>&1
  sudo poweroff
  exit "$1"
}
# sample STEP PID PATTERN [FILE]: every 30 s, one profile row for the processes whose command name is PATTERN, while
# PID lives; stops the step when the root file system has under 10 GiB free.
sample() {
  st=$1; pid=$2; pat=$3; f=${4:-}
  # shellcheck disable=SC2046
  set -- $(awk '/^cpu /{print $2+$3, $6, $2+$3+$4+$5+$6+$7+$8}' /proc/stat); u0=$1; w0=$2; t0=$3
  while kill -0 "$pid" 2> /dev/null; do
    sleep 30
    # shellcheck disable=SC2046
    set -- $(awk '/^cpu /{print $2+$3, $6, $2+$3+$4+$5+$6+$7+$8}' /proc/stat); u1=$1; w1=$2; t1=$3
    pids=$(pgrep -x "$pat" | tr '\n' ' ')
    pss=0; rss=0; flt=0; cpu=0
    for q in $pids; do
      a=$(awk '/^Pss_Anon:/{print $2}' "/proc/$q/smaps_rollup" 2> /dev/null); pss=$((pss + ${a:-0}))
      a=$(awk '/^VmRSS:/{print $2}' "/proc/$q/status" 2> /dev/null); rss=$((rss + ${a:-0}))
      # shellcheck disable=SC2046
      set -- $(awk '{print $12, $14 + $15}' "/proc/$q/stat" 2> /dev/null); flt=$((flt + ${1:-0})); cpu=$((cpu + ${2:-0}))
    done
    fb=0; [ -n "$f" ] && fb=$(stat -c %s "$f" 2> /dev/null || echo 0)
    ma=$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)
    df=$(df --output=avail -BG "$HOME" | tail -1 | tr -dc 0-9)
    us=$(awk -v a="$u0" -v b="$u1" -v c="$t0" -v d="$t1" 'BEGIN{printf "%.1f", (d>c)?100*(b-a)/(d-c):0}')
    io=$(awk -v a="$w0" -v b="$w1" -v c="$t0" -v d="$t1" 'BEGIN{printf "%.1f", (d>c)?100*(b-a)/(d-c):0}')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$st" "$fb" $((pss / 1024)) $((rss / 1024)) "$flt" $((cpu / 100)) "$us" "$io" "$ma" "$df" >> "$P"
    u0=$u1; w0=$w1; t0=$t1
    if [ "$df" -lt 10 ]; then pkill -x "$pat"; log "guard: $st stopped at ${df}G free"; fi
  done
}
# step NAME PATTERN FILE CMD...: runs CMD under GNU time with its profile; logs exit status, wall, CPU and peak RSS.
step() {
  n=$1; pat=$2; f=$3; shift 3
  /usr/bin/time -f "%e s wall, %U user, %S sys, %M KiB peak" -o "$E/$n.time" "$@" &
  pid=$!; sample "$n" "$pid" "$pat" "$f" &
  wait "$pid"; rc=$?
  log "$n rc=$rc $(cat "$E/$n.time" 2> /dev/null | tail -1) pss_anon_peak_mb $(awk -F'\t' -v s="$n" '$2==s && $4>m{m=$4} END{print m+0}' "$P")"
  return "$rc"
}
sudo shutdown -h +"$FAILSAFE_MIN" > /dev/null 2>&1
log "stage_ext2 start on $(hostname -s); nproc $NP; MemTotal $(awk '/^MemTotal:/{print int($2/1048576)}' /proc/meminfo) GiB; free $(df --output=avail -BG "$HOME" | tail -1 | tr -dc 0-9)G; failsafe power-off in $FAILSAFE_MIN min"
[ -f "$P" ] || printf 'utc\tstep\tfile_bytes\tpss_anon_mb\trss_mb\tmajflt\tcpu_s\tsys_user_pct\tsys_iowait_pct\tmemavail_mb\tdisk_free_gb\n' > "$P"
[ -f "$E/main5.ndjson" ] && log "earlier partial export: $(stat -c '%s bytes, mtime %y' "$E/main5.ndjson"); the new export overwrites it"
gcloud storage cp "$B/in/verifiers/lean4export" "$B/in/verifiers/external_kernel_export.py" "$E/" > /dev/null 2>&1 && chmod +x "$E/lean4export" || { log "FAIL fetch tools"; finish 1; }
# Calibration exports are dependency closures, like the main export: cal-bad2 holds ReplayFixture.bogus (False :=
# True.intro, added without the kernel), cal-good2 the closure of GlobalTheory.isogeny_torsion_bij (22,234 declarations,
# three standard axioms). A whole-environment export declares sorryAx and Lean.trustCompiler, which the strict nanoda
# configuration refuses before any type check.
{ gcloud storage cp "$B/in/verifiers/cal-bad2.ndjson" "$E/cal/cal-bad.ndjson" && gcloud storage cp "$B/in/verifiers/cal-good2.ndjson" "$E/cal/cal-good.ndjson"; } > /dev/null 2>&1 || { log "FAIL fetch calibration exports"; finish 1; }
log "calibration exports: $(sha256sum "$E/cal/cal-bad.ndjson" "$E/cal/cal-good.ndjson" | cut -c1-16 | tr '\n' ' ')"
elan toolchain install leanprover/lean4:v4.35.0 > "$E/elan.log" 2>&1; X=$HOME/.elan/toolchains/leanprover--lean4---v4.35.0/bin
for t in con-leche nanoda_bin; do [ -x "$X/$t" ] || { log "FAIL missing $X/$t"; finish 1; }; done
log "tools: lean4export sha256 $(sha256sum "$E/lean4export" | cut -c1-16); toolchain 4.35.0 $(sha256sum "$X/con-leche" "$X/nanoda_bin" | cut -c1-16 | tr '\n' ' ')"
cfg() { printf '{"export_file_path": "%s", "permitted_axioms": ["propext", "Classical.choice", "Quot.sound"], "unpermitted_axiom_hard_error": true, "nat_extension": true, "string_extension": true, "num_threads": %s}\n' "$1" "$3" > "$2"; }
ok=1
for x in bad good; do
  f=$E/cal/cal-$x.ndjson
  "$X/con-leche" --verified --jobs="$NP" "$f" > "$E/cal-$x-con-leche.log" 2>&1; r1=$?
  cfg "$f" "$E/cal-$x-nanoda.json" "$NP"; "$X/nanoda_bin" "$E/cal-$x-nanoda.json" > "$E/cal-$x-nanoda.log" 2>&1; r2=$?
  log "calibration $x: con-leche rc=$r1 nanoda rc=$r2"
  if [ "$x" = bad ]; then [ "$r1" -ne 0 ] && [ "$r2" -ne 0 ] || ok=0; else [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || ok=0; fi
done
[ "$ok" = 1 ] || { log "FAIL calibration: a checker accepted the known-bad export or refused the known-good one"; finish 1; }
cd "$HOME/alpo/src/lean" || { log "FAIL no archive tree"; finish 1; }
# shellcheck disable=SC2086
step export lean4export "$E/main5.ndjson" sh -c 'lake env "$1" Main -- $2 > "$3" 2> "$4"' sh "$E/lean4export" "$THMS" "$E/main5.ndjson" "$E/export.err"; rc=$?
M=$E/main5.ndjson; sz=$(stat -c %s "$M" 2> /dev/null || echo 0)
tail -n 1 "$M" | python3 -c 'import json, sys; json.loads(sys.stdin.read())' 2> /dev/null; lastok=$?
log "export bytes $sz exit $rc last-line-json $([ "$lastok" = 0 ] && echo ok || echo bad)"
[ "$rc" = 0 ] && [ "$lastok" = 0 ] && [ "$sz" -gt 0 ] || { log "FAIL export incomplete; checkers not run"; tail -c 2000 "$E/export.err" >> "$S"; finish 1; }
( printf 'lines %s\n' "$(wc -l < "$M")" > "$E/main5.lines"; sha256sum "$M" | cut -d' ' -f1 > "$E/main5.sha256" ) &
bg1=$!
# shellcheck disable=SC2086
python3 "$E/external_kernel_export.py" "$M" $THMS > "$E/namecheck.log" 2>&1 &
bg2=$!
ma=$(awk '/^MemAvailable:/{print $2 * 1024}' /proc/meminfo)
if awk -v e="$sz" -v m="$ma" 'BEGIN{exit !(2.3 * e < m)}'; then
  h=$((NP / 2)); log "checkers together, $h threads each (2.3 x $sz < MemAvailable $ma)"
  cfg "$M" "$E/main5-nanoda.json" "$h"
  step main5-con-leche con-leche "" "$X/con-leche" --verified --jobs="$h" "$M" > "$E/main5-con-leche.log" 2>&1 &
  c1=$!
  step main5-nanoda nanoda_bin "" "$X/nanoda_bin" "$E/main5-nanoda.json" > "$E/main5-nanoda.log" 2>&1 &
  c2=$!
  wait "$c1"; wait "$c2"
else
  log "checkers one after the other, $NP threads (2.3 x $sz >= MemAvailable $ma)"
  cfg "$M" "$E/main5-nanoda.json" "$NP"
  step main5-con-leche con-leche "" "$X/con-leche" --verified --jobs="$NP" "$M" > "$E/main5-con-leche.log" 2>&1
  step main5-nanoda nanoda_bin "" "$X/nanoda_bin" "$E/main5-nanoda.json" > "$E/main5-nanoda.log" 2>&1
fi
wait "$bg1"; wait "$bg2"
log "export $(cat "$E/main5.lines") sha256 $(cat "$E/main5.sha256")"
log "namecheck: $(tail -n 2 "$E/namecheck.log" | tr '\n' ' ')"
log "con-leche: $(tail -n 2 "$E/main5-con-leche.log" | tr '\n' ' ')"
log "nanoda: $(tail -n 2 "$E/main5-nanoda.log" | tr '\n' ' ')"
finish 0

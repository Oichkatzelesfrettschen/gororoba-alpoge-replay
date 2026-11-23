#!/bin/sh
# lc_run.sh MODLIST JOBS THREADS OUT, version 2: kernel replay of each module of MODLIST, one alpocheck process per
# module, run from the Lake root. alpocheck (alpocheck/AlpoCheck.lean) calls the replay function of Lean 4.33.1's
# leanchecker (replayFromImports, copied verbatim) on exactly the named module; leanchecker itself first walks every
# .olean of the search path to resolve its argument as a module-name prefix, which took 117 of 123 s per module
# (measured on workstation, 2026-11-23). The job count is the content of lc.jobs beside this script when that file
# exists, else JOBS; THREADS is ignored (one kernel thread per module). Each verdict appends "PASS M" or "FAIL M rc=N"
# (N from 1 to 128) to OUT/results.txt and to OUT/driver-results.txt; an exit by signal (N above 128) appends
# "SIG M rc=N" to OUT/driver-signals.txt only, so the module stays unchecked and a later chunk retries it. The
# module's output stays in OUT/err/M for a FAIL or a SIG.
set -u
list=$1; jobs=$2; out=$4; here=$(cd "$(dirname "$0")" && pwd)
[ -s "$here/lc.jobs" ] && jobs=$(cat "$here/lc.jobs")
mkdir -p "$out/err"
LEAN_PATH=$(lake env printenv LEAN_PATH) || exit 1
LEAN_SYSROOT=$(lake env printenv LEAN_SYSROOT) || exit 1
export LEAN_PATH LEAN_SYSROOT LEAN_NUM_THREADS=1 OUT="$out" X="$here/alpocheck"
xargs -d '\n' -P "$jobs" -I{} sh -c '"$X" "$1" > "$OUT/err/$1" 2>&1; rc=$?; if [ "$rc" = 0 ]; then l="PASS $1"; rm -f "$OUT/err/$1"; elif [ "$rc" -gt 128 ]; then echo "SIG $1 rc=$rc" >> "$OUT/driver-signals.txt"; exit 0; else l="FAIL $1 rc=$rc"; fi; echo "$l" >> "$OUT/results.txt"; echo "$l" >> "$OUT/driver-results.txt"' _ {} < "$list"

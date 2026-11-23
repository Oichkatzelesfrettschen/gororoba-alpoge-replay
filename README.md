# Kernel replay of Levent Alpöge's Lean archive for the Riemann hypothesis

Levent Alpöge published, at [alpo.ge](https://alpo.ge/), a Lean 4 archive (`lean.tar.gz.part01..14`) and a note
stating that it proves the Riemann hypothesis. The archive, its mathematics and its note are his work. This repository
holds none of the archive's source files: `fetch_archive.sh` downloads them from alpo.ge and checks their sha256.
The evidence does carry facts derived from the archive: its module names (the module list and the .olean path
list), declaration names in the logs, and the statements of the five theorems as the audit restates them.

This repository records an independent machine check of that archive, run from 2026-11-20 to 2026-11-23: the
build, an audit of the five statements, a replay of every module through Lean's kernel, and a check of the five
theorems' complete dependency closure by an independently written kernel. `CERTIFICATION.md` holds every number.

## Result

| Check | Outcome |
|---|---|
| Build (Lean 4.33.1, Mathlib 0df444a3) | 175,187 modules, "Build completed successfully" |
| Statement audit (`audit/GororobaAudit.lean`) | two theorems state the Riemann hypothesis (Mathlib's `RiemannHypothesis` and the zeros-on-the-line form) and three state it for Dirichlet L-functions, each matched to its standard form by `Iff.rfl`; axioms: propext, Classical.choice, Quot.sound |
| Lean kernel replay of every module | 175,187 of 175,187 PASS on five hosts; no kernel rejection (`scripts/verify_replay_evidence.sh`, calibrated) |
| Independent kernel on the five theorems' closure (61.6 GB, 1,460,445 declarations) | nanoda: accepted (strict, three standard axioms); con-leche: no verdict (its normalization step budget, at one `decide +kernel` proof); con-ron: not run on the closure, since it declined a 13.3 GB export at its arena capacity |

The theorems `riemannHypothesis`, `riemannZeta_eq_zero_re`, `LFunction_ne_zero_of_half_lt_re`,
`LFunction_eq_zero_re` and `LFunction_eq_zero_re_of_isPrimitive` therefore follow, in Lean's logic with the three
standard axioms, from Mathlib's definitions at the pinned commit. A machine check establishes that, and only that: it
is not a mathematical review of the argument, and the acceptance of the result belongs to the mathematical
community.

## Contents

| Path | What it is |
|---|---|
| `CERTIFICATION.md` | the record: subject, every count and digest, calibration, limits, scope |
| `fetch_archive.sh` | downloads the 14 parts from alpo.ge, checks sha256 9631b4f0..., extracts the Lake project |
| `audit/GororobaAudit.lean` | the statement audit, run inside the archive's Lake project |
| `driver/` | `alpocheck`: Lean 4.33.1 leanchecker's `replayFromImports`, copied verbatim, called on one named module per process |
| `scripts/lc_run.sh` | runs `alpocheck` over a module list, one process per module |
| `scripts/stage_ext2.sh` | the independent-kernel run: calibration, lean4export, nanoda and con-leche |
| `scripts/verify_replay_evidence.sh`, `scripts/cal_verify.sh` | the coverage verdict over `evidence/`, and its calibration on six planted defects |
| `evidence/hosts/*/` | each host's own result files: `results.txt` (every PASS/FAIL line), `driver-results.txt`, `driver-switch.txt` (calibration and agreement), `err/`, `summary.txt`, `manifest-digest.txt` |
| `evidence/modules/` | the module list (175,073 leaves, 114 parents) |
| `evidence/olean-manifest.sha256.xz` | sha256 of every compiled .olean; all five hosts hashed identical bytes |
| `evidence/external-kernels/` | the closure check (logs, timings, 30 s resource profile), the scale points at 162 MB and 13 GB, the empty-export test, and the single-declaration test of `PI.PC.loop_run` |
| `evidence/build/`, `evidence/audit/` | the last lines of the build log and the audit output |

Host names are replaced by `workstation` and `cloud-vm-1..4`, and home directories by `~`.

## Reproducing

1. `sh fetch_archive.sh` (about 240 MB download), then in `archive/lean`: `lake exe cache get` and `lake build`.
   The last build run took 13 hours at 12 parallel jobs on a 54 GB host; runs at 16 and 24 jobs thrashed the page
   cache, so memory, not cores, limits the job count.
2. Statement audit: copy `audit/GororobaAudit.lean` into `archive/lean` and run `lake env lean GororobaAudit.lean`.
3. Kernel replay: build `driver/` with `lake build`, calibrate it on a module holding a False theorem added under
   `debug.skipKernelTC` (it must print FAIL) and on a good module, then run `scripts/lc_run.sh MODLIST JOBS 1 OUT`
   from `archive/lean`. Each module costs about 6 s and 0.2 to 0.3 GB private memory; a host should hold the
   94.6 GB of mapped .olean files in its page cache.
4. Independent kernel: `scripts/stage_ext2.sh` documents the run; it needs about 250 GB of memory for the export
   and `ci/external_kernel_export.py` of [gororoba-math](https://github.com/Oichkatzelesfrettschen/gororoba-math)
   (commit 91c77465f, sha256 450e8f20...).
5. Verdict: `sh scripts/verify_replay_evidence.sh` and `sh scripts/cal_verify.sh`.

## License

The files of this repository are under the BSD 3-Clause License (`LICENSE`), except the function
`replayFromImports` in `driver/AlpoCheck.lean`, copied from Lean 4 and under the Apache License 2.0
(`driver/NOTICE`). Levent Alpöge's archive is not part
of it and stays under its author's terms; no license for it was found in the archive, on alpo.ge or in the note.

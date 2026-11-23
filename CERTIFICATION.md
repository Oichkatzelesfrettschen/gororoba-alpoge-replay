# Certification record: kernel replay of the alpo.ge Lean archive

Record of the replay run from 2026-11-20 to 2026-11-23. Numbers come from files under `evidence/` of this
repository, which holds each host's own result files, except those marked "(running record)", which come from the
replay's working notes. Times are UTC.

## Subject

- Archive: `lean.tar.gz`, the concatenation of `https://alpo.ge/lean.tar.gz.part01..14`, sha256
  9631b4f020199e580ba86178cb56c6e9b09f690c2369a80dc4334aa93f49c7fc; 175,187 modules (175,073 leaves, 114 parents),
  toolchain leanprover/lean4:v4.33.1, Mathlib 0df444a360eaa60ab8c11dca51a86af692955474 (batteries 4488d40d, aesop
  3448c0bc, Qq 92c15be1, plausible b7eb3304, LeanSearchClient 5f4d51b8, importGraph 16f02aa7, proofwidgets 4be2e3d5,
  Cli v4.33.0); the Mathlib package checkout is upstream mathlib4 at that revision with no local change (`git status`
  clean, 2026-11-23). The archive carries no license.
- Claims: the five theorems of `Main.lean`: `riemannHypothesis`, `riemannZeta_eq_zero_re`,
  `LFunction_ne_zero_of_half_lt_re`, `LFunction_eq_zero_re`, `LFunction_eq_zero_re_of_isPrimitive`.

## Result

Items (a), (b) and (c) hold in full. Item (d) asked for acceptance by three external checkers; one of the three accepted, and the other two returned no verdict, for the causes measured below. No checker rejected anything.

| Item | Check | Result |
|---|---|---|
| (a) build | workstation `lake build`, Lean 4.33.1, sandboxed | "Build completed successfully (183903 jobs)" (`evidence/build/build-tail.txt`), at 2026-11-22T15:11:38Z (running record) |
| (b) statements | `GororobaAudit.lean` (imports Main) | each of the five propositions equals its standard form by `Iff.rfl`; `RiemannHypothesis` and `riemannZeta` come from Mathlib.NumberTheory.LSeries.RiemannZeta, `DirichletCharacter.LFunction` from Mathlib.NumberTheory.LSeries.DirichletContinuation, unredefined; `#print axioms` gives [propext, Classical.choice, Quot.sound] for all five |
| (c) kernel replay | every module replayed by Lean's kernel on some host | 175,187 of 175,187 modules PASS; no kernel message in any of the 155 per-module err files or any FAIL line of a listed module (`verify_replay_evidence.sh`, VERDICT PASS, calibrated) |
| (d) independent kernel | export of the five theorems' dependency closure, checked outside Lean | 1 of 3: nanoda_bin accepts under the strict three-axiom configuration; con-leche gives no verdict (step budget); con-ron declines by capacity |

## (c) Kernel replay in detail

Two replay programs ran, both calling Lean 4.33.1's kernel through the function `replayFromImports` of leanchecker's `src/LeanChecker.lean`:
- `leanchecker` of the toolchain, one call per module, until each host's driver switch;
- the driver `alpocheck` (`driver/AlpoCheck.lean`, source sha256 05bbf74d22388d256f1c6f57866d852d0f85789d20075aaca1bf8b7fb6446f41, binary sha256
  ad3ec835ff683763d7c431ae67b752899ebb30e5a9404270fc674bfd6f4b7c60), which copies `replayFromImports` verbatim from tag
  v4.33.1 (commit 819816b2e0a3) and skips leanchecker's per-target walk of the search path (117 of 123 s per module, running record).
  Each host calibrated it before the switch (`evidence/hosts/*/driver-switch.txt`): `ReplayFixture.bogus` (a False theorem added under `debug.skipKernelTC`)
  rejected with "(kernel) declaration type mismatch", a known-good module accepted, and agreement with leanchecker
  on modules leanchecker had passed (the workstation 40 of 40, each VM 14 of 14), in each host's `driver-switch.txt`.

| Host | PASS | driver | leanchecker | FAIL lines |
|---|---|---|---|---|
| workstation (WSL, 16 cores, 54 GB) | 13,125 | 8,000 | 5,125 | 0 |
| cloud-vm-1 (n2d-highmem-16) | 46,047 | 5,530 | 40,517 | 2 (harness artifact) |
| cloud-vm-2 (c2d-highmem-16) | 46,302 | 3,881 | 42,421 | 0 |
| cloud-vm-3 (c2d-highmem-16) | 47,903 | 5,772 | 42,131 | 0 |
| cloud-vm-4 (c2d-highmem-8) | 29,469 | 2,800 | 26,669 | 0 |

- Coverage: the union of PASS names equals the module list (leaves.txt + parents.txt), which equals the module set of
  the olean manifest. 156,408 modules have a leanchecker PASS; the other 18,779 have driver PASS lines only. All 114
  parents passed through the driver on cloud-vm-3.
- Err files: the hosts kept 155 per-module stderr files; 154 are empty, and the one nonempty file is the HypothesesZ artifact below ("Could not find any oleans"). The only "(kernel)"
  text in any log is the calibration rejection of `ReplayFixture.bogus` in the driver-switch and calibration files.
- Olean identity: the sorted sha256 list of all 175,187 archive .olean files has digest
  e568bf3058c58bfa09f1f89c5645e37781673582d029bb1057fb20415ec99d85 on all five hosts, so every host checked the
  bytes the workstation built.
- Harness artifact: cloud-vm-1's two FAIL lines (results and recheck) name
  `...DenseThresholdCases.HypothesesZ`, which is no module of the archive: default xargs quote parsing turned the
  target `HypothesesZ''` into it before `xargs -d '\n'` replaced it. The real modules `HypothesesZ'` and
  `HypothesesZ''` both have PASS lines.
- Verifier: `verify_replay_evidence.sh`; calibration `cal_verify.sh` (real evidence PASS; six mutants FAIL: a missing
  PASS, a kernel FAIL line, a kernel message in an err file without a FAIL line, a changed manifest digit, a removed
  calibration line, a malformed line). Output:
  `evidence/verify-output.txt`.

## (d) Independent kernel in detail

- Export: lean4export 4.33.1 (sha256 805ab4cc...) of `Main -- <the five theorems>` on one c2d-highmem-32 VM
  (251 GiB), 2026-11-23: exit 0 after 7,000.5 s, peak RSS 162.5 GB (private 69.7 GB); 61,571,290,481 bytes,
  1,080,769,494 lines, sha256 4301ce4828d397c728e87f3e6a1251aa42abe5e12809bb9e0b73cc3d33072e7e; 1,460,445 declarations
  whose axioms are exactly propext, Classical.choice, Quot.sound (`external_kernel_export.py`).
- Calibration on the same VM before the export: dependency-closure exports cal-bad2 (`ReplayFixture.bogus`, sha256
  76cb0a26...) and cal-good2 (closure of `GlobalTheory.isogeny_torsion_bij`, 22,234 declarations, sha256 e96926c6...);
  con-leche --verified rejected bad2 (type mismatch, exit 1) and accepted good2; nanoda_bin rejected bad2 at its type
  check (exit 101) and accepted good2.
- **nanoda_bin** (Lean 4.35.0 toolchain; permitted axioms propext, Classical.choice, Quot.sound; hard error on any
  other): exit 0, 3,420.6 s wall, 31,588 CPU-seconds on 16 threads, peak RSS 80.4 GB. nanoda prints nothing on
  acceptance, and it also exits 0 on an empty export, as con-leche does ("accepted 0 declarations";
  `evidence/external-kernels/empty-export/`), so the accept rests on
  three further facts: the export gate (lean4export exit 0, a final line that parses as JSON, 61.6 GB); the name check
  (exit 0 only when all five theorems are declared as theorems: "1,460,445 declarations; axioms: Classical.choice,
  Quot.sound, propext"); and the work done, 31,588 CPU-seconds at 80 GB, against 42 s for one 15k-line closure.
- The export itself is gone: it lived on the VM disk, which the teardown deleted; its size, line count and sha256
  above are the record. Rebuilding it needs a host with about 250 GB of memory (peak RSS 162.5 GB with the mapped
  oleans).
- **con-leche --verified**: exit 3, "internal error: fuel exhausted: whnf loop" at `PI.PC.loop_run._proof_1_1` after
  1,651.7 s; no verdict. `PI.PC.loop_run` (Formalism/PeriodIntegrals/UnitaryGroupMassFormula/ChebyshevPrimeBounds/SmallLoop.lean)
  is `loop 362 131070 2 0 1 = true := by decide +kernel`, a 131,070-step kernel evaluation. Its own closure export
  (827,281 bytes) reproduces the stop in 2.6 s in both --verified and --trusted modes, and nanoda accepts it in 42 s:
  the stop is con-leche's fixed normalization budget, which its options cannot raise.
- **con-ron --verified**: not run on the closure; at 13.3 GB it declined with exit 2, "arena: expr constructor at
  capacity" (u32 term handles; `evidence/external-kernels/scale-13GB/`).

## Scope of the result

- What the replay establishes: Lean 4.33.1's kernel accepts every declaration of all 175,187 modules, and an
  independently written kernel (nanoda) accepts the complete dependency closure of the five theorems, which uses no
  axiom beyond the three standard ones. The theorems therefore follow from Mathlib's definitions of
  `riemannZeta`, `DirichletCharacter.LFunction` and `RiemannHypothesis` at the pinned commit.
- What it rests on: the correctness of nanoda or of Lean's kernel; lean4export's faithful export of the environment;
  and Mathlib's definitions meaning what the statements say (the audit pins the propositions to Mathlib's own
  names by definitional equality).
- What it does not establish: mathematical review of the argument, and acceptance by the mathematical community.
- Cost (running record): about USD 228 of list-price cloud compute, of which about 95 % went to leanchecker's
  per-module walk of the search path before the driver replaced it.

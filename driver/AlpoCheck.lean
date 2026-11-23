/-
Driver around the replay function of Lean 4.33.1's leanchecker (src/LeanChecker.lean, function replayFromImports,
copied verbatim): each argument names one module, which is replayed from its imports with the kernel, without the
search-path walk that leanchecker runs per target to resolve a module-name prefix. Prints "PASS M" or
"FAIL M: error" per module; the exit code is 1 when any module fails.
-/
import Lean.CoreM
import Lean.Replay

open Lean

unsafe def replayFromImports (module : Name) : IO Unit := do
  let mFile ← findOLean module
  unless (← mFile.pathExists) do
    throw <| IO.userError s!"object file '{mFile}' of module {module} does not exist"
  -- Load all module data parts (exported, server, private)
  let mut fnames := #[mFile]
  let sFile := OLeanLevel.server.adjustFileName mFile
  if (← sFile.pathExists) then
    fnames := fnames.push sFile
    let pFile := OLeanLevel.private.adjustFileName mFile
    if (← pFile.pathExists) then
      fnames := fnames.push pFile
  let parts ← readModuleDataParts fnames
  if h : parts.size = 0 then throw <| IO.userError "failed to read module data" else
  let (mod, _) := parts[0]
  let (_, s) ← importModulesCore mod.imports |>.run
  let env ← finalizeImport s mod.imports {} 0 false false (isModule := true)
  let mut newConstants := {}
  -- Collect constants from last ("most private") part, which subsumes all prior ones
  for name in parts[parts.size-1].1.constNames, ci in parts[parts.size-1].1.constants do
    newConstants := newConstants.insert name ci
  let env' ← env.replay newConstants
  env'.freeRegions

unsafe def main (args : List String) : IO UInt32 := do
  initSearchPath (← findSysroot)
  let mut rc : UInt32 := 0
  for a in args do
    let m := a.toName
    if m.isAnonymous then
      IO.println s!"FAIL {a}: not a module name"; rc := 1
    else
      try
        replayFromImports m
        IO.println s!"PASS {a}"
      catch e =>
        IO.println s!"FAIL {a}: {e}"; rc := 1
    (← IO.getStdout).flush
  return rc

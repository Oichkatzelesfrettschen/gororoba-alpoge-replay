import Main

/-! Statement audit of the alpo.ge archive: each proposition its Main.lean theorems prove, restated here
from its standard form, must equal the archive's constant by `Iff.rfl` (definitional unfolding only), and
each theorem's axioms are printed. -/

namespace GororobaAudit

/-- The Riemann hypothesis: every zero of zeta that is not a trivial zero -2(n+1) and not s = 1 has real
part 1/2 (the form of Mathlib's `RiemannHypothesis`). -/
def rh : Prop :=
  ∀ s : ℂ, riemannZeta s = 0 → (¬∃ n : ℕ, s = -2 * ((n : ℂ) + 1)) → s ≠ 1 → s.re = 1 / 2

/-- Dirichlet L-functions have no zero right of the critical line, apart from the pole of the trivial
character at 1. -/
def lNonvanishing : Prop :=
  ∀ (N : ℕ) [NeZero N] (χ : DirichletCharacter ℂ N) (s : ℂ),
    1 / 2 < s.re → (χ ≠ 1 ∨ s ≠ 1) → DirichletCharacter.LFunction χ s ≠ 0

/-- Zeros of Dirichlet L-functions in the open critical strip lie on the critical line. -/
def lZerosOnLine : Prop :=
  ∀ (N : ℕ) [NeZero N] (χ : DirichletCharacter ℂ N) (s : ℂ),
    0 < s.re → s.re < 1 → DirichletCharacter.LFunction χ s = 0 → s.re = 1 / 2

/-- The same for primitive characters. -/
def primitiveLZerosOnLine : Prop :=
  ∀ (N : ℕ) [NeZero N] (χ : DirichletCharacter ℂ N), χ.IsPrimitive →
    ∀ s : ℂ, 0 < s.re → s.re < 1 → DirichletCharacter.LFunction χ s = 0 → s.re = 1 / 2

example : RiemannHypothesis ↔ rh := Iff.rfl
example : RiemannZetaZerosOnLine ↔ rh := Iff.rfl
example : DirichletLNonvanishingRightOfHalf ↔ lNonvanishing := Iff.rfl
example : DirichletLZerosOnLine ↔ lZerosOnLine := Iff.rfl
example : PrimitiveDirichletLZerosOnLine ↔ primitiveLZerosOnLine := Iff.rfl

example : rh := riemannHypothesis
example : rh := riemannZeta_eq_zero_re
example : lNonvanishing := LFunction_ne_zero_of_half_lt_re
example : lZerosOnLine := LFunction_eq_zero_re
example : primitiveLZerosOnLine := LFunction_eq_zero_re_of_isPrimitive

end GororobaAudit

open Lean in
#eval show CoreM Unit from do
  let env ← getEnv
  for n in [`RiemannHypothesis, `riemannZeta, `DirichletCharacter.LFunction, `riemannHypothesis] do
    IO.println s!"{n} module: {(env.getModuleIdxFor? n).map (fun i => env.header.moduleNames[i.toNat]!)}"

#print axioms riemannHypothesis
#print axioms riemannZeta_eq_zero_re
#print axioms LFunction_ne_zero_of_half_lt_re
#print axioms LFunction_eq_zero_re
#print axioms LFunction_eq_zero_re_of_isPrimitive

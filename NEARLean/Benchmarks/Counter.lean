import NEARLean.Verification

namespace NEARLean.Benchmarks.Counter

open Verification

structure State where
  value : Nat
  isolated : Nat
  deriving BEq, Repr

inductive Action where
  | increment (caller : Principal)
  | read (caller : Principal)
  deriving BEq, Repr

def step (state : State) : Action → State × Nat
  | .increment _ => ({ state with value := state.value + 1 }, state.value + 1)
  | .read _ => (state, state.value)

def system : System State Action Nat := { step := step }

def Invariant (initial : State) (state : State) : Prop :=
  initial.value ≤ state.value ∧ state.isolated = initial.isolated

theorem step_preserves
    (initial before : State)
    (action : Action)
    (after : State)
    (result : Nat)
    (beforeValid : Invariant initial before)
    (transition : system.Transition before action after result) :
    Invariant initial after := by
  cases action with
  | increment caller =>
      simp [System.Transition, system, step] at transition
      rcases transition with ⟨rfl, rfl⟩
      exact ⟨Nat.le_trans beforeValid.1 (Nat.le_succ before.value), beforeValid.2⟩
  | read caller =>
      simp [System.Transition, system, step] at transition
      rcases transition with ⟨rfl, rfl⟩
      exact beforeValid

/-- Counter isolation and monotonicity hold for every finite valid trace. -/
theorem safe
    (initial last : State)
    (actions : List Action)
    (trace : ValidTrace system initial actions last) :
    Invariant initial last := by
  exact invariant_of_validTrace system (Invariant initial)
    (step_preserves initial) trace ⟨Nat.le_refl _, rfl⟩

end NEARLean.Benchmarks.Counter

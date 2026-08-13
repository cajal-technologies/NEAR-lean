import NEARLean.Verification

namespace NEARLean.Benchmarks.Escrow

open Verification

structure State where
  owner : Principal
  balance : Nat
  released : Nat
  deposited : Nat
  deriving BEq, Repr

inductive Action where
  | deposit (caller : Principal) (amount : Nat)
  | release (caller : Principal)
  deriving BEq, Repr

inductive Result where
  | deposited
  | released
  | unauthorized
  deriving BEq, Repr

def step (state : State) : Action → State × Result
  | .deposit _ amount => ({ state with
      balance := state.balance + amount
      deposited := state.deposited + amount
    }, .deposited)
  | .release caller =>
      if caller = state.owner then
        ({ state with balance := 0, released := state.released + state.balance }, .released)
      else
        (state, .unauthorized)

def system : System State Action Result := { step := step }

def Invariant (state : State) : Prop :=
  state.balance + state.released = state.deposited

theorem step_preserves
    (before : State)
    (action : Action)
    (after : State)
    (result : Result)
    (beforeValid : Invariant before)
    (transition : system.Transition before action after result) :
    Invariant after := by
  cases action with
  | deposit caller amount =>
      simp [System.Transition, system, step] at transition
      rcases transition with ⟨rfl, rfl⟩
      unfold Invariant at beforeValid ⊢
      change before.balance + amount + before.released = before.deposited + amount
      calc
        before.balance + amount + before.released =
            (before.balance + before.released) + amount := by
          rw [Nat.add_assoc, Nat.add_comm amount before.released, ← Nat.add_assoc]
        _ = before.deposited + amount := congrArg (· + amount) beforeValid
  | release caller =>
      simp [System.Transition, system, step] at transition
      split at transition
      · rcases transition with ⟨rfl, rfl⟩
        unfold Invariant at beforeValid ⊢
        change 0 + (before.released + before.balance) = before.deposited
        simpa [Nat.add_comm] using beforeValid
      · rcases transition with ⟨rfl, rfl⟩
        exact beforeValid

/-- Escrow balance is conserved against deposits over every valid trace. -/
theorem safe
    (initial last : State)
    (actions : List Action)
    (initialValid : Invariant initial)
    (trace : ValidTrace system initial actions last) :
    Invariant last :=
  invariant_of_validTrace system Invariant step_preserves trace initialValid

theorem unauthorized_release_unchanged
    (state : State)
    (caller : Principal)
    (unauthorized : caller ≠ state.owner) :
    (step state (.release caller)).1 = state := by
  simp [step, unauthorized]

end NEARLean.Benchmarks.Escrow

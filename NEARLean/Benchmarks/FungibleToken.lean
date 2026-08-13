import NEARLean.Verification

namespace NEARLean.Benchmarks.FungibleToken

open Verification

def alice : Principal := 0
def bob : Principal := 1

structure State where
  aliceBalance : Nat
  bobBalance : Nat
  totalSupply : Nat
  deriving BEq, Repr

structure Action where
  caller : Principal
  receiver : Principal
  amount : Nat
  deriving BEq, Repr

inductive Result where
  | transferred
  | rejected
  deriving BEq, Repr

def step (state : State) (action : Action) : State × Result :=
  if action.caller = alice ∧ action.receiver = bob ∧ action.amount ≤ state.aliceBalance then
    ({ state with
      aliceBalance := state.aliceBalance - action.amount
      bobBalance := state.bobBalance + action.amount
    }, .transferred)
  else if action.caller = bob ∧ action.receiver = alice ∧ action.amount ≤ state.bobBalance then
    ({ state with
      aliceBalance := state.aliceBalance + action.amount
      bobBalance := state.bobBalance - action.amount
    }, .transferred)
  else
    (state, .rejected)

def system : System State Action Result := { step := step }

def Invariant (state : State) : Prop :=
  state.aliceBalance + state.bobBalance = state.totalSupply

theorem step_preserves
    (before : State)
    (action : Action)
    (after : State)
    (result : Result)
    (beforeValid : Invariant before)
    (transition : system.Transition before action after result) :
    Invariant after := by
  simp [System.Transition, system, step] at transition
  split at transition
  · rcases transition with ⟨rfl, rfl⟩
    have sufficient : action.amount ≤ before.aliceBalance := by simp_all
    unfold Invariant at beforeValid ⊢
    calc
      before.aliceBalance - action.amount + (before.bobBalance + action.amount) =
          (before.aliceBalance - action.amount + action.amount) + before.bobBalance := by
        rw [Nat.add_comm before.bobBalance action.amount, ← Nat.add_assoc]
      _ = before.aliceBalance + before.bobBalance := by
        rw [Nat.sub_add_cancel sufficient]
      _ = before.totalSupply := beforeValid
  · split at transition
    · rcases transition with ⟨rfl, rfl⟩
      have sufficient : action.amount ≤ before.bobBalance := by simp_all
      unfold Invariant at beforeValid ⊢
      calc
        before.aliceBalance + action.amount + (before.bobBalance - action.amount) =
            before.aliceBalance +
              (before.bobBalance - action.amount + action.amount) := by
          rw [Nat.add_assoc, Nat.add_comm action.amount
            (before.bobBalance - action.amount)]
        _ = before.aliceBalance + before.bobBalance := by
          rw [Nat.sub_add_cancel sufficient]
        _ = before.totalSupply := beforeValid
    · rcases transition with ⟨rfl, rfl⟩
      exact beforeValid

/-- Total token supply is conserved over every valid adversarial trace. -/
theorem safe
    (initial last : State)
    (actions : List Action)
    (initialValid : Invariant initial)
    (trace : ValidTrace system initial actions last) :
    Invariant last :=
  invariant_of_validTrace system Invariant step_preserves trace initialValid

theorem rejected_transfer_unchanged
    (state : State)
    (action : Action)
    (invalid : ¬(action.caller = alice ∧ action.receiver = bob ∧
        action.amount ≤ state.aliceBalance) ∧
      ¬(action.caller = bob ∧ action.receiver = alice ∧
        action.amount ≤ state.bobBalance)) :
    (step state action).1 = state := by
  simp [step, invalid.1, invalid.2]

end NEARLean.Benchmarks.FungibleToken

/-!
# Public contract-verification API

This module is independent of the runtime implementation. Contract models provide
a deterministic transition system and reuse the trace and property definitions below.
-/

namespace NEARLean.Verification

abbrev Principal := Nat

structure System (State Action Result : Type) where
  step : State → Action → State × Result

def System.Transition
    (system : System State Action Result)
    (before : State)
    (action : Action)
    (after : State)
    (result : Result) : Prop :=
  system.step before action = (after, result)

inductive ValidTrace
    (system : System State Action Result) : State → List Action → State → Prop where
  | nil (state : State) : ValidTrace system state [] state
  | cons
      (head : system.Transition initial action next result)
      (tail : ValidTrace system next actions last) :
      ValidTrace system initial (action :: actions) last

def Reachable
    (system : System State Action Result) (initial state : State) : Prop :=
  ∃ actions, ValidTrace system initial actions state

abbrev StateInvariant (State : Type) := State → Prop
abbrev Precondition (State Action : Type) := State → Action → Prop
abbrev Postcondition (State Action Result : Type) :=
  State → Action → State → Result → Prop
abbrev Authorization (State Action : Type) :=
  State → Principal → Action → Prop

def Preserves
    (system : System State Action Result)
    (invariant : StateInvariant State) : Prop :=
  ∀ before action after result,
    invariant before → system.Transition before action after result → invariant after

def Ensures
    (system : System State Action Result)
    (precondition : Precondition State Action)
    (postcondition : Postcondition State Action Result) : Prop :=
  ∀ before action after result,
    precondition before action →
      system.Transition before action after result →
      postcondition before action after result

def Conserves
    (system : System State Action Result) (quantity : State → Nat) : Prop :=
  ∀ before action after result,
    system.Transition before action after result → quantity after = quantity before

def Noninterference
    [BEq Observation]
    (system : System State Action Result)
    (observe : State → Observation)
    (relevant : Action → Bool) : Prop :=
  ∀ before action after result,
    relevant action = false →
      system.Transition before action after result →
      observe after = observe before

def ConditionalLiveness
    (system : System State Action Result)
    (enabled : State → Prop)
    (progress : State → State → Prop) : Prop :=
  ∀ before, enabled before →
    ∃ action after result,
      system.Transition before action after result ∧ progress before after

inductive UpgradePolicy where
  | forbidden
  | authorizedOnly
  | unrestricted
  deriving BEq, Repr

/-- The blockchain inputs considered adversarial at the public proof boundary. -/
structure BlockchainThreatModel where
  callerIdentity : Bool
  arguments : Bool
  transactionOrdering : Bool
  attachedDeposit : Bool
  prepaidGas : Bool
  crossContractResponses : Bool
  callbackSuccess : Bool
  blockHeightAndTimestamp : Bool
  upgrades : UpgradePolicy
  deriving BEq, Repr

def BlockchainThreatModel.milestoneSix : BlockchainThreatModel := {
  callerIdentity := true
  arguments := true
  transactionOrdering := true
  attachedDeposit := true
  prepaidGas := true
  crossContractResponses := true
  callbackSuccess := true
  blockHeightAndTimestamp := true
  upgrades := .forbidden
}

structure AdversaryModel (Action : Type) where
  allowed : Action → Prop

structure EnvironmentModel (Action : Type) where
  enabled : Action → Prop
  fair : List Action → Prop

def ValidAdversarialTrace
    (system : System State Action Result)
    (adversary : AdversaryModel Action)
    (initial : State)
    (actions : List Action)
    (last : State) : Prop :=
  ValidTrace system initial actions last ∧
    ∀ action, action ∈ actions → adversary.allowed action

theorem System.transition_deterministic
    (system : System State Action Result)
    (first : system.Transition state action after₁ result₁)
    (second : system.Transition state action after₂ result₂) :
    after₁ = after₂ ∧ result₁ = result₂ := by
  unfold System.Transition at first second
  rw [first] at second
  cases second
  exact ⟨rfl, rfl⟩

theorem invariant_of_validTrace
    (system : System State Action Result)
    (invariant : StateInvariant State)
    (preserved : Preserves system invariant)
    (trace : ValidTrace system initial actions last)
    (initialValid : invariant initial) :
    invariant last := by
  induction trace with
  | nil => exact initialValid
  | cons head tail inductionHypothesis =>
      exact inductionHypothesis (preserved _ _ _ _ initialValid head)

theorem invariant_of_reachable
    (system : System State Action Result)
    (invariant : StateInvariant State)
    (preserved : Preserves system invariant)
    (initialValid : invariant initial)
    (reachable : Reachable system initial state) :
    invariant state := by
  rcases reachable with ⟨actions, trace⟩
  exact invariant_of_validTrace system invariant preserved trace initialValid

end NEARLean.Verification

/-!
# Abstract state-transition kernel

This module is the proof-oriented kernel through Milestone 2. Its data structures
and basic actions deliberately make no byte-level or nearcore-compatibility claim.
-/

namespace NEARLean

/-- A proof-friendly account identifier. Concrete validation belongs to a later layer. -/
abbrev AccountId := List UInt8

/-- An abstract identifier for contract code. -/
abbrev ContractId := List UInt8

/-- Token amounts are unbounded naturals in the abstract kernel. -/
abbrev Balance := Nat

/-- Gas amounts are unbounded naturals in the abstract kernel. -/
abbrev Gas := Nat

/-- Storage is represented extensionally as finite key-value associations. -/
abbrev StorageKey := List UInt8

abbrev StorageValue := List UInt8

abbrev Storage := List (StorageKey × StorageValue)

/-- Block data visible to an abstract runtime transition. -/
structure BlockContext where
  height : Nat
  timestamp : Nat
  gasPrice : Balance
  gasLimit : Gas
  deriving BEq, Repr

/-- Bounds used by the abstract invariants, not a nearcore gas or economics table. -/
structure RuntimeConfig where
  maxAccountIdLength : Nat
  maxContractIdLength : Nat
  maxStorageKeyLength : Nat
  maxStorageValueLength : Nat
  maxAccountBalance : Balance
  maxGas : Gas
  deriving BEq, Repr

/-- A small configuration suitable for examples and tests. -/
def RuntimeConfig.default : RuntimeConfig where
  maxAccountIdLength := 64
  maxContractIdLength := 64
  maxStorageKeyLength := 2048
  maxStorageValueLength := 65536
  maxAccountBalance := 10 ^ 30
  maxGas := 10 ^ 15

/-- Account identifiers are nonempty and within the configured abstract bound. -/
def AccountId.WellFormed (config : RuntimeConfig) (id : AccountId) : Prop :=
  id.length > 0 ∧ id.length ≤ config.maxAccountIdLength

instance (config : RuntimeConfig) (identifier : AccountId) :
    Decidable (AccountId.WellFormed config identifier) := by
  unfold AccountId.WellFormed
  infer_instance

/-- Contract identifiers are nonempty and within the configured abstract bound. -/
def ContractId.WellFormed (config : RuntimeConfig) (id : ContractId) : Prop :=
  id.length > 0 ∧ id.length ≤ config.maxContractIdLength

instance (config : RuntimeConfig) (identifier : ContractId) :
    Decidable (ContractId.WellFormed config identifier) := by
  unfold ContractId.WellFormed
  infer_instance

/-- Storage keys are unique, nonempty, and all entries satisfy configured bounds. -/
def Storage.WellFormed (config : RuntimeConfig) (storage : Storage) : Prop :=
  (storage.map fun entry => entry.1).Nodup ∧
    storage.all (fun entry => decide (
      entry.1.length > 0 ∧
        entry.1.length ≤ config.maxStorageKeyLength ∧
        entry.2.length ≤ config.maxStorageValueLength)) = true

instance (config : RuntimeConfig) (storage : Storage) :
    Decidable (Storage.WellFormed config storage) := by
  unfold Storage.WellFormed
  infer_instance

/-- The balance components and their sum fit within the configured abstract bound. -/
def Balance.WellFormed (config : RuntimeConfig) (liquid locked : Balance) : Prop :=
  liquid ≤ config.maxAccountBalance ∧
    locked ≤ config.maxAccountBalance ∧
    liquid + locked ≤ config.maxAccountBalance

instance (config : RuntimeConfig) (liquid locked : Balance) :
    Decidable (Balance.WellFormed config liquid locked) := by
  unfold Balance.WellFormed
  infer_instance

/-- Abstract account data; code bytes and access keys are intentionally absent. -/
structure Account where
  balance : Balance
  locked : Balance
  storage : Storage
  contract : Option ContractId
  deriving BEq, Repr

/-- The empty account constructor used before Milestone 2 action semantics exist. -/
def Account.initial : Account where
  balance := 0
  locked := 0
  storage := []
  contract := none

/-- Every account component satisfies its explicit Milestone 1 invariant. -/
def Account.WellFormed
    (config : RuntimeConfig) (id : AccountId) (account : Account) : Prop :=
  id.WellFormed config ∧
    Balance.WellFormed config account.balance account.locked ∧
    Storage.WellFormed config account.storage ∧
    match account.contract with
    | none => True
    | some contractId => contractId.WellFormed config

instance (config : RuntimeConfig) (identifier : AccountId) (account : Account) :
    Decidable (Account.WellFormed config identifier account) := by
  unfold Account.WellFormed
  cases account.contract <;> infer_instance

/-- The initial account is well formed whenever its supplied identifier is valid. -/
theorem Account.initial_wellFormed
    (config : RuntimeConfig)
    (id : AccountId)
    (identifierValid : id.WellFormed config) :
    (Account.initial.WellFormed config id) := by
  exact ⟨identifierValid,
    ⟨Nat.zero_le _, Nat.zero_le _, Nat.zero_le _⟩,
    ⟨List.Pairwise.nil, rfl⟩,
    True.intro⟩

/-- Abstract global state with a finite account map and current block context. -/
structure WorldState where
  accounts : List (AccountId × Account)
  block : BlockContext
  deriving BEq, Repr

/-- The block context respects configured gas and balance bounds. -/
def BlockContext.WellFormed (config : RuntimeConfig) (block : BlockContext) : Prop :=
  block.gasPrice ≤ config.maxAccountBalance ∧ block.gasLimit ≤ config.maxGas

instance (config : RuntimeConfig) (block : BlockContext) :
    Decidable (BlockContext.WellFormed config block) := by
  unfold BlockContext.WellFormed
  infer_instance

/-- Account IDs are unique and every stored account satisfies all local invariants. -/
def WorldState.WellFormed (config : RuntimeConfig) (state : WorldState) : Prop :=
  state.block.WellFormed config ∧
    (state.accounts.map fun entry => entry.1).Nodup ∧
    state.accounts.all (fun entry => decide (entry.2.WellFormed config entry.1)) = true

instance (config : RuntimeConfig) (state : WorldState) :
    Decidable (WorldState.WellFormed config state) := by
  unfold WorldState.WellFormed
  infer_instance

/-- A deterministic empty world whose block limits are derived from the configuration. -/
def WorldState.initial (config : RuntimeConfig) : WorldState where
  accounts := []
  block := {
    height := 0
    timestamp := 0
    gasPrice := 0
    gasLimit := config.maxGas
  }

/-- The empty world constructor is well formed for every runtime configuration. -/
theorem WorldState.initial_wellFormed :
    (WorldState.initial config).WellFormed config := by
  exact ⟨⟨Nat.zero_le _, Nat.le_refl _⟩, List.Pairwise.nil, rfl⟩

/-- Look up a key in finite abstract storage. -/
def Storage.lookup (key : StorageKey) : Storage → Option StorageValue
  | [] => none
  | (storedKey, value) :: rest =>
      if storedKey = key then some value else lookup key rest

/-- Replace or insert a storage entry while preserving unrelated keys. -/
def Storage.set (key : StorageKey) (value : StorageValue) : Storage → Storage
  | [] => [(key, value)]
  | (storedKey, storedValue) :: rest =>
      if storedKey = key then
        (key, value) :: rest
      else
        (storedKey, storedValue) :: set key value rest

/-- Look up an account in the finite world-state map. -/
def WorldState.lookupAccount : List (AccountId × Account) → AccountId → Option Account
  | [], _ => none
  | (storedId, account) :: rest, id =>
      if storedId = id then some account else lookupAccount rest id

/-- Replace or insert one account in the finite world-state map. -/
def WorldState.setAccountList
    (id : AccountId) (account : Account) : List (AccountId × Account) → List (AccountId × Account)
  | [] => [(id, account)]
  | (storedId, storedAccount) :: rest =>
      if storedId = id then
        (id, account) :: rest
      else
        (storedId, storedAccount) :: setAccountList id account rest

def WorldState.account? (state : WorldState) (id : AccountId) : Option Account :=
  WorldState.lookupAccount state.accounts id

def WorldState.setAccount (state : WorldState) (id : AccountId) (account : Account) : WorldState :=
  { state with accounts := WorldState.setAccountList id account state.accounts }

def Option.orError (error : ε) : Option α → Except ε α
  | none => .error error
  | some value => .ok value

/-- The two native contract programs available in the temporary backend. -/
inductive NativeContract where
  | counter
  | escrow
  deriving BEq, Repr

def NativeContract.counterId : ContractId := [1]

def NativeContract.escrowId : ContractId := [2]

def NativeContract.ofId (id : ContractId) : Option NativeContract :=
  if id = counterId then
    some .counter
  else if id = escrowId then
    some .escrow
  else
    none

namespace NativeMethod

def increment : StorageKey := [1]
def get : StorageKey := [2]
def deposit : StorageKey := [3]
def release : StorageKey := [4]
def balance : StorageKey := [5]

end NativeMethod

namespace NativeStorage

def counter : StorageKey := [1]
def escrowOwner : StorageKey := [2]

end NativeStorage

/-- Basic sandbox actions supported at Milestone 2. -/
inductive Input where
  | createAccount (accountId : AccountId)
  | transfer (sender receiver : AccountId) (amount : Balance)
  | deployContract (deployer accountId : AccountId) (contractId : ContractId)
  | functionCall
      (caller receiver : AccountId)
      (methodName : StorageKey)
      (arguments : StorageValue)
      (attachedDeposit : Balance)
      (prepaidGas : Gas)
  deriving Repr

/-- Explicit failures for the executable sandbox. -/
inductive RuntimeError where
  | invalidInitialState
  | invalidAccountId (accountId : AccountId)
  | accountAlreadyExists (accountId : AccountId)
  | accountNotFound (accountId : AccountId)
  | insufficientBalance (accountId : AccountId)
  | balanceOverflow (accountId : AccountId)
  | invalidGas
  | contractAlreadyDeployed (accountId : AccountId)
  | unsupportedContract (contractId : ContractId)
  | contractNotDeployed (accountId : AccountId)
  | methodNotFound (methodName : StorageKey)
  | depositRequired
  | unauthorized
  | invalidArguments
  | invariantViolation
  deriving BEq, Repr

/-- Observable result of a successful sandbox action or view. -/
structure Output where
  returnValue : StorageValue := []
  logs : List StorageValue := []
  gasBurnt : Gas := 0
  balance : Option Balance := none
  deriving BEq, Repr

def Output.empty : Output := {}

/-- Move liquid balance between two existing accounts. -/
def WorldState.transferBalance
    (config : RuntimeConfig)
    (state : WorldState)
    (sender receiver : AccountId)
    (amount : Balance) : Except RuntimeError WorldState :=
  match state.account? sender with
  | none => .error (.accountNotFound sender)
  | some senderAccount =>
      match state.account? receiver with
      | none => .error (.accountNotFound receiver)
      | some receiverAccount =>
          if senderAccount.balance < amount then
            .error (.insufficientBalance sender)
          else if sender = receiver then
            .ok state
          else if config.maxAccountBalance - receiverAccount.balance < amount then
            .error (.balanceOverflow receiver)
          else
            let state := state.setAccount sender {
              senderAccount with balance := senderAccount.balance - amount }
            .ok <| state.setAccount receiver {
              receiverAccount with balance := receiverAccount.balance + amount }

def initializedContractAccount
    (deployer : AccountId) (contractId : ContractId) (account : Account) : Account :=
  let storage :=
    if contractId = NativeContract.counterId then
      account.storage.set NativeStorage.counter []
    else
      account.storage.set NativeStorage.escrowOwner deployer
  { account with contract := some contractId, storage := storage }

def executeNative
    (config : RuntimeConfig)
    (state : WorldState)
    (caller receiver : AccountId)
    (contract : NativeContract)
    (methodName : StorageKey)
    (arguments : StorageValue)
    (attachedDeposit : Balance) : Except RuntimeError (WorldState × Output) := do
  let account ← Option.orError (.accountNotFound receiver) (state.account? receiver)
  match contract with
  | .counter =>
      if methodName = NativeMethod.increment then
        let current := account.storage.lookup NativeStorage.counter |>.getD []
        let updatedValue := 0 :: current
        let updatedAccount := { account with
          storage := account.storage.set NativeStorage.counter updatedValue }
        return (state.setAccount receiver updatedAccount, {
          returnValue := updatedValue
          logs := [[1]]
          gasBurnt := 1
        })
      else if methodName = NativeMethod.get then
        return (state, {
          returnValue := account.storage.lookup NativeStorage.counter |>.getD []
          gasBurnt := 1
        })
      else
        throw (.methodNotFound methodName)
  | .escrow =>
      if methodName = NativeMethod.deposit then
        if attachedDeposit = 0 then
          throw .depositRequired
        return (state, { logs := [[2]], gasBurnt := 1, balance := some account.balance })
      else if methodName = NativeMethod.release then
        let owner ← Option.orError .unauthorized
          (account.storage.lookup NativeStorage.escrowOwner)
        if caller ≠ owner then
          throw .unauthorized
        if arguments.isEmpty then
          throw .invalidArguments
        let releasedState ← state.transferBalance config receiver arguments account.balance
        return (releasedState, {
          logs := [[3]]
          gasBurnt := 1
          balance := some account.balance
        })
      else if methodName = NativeMethod.balance then
        return (state, { gasBurnt := 1, balance := some account.balance })
      else
        throw (.methodNotFound methodName)

/-- Execute one action into a candidate state before invariant validation. -/
def execute
    (config : RuntimeConfig)
    (state : WorldState)
    (input : Input) : Except RuntimeError (WorldState × Output) := do
  match input with
  | .createAccount accountId =>
      if ¬accountId.WellFormed config then
        throw (.invalidAccountId accountId)
      if state.account? accountId |>.isSome then
        throw (.accountAlreadyExists accountId)
      return (state.setAccount accountId Account.initial, Output.empty)
  | .transfer sender receiver amount =>
      let state ← state.transferBalance config sender receiver amount
      return (state, Output.empty)
  | .deployContract deployer accountId contractId =>
      let _ ← Option.orError (.accountNotFound deployer) (state.account? deployer)
      let account ← Option.orError (.accountNotFound accountId) (state.account? accountId)
      if account.contract.isSome then
        throw (.contractAlreadyDeployed accountId)
      let _ ← Option.orError (.unsupportedContract contractId) (NativeContract.ofId contractId)
      let account := initializedContractAccount deployer contractId account
      return (state.setAccount accountId account, Output.empty)
  | .functionCall caller receiver methodName arguments attachedDeposit prepaidGas =>
      if prepaidGas = 0 ∨ config.maxGas < prepaidGas then
        throw .invalidGas
      let depositedState ← state.transferBalance config caller receiver attachedDeposit
      let receiverAccount ← Option.orError (.accountNotFound receiver)
        (depositedState.account? receiver)
      let contractId ← Option.orError (.contractNotDeployed receiver) receiverAccount.contract
      let contract ← Option.orError (.unsupportedContract contractId)
        (NativeContract.ofId contractId)
      executeNative config depositedState caller receiver contract methodName arguments attachedDeposit

/-!
`step` commits only well-formed candidate states. Every execution or validation
failure explicitly returns the unchanged pre-state.
-/
def step
    (config : RuntimeConfig)
    (state : WorldState)
    (input : Input) : WorldState × Except RuntimeError Output :=
  match execute config state input with
  | .error runtimeError => (state, .error runtimeError)
  | .ok (candidate, output) =>
      if candidate.WellFormed config then
        (candidate, .ok output)
      else
        (state, .error .invariantViolation)

/-- A propositional transition is derived directly from `step`. -/
def Transition
    (config : RuntimeConfig)
    (before : WorldState)
    (input : Input)
    (after : WorldState)
    (result : Except RuntimeError Output) : Prop :=
  step config before input = (after, result)

/-- Equal inputs to the executable kernel have exactly one post-state and result. -/
theorem step_deterministic
    (first : step config state input = (after₁, result₁))
    (second : step config state input = (after₂, result₂)) :
    after₁ = after₂ ∧ result₁ = result₂ := by
  rw [first] at second
  cases second
  exact ⟨rfl, rfl⟩

/-- The derived transition relation is deterministic. -/
theorem Transition.deterministic
    (first : Transition config state input after₁ result₁)
    (second : Transition config state input after₂ result₂) :
    after₁ = after₂ ∧ result₁ = result₂ :=
  step_deterministic first second

/-- Failed actions and calls atomically roll back to their input state. -/
theorem step_error_rolls_back
    (failed : (step config state input).2 = .error runtimeError) :
    (step config state input).1 = state := by
  unfold step at failed ⊢
  split
  · rfl
  · split
    · simp_all
    · rfl

/-- Runtime validation preserves all world-state invariants. -/
theorem step_preserves_wellFormed
    (stateValid : state.WellFormed config) :
    (step config state input).1.WellFormed config := by
  unfold step
  split
  · exact stateValid
  · split
    · assumption
    · exact stateValid

/-- Updating one account cannot change lookup of a distinct account. -/
theorem WorldState.lookupAccount_setAccountList_of_ne
    (accounts : List (AccountId × Account))
    (observed updated : AccountId)
    (account : Account)
    (different : observed ≠ updated) :
    WorldState.lookupAccount (WorldState.setAccountList updated account accounts) observed =
      WorldState.lookupAccount accounts observed := by
  induction accounts with
  | nil =>
      simp [WorldState.setAccountList, WorldState.lookupAccount, Ne.symm different]
  | cons entry rest ih =>
      cases entry with
      | mk storedId storedAccount =>
          by_cases updatedHere : storedId = updated
          · simp [WorldState.setAccountList, WorldState.lookupAccount, updatedHere,
              Ne.symm different]
          · by_cases observedHere : storedId = observed
            · simp [WorldState.setAccountList, WorldState.lookupAccount, observedHere, different]
            · simp [WorldState.setAccountList, WorldState.lookupAccount, updatedHere,
                observedHere, ih]

theorem WorldState.account?_setAccount_of_ne
    (state : WorldState)
    (observed updated : AccountId)
    (account : Account)
    (different : observed ≠ updated) :
    (state.setAccount updated account).account? observed = state.account? observed := by
  exact WorldState.lookupAccount_setAccountList_of_ne
    state.accounts observed updated account different

/-- The two account updates used by transfer cannot affect a third account. -/
theorem transfer_updates_unrelated_account
    (state : WorldState)
    (sender receiver observed : AccountId)
    (senderAccount receiverAccount : Account)
    (senderDifferent : observed ≠ sender)
    (receiverDifferent : observed ≠ receiver) :
    ((state.setAccount sender senderAccount).setAccount receiver receiverAccount).account? observed =
      state.account? observed := by
  rw [WorldState.account?_setAccount_of_ne _ _ _ _ receiverDifferent]
  rw [WorldState.account?_setAccount_of_ne _ _ _ _ senderDifferent]

/-- Successful transfer execution preserves every unrelated account observation. -/
theorem transferBalance_unrelated_account
    (config : RuntimeConfig)
    (state after : WorldState)
    (sender receiver observed : AccountId)
    (amount : Balance)
    (senderDifferent : observed ≠ sender)
    (receiverDifferent : observed ≠ receiver)
    (success : state.transferBalance config sender receiver amount = .ok after) :
    after.account? observed = state.account? observed := by
  unfold WorldState.transferBalance at success
  split at success
  · contradiction
  · split at success
    · contradiction
    · split at success
      · contradiction
      · split at success
        · cases success
          rfl
        · split at success
          · contradiction
          · cases success
            exact transfer_updates_unrelated_account _ _ _ _ _ _
              senderDifferent receiverDifferent

/-- A concrete successful transfer trace for executable evaluation. -/
def basicTransferExample : WorldState × Except RuntimeError Output :=
  let config := RuntimeConfig.default
  let sender := { Account.initial with balance := 2 }
  let state := { WorldState.initial config with accounts := [([1], sender), ([2], Account.initial)] }
  step config state (.transfer [1] [2] 1)

#eval basicTransferExample

end NEARLean

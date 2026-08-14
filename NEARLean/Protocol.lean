import NEARLean.Blocks

/-!
# Current protocol configuration and sharding

This module models the pinned mainnet protocol version and current shard layout.
It deliberately does not provide historical runtime configurations or migrations.
-/

namespace NEARLean

abbrev ProtocolVersion := Nat
abbrev ShardId := Nat

def currentProtocolVersion : ProtocolVersion := 86

inductive ProtocolFeature where
  | invalidTxGenerateOutcomes
  | wasmtime
  | dynamicResharding
  | enforcePerReceiptStorageProofLimit
  deriving BEq, DecidableEq, Repr

def ProtocolFeature.activationVersion : ProtocolFeature → ProtocolVersion
  | .invalidTxGenerateOutcomes => 83
  | .wasmtime => 84
  | .dynamicResharding => 85
  | .enforcePerReceiptStorageProofLimit => 86

def ProtocolFeature.enabled
    (feature : ProtocolFeature) (version : ProtocolVersion) : Bool :=
  feature.activationVersion ≤ version

structure ShardLayout where
  version : Nat
  boundaryAccounts : List AccountId
  shardIds : List ShardId
  deriving BEq, Repr

def ShardLayout.WellFormed (layout : ShardLayout) : Prop :=
  layout.boundaryAccounts.length + 1 = layout.shardIds.length ∧
    layout.boundaryAccounts.Pairwise (· < ·) ∧
    layout.shardIds.Nodup

instance (layout : ShardLayout) : Decidable layout.WellFormed := by
  unfold ShardLayout.WellFormed
  infer_instance

def ShardLayout.route :
    List AccountId → List ShardId → AccountId → Option ShardId
  | [], [shardId], _ => some shardId
  | boundary :: boundaries, shardId :: shardIds, accountId =>
      if accountId < boundary then
        some shardId
      else
        route boundaries shardIds accountId
  | _, _, _ => none

def ShardLayout.shardId? (layout : ShardLayout) (accountId : AccountId) : Option ShardId :=
  ShardLayout.route layout.boundaryAccounts layout.shardIds accountId

private def accountId (value : String) : AccountId :=
  value.toUTF8.toList

def ShardLayout.currentMainnet : ShardLayout := {
  version := 3
  boundaryAccounts := [
    accountId "650",
    accountId "aurora",
    accountId "aurora-0",
    accountId "earn.kaiching",
    accountId "game.hot.tg",
    accountId "game.hot.tg-0",
    accountId "kkuuue2akv_1630967379.near",
    accountId "tge-lockup.sweat",
    accountId "wallet.ka"
  ]
  shardIds := [10, 11, 1, 8, 9, 6, 7, 4, 12, 13]
}

theorem ShardLayout.currentMainnet_wellFormed :
    ShardLayout.currentMainnet.WellFormed := by
  decide +kernel

theorem ShardLayout.routing_deterministic
    (layout : ShardLayout)
    (account : AccountId)
    (first second : ShardId)
    (firstRoute : layout.shardId? account = some first)
    (secondRoute : layout.shardId? account = some second) :
    first = second := by
  rw [firstRoute] at secondRoute
  exact Option.some.inj secondRoute

inductive ReceiptRoute where
  | local
  | crossShard
  deriving BEq, DecidableEq, Repr

def receiptRoute (source target : ShardId) : ReceiptRoute :=
  if source = target then .local else .crossShard

def receiptDeliveryHeight (height : Nat) (source target : ShardId) : Nat :=
  if source = target then height else height + 1

theorem crossShard_receipt_delayed
    (height : Nat)
    (source target : ShardId)
    (crossShard : source ≠ target) :
    receiptDeliveryHeight height source target = height + 1 := by
  simp [receiptDeliveryHeight, crossShard]

structure RoutedReceipt where
  receipt : Receipt
  sourceShard : ShardId
  targetShard : ShardId
  route : ReceiptRoute
  deliveryHeight : Nat
  deriving BEq, Repr

def ShardLayout.routeReceipt?
    (layout : ShardLayout) (height : Nat) (receipt : Receipt) : Option RoutedReceipt := do
  let source ← layout.shardId? receipt.predecessorId
  let target ← layout.shardId? receipt.receiverId
  return {
    receipt := receipt
    sourceShard := source
    targetShard := target
    route := receiptRoute source target
    deliveryHeight := receiptDeliveryHeight height source target
  }

structure VersionedRuntimeConfig where
  protocolVersion : ProtocolVersion
  runtime : RuntimeConfig
  shardLayout : ShardLayout
  epochLength : Nat
  deriving BEq, Repr

def VersionedRuntimeConfig.current : VersionedRuntimeConfig := {
  protocolVersion := currentProtocolVersion
  runtime := RuntimeConfig.default
  shardLayout := ShardLayout.currentMainnet
  epochLength := 43200
}

def VersionedRuntimeConfig.forVersion?
    (version : ProtocolVersion) : Option VersionedRuntimeConfig :=
  if version = currentProtocolVersion then
    some VersionedRuntimeConfig.current
  else
    none

structure EpochInputs where
  protocolVersion : ProtocolVersion
  epochHeight : Nat
  epochId : List UInt8
  nextEpochId : List UInt8
  validators : List AccountId
  deriving BEq, Repr

def EpochInputs.WellFormed
    (config : VersionedRuntimeConfig) (inputs : EpochInputs) : Prop :=
  inputs.protocolVersion = config.protocolVersion ∧
    !inputs.epochId.isEmpty ∧
    !inputs.nextEpochId.isEmpty ∧
    !inputs.validators.isEmpty ∧
    inputs.validators.Nodup

instance (config : VersionedRuntimeConfig) (inputs : EpochInputs) :
    Decidable (inputs.WellFormed config) := by
  unfold EpochInputs.WellFormed
  infer_instance

inductive ContractProtocolPolicy where
  | fixed (version : ProtocolVersion)
  | range (minimum maximum : ProtocolVersion)
  deriving BEq, Repr

def ContractProtocolPolicy.accepts
    (policy : ContractProtocolPolicy) (version : ProtocolVersion) : Bool :=
  match policy with
  | .fixed fixedVersion => version = fixedVersion
  | .range minimum maximum => minimum ≤ version && version ≤ maximum

def ContractProtocolPolicy.supported : ContractProtocolPolicy → Bool
  | .fixed version => version = currentProtocolVersion
  | .range minimum maximum =>
      minimum = currentProtocolVersion && maximum = currentProtocolVersion

theorem current_fixed_policy_supported :
    (ContractProtocolPolicy.fixed currentProtocolVersion).supported = true := by
  decide

theorem current_range_policy_supported :
    (ContractProtocolPolicy.range currentProtocolVersion currentProtocolVersion).supported = true := by
  decide

theorem activation_boundaries :
    ProtocolFeature.invalidTxGenerateOutcomes.enabled 82 = false ∧
    ProtocolFeature.invalidTxGenerateOutcomes.enabled 83 = true ∧
    ProtocolFeature.wasmtime.enabled 83 = false ∧
    ProtocolFeature.wasmtime.enabled 84 = true ∧
    ProtocolFeature.dynamicResharding.enabled 84 = false ∧
    ProtocolFeature.dynamicResharding.enabled 85 = true ∧
    ProtocolFeature.enforcePerReceiptStorageProofLimit.enabled 85 = false ∧
    ProtocolFeature.enforcePerReceiptStorageProofLimit.enabled 86 = true := by
  decide

end NEARLean

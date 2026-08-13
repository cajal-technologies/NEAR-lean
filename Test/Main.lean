import NEARLean

open NEARLean

private def assertEqual [BEq α] [Repr α] (expected actual : α) : IO Unit :=
  if expected == actual then
    pure ()
  else
    throw <| IO.userError s!"expected {repr expected}, got {repr actual}"

private def expectOk : Except RuntimeError Output → IO Output
  | .ok output => pure output
  | .error runtimeError =>
      throw <| IO.userError s!"expected success, got {repr runtimeError}"

private def expectInit : Except RuntimeError NearChain → IO NearChain
  | .ok chain => pure chain
  | .error runtimeError =>
      throw <| IO.userError s!"expected valid genesis, got {repr runtimeError}"

private def expectValue [BEq α] [Repr α]
    (expected : α) : Except RuntimeError α → IO Unit
  | .ok actual => assertEqual expected actual
  | .error runtimeError =>
      throw <| IO.userError s!"expected {repr expected}, got {repr runtimeError}"

private def expectInitError
    (expected : RuntimeError) : Except RuntimeError NearChain → IO Unit
  | .error actual => assertEqual expected actual
  | .ok chain => throw <| IO.userError s!"expected {repr expected}, got {repr chain}"

private def expectError
    (expected : RuntimeError)
    (before : NearChain)
    (transition : NearChain × Except RuntimeError Output) : IO Unit := do
  assertEqual before transition.1
  match transition.2 with
  | .error actual => assertEqual expected actual
  | .ok output => throw <| IO.userError s!"expected {repr expected}, got {repr output}"

private def funded (amount : Balance) : Account :=
  { Account.initial with balance := amount }

private def runTransferScenarios (config : RuntimeConfig) : IO Unit := do
  for amount in List.range 100 do
    let chain ← expectInit <| NearChain.init config [([1], funded amount), ([2], Account.initial)]
    let (chain, result) := chain.transfer [1] [2] amount
    let _ ← expectOk result
    assertEqual (some 0) (chain.balance? [1])
    assertEqual (some amount) (chain.balance? [2])

def main : IO Unit := do
  assertEqual "abstract" (SemanticsLayer.label .abstract)
  assertEqual "concrete-compatibility" (SemanticsLayer.label .concreteCompatibility)
  let config := RuntimeConfig.default
  let empty := NearChain.initEmpty config

  assertEqual true (WorldState.WellFormed config empty.state |> decide)
  assertEqual false (AccountId.WellFormed config [] |> decide)
  assertEqual false (Storage.WellFormed config [([1], [2]), ([1], [3])] |> decide)
  expectInitError .invalidInitialState (NearChain.init config [([], Account.initial)])

  let (created, createResult) := empty.createAccount [1]
  let _ ← expectOk createResult
  assertEqual (some 0) (created.balance? [1])
  expectError (.accountAlreadyExists [1]) created (created.createAccount [1])
  expectError (.invalidAccountId []) created (created.createAccount [])

  let chain ← expectInit <| NearChain.init config [([1], funded 10), ([2], Account.initial)]
  let (transferred, transferResult) := chain.transfer [1] [2] 4
  let _ ← expectOk transferResult
  assertEqual (some 6) (transferred.balance? [1])
  assertEqual (some 4) (transferred.balance? [2])
  expectError (.insufficientBalance [1]) chain (chain.transfer [1] [2] 11)
  expectError (.accountNotFound [3]) chain (chain.transfer [1] [3] 1)
  let (selfTransfer, selfResult) := chain.transfer [1] [1] 10
  let _ ← expectOk selfResult
  assertEqual chain selfTransfer

  let overflowChain ← expectInit <| NearChain.init config
    [([1], funded 1), ([2], funded config.maxAccountBalance)]
  expectError (.balanceOverflow [2]) overflowChain (overflowChain.transfer [1] [2] 1)

  let counterGenesis := [([1], funded 10), ([2], Account.initial)]
  let counterChain ← expectInit <| NearChain.init config counterGenesis
  let (counterChain, deployResult) := counterChain.deploy [1] [2] NativeContract.counterId
  let _ ← expectOk deployResult
  expectError (.contractAlreadyDeployed [2]) counterChain
    (counterChain.deploy [1] [2] NativeContract.counterId)
  let (counterChain, incrementResult) := counterChain.call [1] [2] NativeMethod.increment
  let incrementOutput ← expectOk incrementResult
  assertEqual [0] incrementOutput.returnValue
  assertEqual [[1]] incrementOutput.logs
  let (counterChain, secondIncrement) := counterChain.call [1] [2] NativeMethod.increment
  let secondOutput ← expectOk secondIncrement
  assertEqual [0, 0] secondOutput.returnValue
  let (viewedChain, viewResult) := counterChain.view [2] NativeMethod.get
  let viewOutput ← expectOk viewResult
  assertEqual counterChain viewedChain
  assertEqual [0, 0] viewOutput.returnValue
  expectError (.methodNotFound [99]) counterChain
    (counterChain.call [1] [2] [99])
  expectError .invalidGas counterChain
    (counterChain.call [1] [2] NativeMethod.increment [] 0 0)

  let escrowGenesis :=
    [([1], funded 10), ([2], Account.initial), ([3], Account.initial), ([4], Account.initial)]
  let escrowChain ← expectInit <| NearChain.init config escrowGenesis
  let (escrowChain, escrowDeploy) := escrowChain.deploy [1] [2] NativeContract.escrowId
  let _ ← expectOk escrowDeploy
  expectError .depositRequired escrowChain
    (escrowChain.call [1] [2] NativeMethod.deposit)
  let (escrowChain, depositResult) := escrowChain.call [1] [2] NativeMethod.deposit [] 4
  let _ ← expectOk depositResult
  assertEqual (some 6) (escrowChain.balance? [1])
  assertEqual (some 4) (escrowChain.balance? [2])
  expectError .unauthorized escrowChain
    (escrowChain.call [4] [2] NativeMethod.release [3])
  expectError .invalidArguments escrowChain
    (escrowChain.call [1] [2] NativeMethod.release [])
  let (escrowChain, releaseResult) := escrowChain.call [1] [2] NativeMethod.release [3]
  let releaseOutput ← expectOk releaseResult
  assertEqual (some 4) releaseOutput.balance
  assertEqual (some 0) (escrowChain.balance? [2])
  assertEqual (some 4) (escrowChain.balance? [3])
  let (viewedEscrow, balanceView) := escrowChain.view [2] NativeMethod.balance
  let balanceOutput ← expectOk balanceView
  assertEqual escrowChain viewedEscrow
  assertEqual (some 0) balanceOutput.balance

  expectValue [0] counterExample
  expectValue 4 escrowExample
  runTransferScenarios config
  IO.println "100 transfer scenarios and Milestone 2 API tests passed"

# Contract-relevant NEAR host environment

Milestone 10 executes five checked-in WebAssembly binaries through Talos at commit
`87336df09b41d819c670be99860481573fd00055`. `CodeLib.Near.Env` supplies the NEAR
ABI semantics; `NEARLean.WasmHost` supplies protocol-86 limits, context, persistent
storage projection, deterministic SHA-256, gas metering, and benchmark promise
resolution.

The benchmark binaries are `counter.wasm`, `escrow.wasm`, `fungible_token.wasm`,
`nft.wasm`, and `async.wasm`. `scripts/wasm_artifacts.mjs` reproducibly compiles
their WAT sources and checks every binary hash. The nearcore oracle loads these
same binary files directly.

Gas constants are copied from the pinned nearcore protocol configuration snapshot
`core/parameters/src/snapshots/near_parameters__config_store__tests__85.json.snap`,
which is the configuration active at protocol 86. Metering includes memory and
register transfer costs, storage base/per-byte/eviction costs, context and output
costs, SHA-256, and promise receipt/action reservation. Gas exhaustion traps as
`GasExceeded` before the host mutation is applied.

`lake exe m10Validation` executes all five contracts, a compiled promise/callback
DAG, exact gas and error boundaries, the SHA-256 `abc` known-answer vector, native
to WASM refinement checks for counter and async observations, and 10,000 generated
compiled `echo` calls. `host/report.json` lists every host function imported by the
corpus and its boundary, error, gas, and differential evidence.

The L5 benchmark trace intentionally leaves receipt graphs and transaction-envelope
economics empty. This is not a claim that M10 reimplements the scheduler or the
transaction fee ledger: those remain covered by the M6 and M7 L4/L5 campaigns.
M10's exactness claim is scoped to host external costs. Arbitrary cross-contract
promise routing and trie-node access charging remain for concrete-state integration.

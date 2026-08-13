(module
  (import "env" "input" (func $input (param i64)))
  (import "env" "signer_account_id" (func $signer_account_id (param i64)))
  (import "env" "sha256" (func $sha256 (param i64 i64 i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "log_utf8" (func $log_utf8 (param i64 i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "nft_mint")
  (func (export "init"))
  (func (export "nft_mint") (local $input_len i64) (local $owner_len i64)
    i64.const 0 call $input
    i64.const 0 call $register_len local.set $input_len
    i64.const 0 i64.const 64 call $read_register
    local.get $input_len i64.const 64 i64.const 1 call $sha256
    i64.const 1 i64.const 256 call $read_register
    i64.const 2 call $signer_account_id
    i64.const 2 call $register_len local.set $owner_len
    i64.const 2 i64.const 512 call $read_register
    i64.const 32 i64.const 256 local.get $owner_len i64.const 512 i64.const 3
    call $storage_write drop
    i64.const 32 i64.const 256 call $value_return
    i64.const 8 i64.const 0 call $log_utf8)
  (func (export "nft_token") (local $input_len i64)
    i64.const 0 call $input
    i64.const 0 call $register_len local.set $input_len
    i64.const 0 i64.const 64 call $read_register
    local.get $input_len i64.const 64 i64.const 1 call $sha256
    i64.const 1 i64.const 256 call $read_register
    i64.const 32 i64.const 256 call $value_return))

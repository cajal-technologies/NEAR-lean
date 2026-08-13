(module
  (import "env" "input" (func $input (param i64)))
  (import "env" "signer_account_id" (func $signer_account_id (param i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "log_utf8" (func $log_utf8 (param i64 i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "ft_mint")
  (data (i32.const 16) "ft_transfer")
  (func (export "init"))
  (func (export "mint") (local $key_len i64) (local $owner_len i64)
    i64.const 0 call $input
    i64.const 0 call $register_len local.set $key_len
    i64.const 0 i64.const 64 call $read_register
    i64.const 1 call $signer_account_id
    i64.const 1 call $register_len local.set $owner_len
    i64.const 1 i64.const 256 call $read_register
    local.get $key_len i64.const 64 local.get $owner_len i64.const 256 i64.const 2
    call $storage_write drop
    i64.const 7 i64.const 0 call $log_utf8)
  (func (export "ft_balance_of") (local $key_len i64) (local $value_len i64)
    i64.const 0 call $input
    i64.const 0 call $register_len local.set $key_len
    i64.const 0 i64.const 64 call $read_register
    local.get $key_len i64.const 64 i64.const 1 call $storage_read drop
    i64.const 1 call $register_len local.set $value_len
    i64.const 1 i64.const 256 call $read_register
    local.get $value_len i64.const 256 call $value_return)
  (func (export "ft_transfer")
    i64.const 11 i64.const 16 call $log_utf8))

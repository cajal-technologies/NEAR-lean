(module
  (type (;0;) (func (param i64)))
  (type (;1;) (func (param i64 i64 i64)))
  (type (;2;) (func (param i64 i64 i64 i64 i64) (result i64)))
  (type (;3;) (func (param i64) (result i64)))
  (type (;4;) (func (param i64 i64)))
  (type (;5;) (func))
  (import "env" "input" (func (;0;) (type 0)))
  (import "env" "signer_account_id" (func (;1;) (type 0)))
  (import "env" "sha256" (func (;2;) (type 1)))
  (import "env" "storage_write" (func (;3;) (type 2)))
  (import "env" "register_len" (func (;4;) (type 3)))
  (import "env" "read_register" (func (;5;) (type 4)))
  (import "env" "value_return" (func (;6;) (type 4)))
  (import "env" "log_utf8" (func (;7;) (type 4)))
  (memory (;0;) 1)
  (export "memory" (memory 0))
  (export "init" (func 8))
  (export "nft_mint" (func 9))
  (export "nft_token" (func 10))
  (func (;8;) (type 5))
  (func (;9;) (type 5)
    (local i64 i64)
    i64.const 0
    call 0
    i64.const 0
    call 4
    local.set 0
    i64.const 0
    i64.const 64
    call 5
    local.get 0
    i64.const 64
    i64.const 1
    call 2
    i64.const 1
    i64.const 256
    call 5
    i64.const 2
    call 1
    i64.const 2
    call 4
    local.set 1
    i64.const 2
    i64.const 512
    call 5
    i64.const 32
    i64.const 256
    local.get 1
    i64.const 512
    i64.const 3
    call 3
    drop
    i64.const 32
    i64.const 256
    call 6
    i64.const 8
    i64.const 0
    call 7
  )
  (func (;10;) (type 5)
    (local i64)
    i64.const 0
    call 0
    i64.const 0
    call 4
    local.set 0
    i64.const 0
    i64.const 64
    call 5
    local.get 0
    i64.const 64
    i64.const 1
    call 2
    i64.const 1
    i64.const 256
    call 5
    i64.const 32
    i64.const 256
    call 6
  )
  (data (;0;) (i32.const 0) "nft_mint")
)

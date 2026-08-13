(module
  (type (;0;) (func (param i64)))
  (type (;1;) (func (param i64 i64 i64 i64 i64) (result i64)))
  (type (;2;) (func (param i64 i64 i64) (result i64)))
  (type (;3;) (func (param i64) (result i64)))
  (type (;4;) (func (param i64 i64)))
  (type (;5;) (func))
  (import "env" "input" (func (;0;) (type 0)))
  (import "env" "attached_deposit" (func (;1;) (type 0)))
  (import "env" "predecessor_account_id" (func (;2;) (type 0)))
  (import "env" "storage_write" (func (;3;) (type 1)))
  (import "env" "storage_read" (func (;4;) (type 2)))
  (import "env" "storage_remove" (func (;5;) (type 2)))
  (import "env" "register_len" (func (;6;) (type 3)))
  (import "env" "read_register" (func (;7;) (type 4)))
  (import "env" "value_return" (func (;8;) (type 4)))
  (import "env" "log_utf8" (func (;9;) (type 4)))
  (memory (;0;) 1)
  (export "memory" (memory 0))
  (export "init" (func 10))
  (export "deposit" (func 11))
  (export "balance" (func 12))
  (export "release" (func 13))
  (func (;10;) (type 5))
  (func (;11;) (type 5)
    i64.const 64
    call 1
    i64.const 7
    i64.const 0
    i64.const 16
    i64.const 64
    i64.const 0
    call 3
    drop
    i64.const 16
    i64.const 64
    call 8
    i64.const 7
    i64.const 16
    call 9
  )
  (func (;12;) (type 5)
    (local i64)
    i64.const 7
    i64.const 0
    i64.const 0
    call 4
    drop
    i64.const 0
    call 6
    local.set 0
    i64.const 0
    i64.const 64
    call 7
    local.get 0
    i64.const 64
    call 8
  )
  (func (;13;) (type 5)
    (local i64)
    i64.const 1
    call 2
    i64.const 0
    call 0
    i64.const 0
    call 6
    local.set 0
    i64.const 0
    i64.const 128
    call 7
    i64.const 7
    i64.const 0
    i64.const 2
    call 5
    drop
    local.get 0
    i64.const 128
    call 8
    i64.const 7
    i64.const 24
    call 9
  )
  (data (;0;) (i32.const 0) "balance")
  (data (;1;) (i32.const 16) "deposit")
  (data (;2;) (i32.const 24) "release")
)

namespace NEARLean.Concrete.Hex

abbrev Bytes := List UInt8

private def digit (value : Nat) : Char :=
  if value < 10 then Char.ofNat (48 + value) else Char.ofNat (87 + value)

def encode (value : Bytes) : String :=
  String.ofList <| value.flatMap fun byte =>
    [digit (byte.toNat / 16), digit (byte.toNat % 16)]

private def value (character : Char) : Option Nat :=
  let code := character.toNat
  if 48 ≤ code ∧ code ≤ 57 then some (code - 48)
  else if 97 ≤ code ∧ code ≤ 102 then some (code - 87)
  else if 65 ≤ code ∧ code ≤ 70 then some (code - 55)
  else none

private def decodeChars : List Char → Option Bytes
  | [] => some []
  | first :: second :: rest => do
      let high ← value first
      let low ← value second
      let tail ← decodeChars rest
      return UInt8.ofNat (high * 16 + low) :: tail
  | _ => none

def decode (encoded : String) : Option Bytes := decodeChars encoded.toList

end NEARLean.Concrete.Hex

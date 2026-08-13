namespace NEARLean.Concrete.Borsh

abbrev Bytes := List UInt8

def littleEndian (width value : Nat) : Bytes :=
  (List.range width).map fun index => UInt8.ofNat (value / (256 ^ index) % 256)

def u8 (value : Nat) : Bytes := littleEndian 1 value

def u16 (value : Nat) : Bytes := littleEndian 2 value

def u32 (value : Nat) : Bytes := littleEndian 4 value

def u64 (value : Nat) : Bytes := littleEndian 8 value

def u128 (value : Nat) : Bytes := littleEndian 16 value

def fixed (width : Nat) (value : Bytes) : Bytes :=
  (value.take width) ++ List.replicate (width - value.length) 0

def bytes (value : Bytes) : Bytes := u32 value.length ++ value

def string (value : String) : Bytes := bytes value.toUTF8.toList

def list (encode : α → Bytes) (values : List α) : Bytes :=
  u32 values.length ++ values.flatMap encode

def option (encode : α → Bytes) : Option α → Bytes
  | none => [0]
  | some value => 1 :: encode value

theorem littleEndian_length : (littleEndian width value).length = width := by
  simp [littleEndian]

theorem bytes_length : (bytes value).length = value.length + 4 := by
  simp [bytes, u32, littleEndian, Nat.add_comm]

end NEARLean.Concrete.Borsh

///|
/// Find one concrete register by its fully qualified dotted name.
pub fn Device::find(self : Device, path : String) -> Register? {
  for reg in self.registers {
    if reg.path == path {
      return Some(reg)
    }
  }
  None
}

///|
/// Return every register at this start address, including alternate views.
pub fn Device::at(self : Device, address : UInt64) -> Array[Register] {
  self.registers.filter(reg => reg.address == address)
}

///|
/// Interpret a register value as one of its named fields.
pub fn Register::decode_field(self : Register, field_name : String, value : UInt64) -> UInt64? {
  for field in self.fields {
    if field.name == field_name {
      let size = self.size.to_uint64()
      if field.bit_width == 0UL || field.bit_offset >= size ||
        field.bit_width > size - field.bit_offset {
        return None
      }
      let shifted = value >> field.bit_offset.to_int()
      let mask = if field.bit_width == 64UL {
        uint_limit
      } else {
        (1UL << field.bit_width.to_int()) - 1UL
      }
      return Some(shifted & mask)
    }
  }
  None
}

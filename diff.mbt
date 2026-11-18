///|
/// One addition, removal or behavioral change in a register map.
pub struct Change {
  path : String
  before : Register?
  after : Register?
  properties : Array[String]
}

///|
fn register_index(registers : Array[Register]) -> Map[String, Register] {
  let indexed = Map([])
  for reg in registers {
    indexed[reg.path] = reg
  }
  indexed
}

///|
fn same_fields(before : Array[Field], after : Array[Field]) -> Bool {
  if before.length() != after.length() {
    return false
  }
  let by_name = Map([])
  for field in before {
    by_name[field.name] = field
  }
  for field in after {
    match by_name.get(field.name) {
      Some(old) if old.bit_offset == field.bit_offset &&
        old.bit_width == field.bit_width && old.access == field.access => ()
      _ => return false
    }
  }
  true
}

///|
fn changed_properties(before : Register, after : Register) -> Array[String] {
  let changed = []
  if before.address != after.address {
    changed.push("address")
  }
  if before.size != after.size {
    changed.push("size")
  }
  if before.access != after.access {
    changed.push("access")
  }
  if before.reset_value != after.reset_value {
    changed.push("resetValue")
  }
  if before.reset_mask != after.reset_mask {
    changed.push("resetMask")
  }
  if before.alternate_register != after.alternate_register ||
    before.alternate_group != after.alternate_group {
    changed.push("alternate")
  }
  if !same_fields(before.fields, after.fields) {
    changed.push("fields")
  }
  changed
}

///|
/// Compare two resolved maps by fully qualified register path.
/// Authoring order and source locations do not affect the result.
pub fn Device::diff(before : Device, after : Device) -> Array[Change] {
  let left = register_index(before.registers)
  let right = register_index(after.registers)
  let changes = []
  for path, reg in left {
    let counterpart = right.get(path)
    let properties = match counterpart {
      Some(current) => changed_properties(reg, current)
      None => ["removed"]
    }
    if !properties.is_empty() {
      changes.push({ path, before: Some(reg), after: counterpart, properties })
    }
  }
  for path, reg in right {
    if !left.contains(path) {
      changes.push({ path, before: None, after: Some(reg), properties: ["added"] })
    }
  }
  changes.sort_by((a, b) => a.path.lexical_compare(b.path))
  changes
}

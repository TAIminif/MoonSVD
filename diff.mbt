///|
/// One addition, removal or behavioral change in a register map.
pub struct Change {
  path : String
  before : Register?
  after : Register?
  properties : Array[String]
  field_changes : Array[FieldChange]
}

///|
/// A field addition, removal, or change inside a register present in both maps.
pub struct FieldChange {
  name : String
  before : Field?
  after : Field?
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
fn append_behavior_changes(
  changed : Array[String],
  before : AccessBehavior,
  after : AccessBehavior,
) -> Unit {
  if before.read_action != after.read_action {
    changed.push("readAction")
  }
  if before.modified_write_values != after.modified_write_values {
    changed.push("modifiedWriteValues")
  }
  if before.write_constraint != after.write_constraint {
    changed.push("writeConstraint")
  }
}

///|
fn changed_field_properties(before : Field, after : Field) -> Array[String] {
  let changed = []
  if before.bit_offset != after.bit_offset {
    changed.push("bitOffset")
  }
  if before.bit_width != after.bit_width {
    changed.push("bitWidth")
  }
  if before.access != after.access {
    changed.push("access")
  }
  append_behavior_changes(changed, before.behavior, after.behavior)
  changed
}

///|
fn diff_fields(
  before : Array[Field],
  after : Array[Field],
) -> Array[FieldChange] {
  let remaining = Map([])
  for field in after {
    remaining[field.name] = field
  }
  let changes = []
  for field in before {
    let counterpart = remaining.get(field.name)
    let properties = match counterpart {
      Some(current) => {
        remaining.remove(field.name)
        changed_field_properties(field, current)
      }
      None => ["removed"]
    }
    if !properties.is_empty() {
      changes.push({
        name: field.name,
        before: Some(field),
        after: counterpart,
        properties,
      })
    }
  }
  for name, field in remaining {
    changes.push({
      name,
      before: None,
      after: Some(field),
      properties: ["added"],
    })
  }
  changes.sort_by((a, b) => a.name.lexical_compare(b.name))
  changes
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
  let before_target = before.alternate_register.map(target => {
    alias_path(before, target)
  })
  let after_target = after.alternate_register.map(target => {
    alias_path(after, target)
  })
  if before_target != after_target ||
    before.alternate_group != after.alternate_group {
    changed.push("alternate")
  }
  append_behavior_changes(changed, before.behavior, after.behavior)
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
    let (properties, field_changes) = match counterpart {
      Some(current) => {
        let properties = changed_properties(reg, current)
        let field_changes = diff_fields(reg.fields, current.fields)
        if !field_changes.is_empty() {
          properties.push("fields")
        }
        (properties, field_changes)
      }
      None => (["removed"], [])
    }
    if !properties.is_empty() {
      changes.push({
        path,
        before: Some(reg),
        after: counterpart,
        properties,
        field_changes,
      })
    }
  }
  for path, reg in right {
    if !left.contains(path) {
      changes.push({
        path,
        before: None,
        after: Some(reg),
        properties: ["added"],
        field_changes: [],
      })
    }
  }
  changes.sort_by((a, b) => a.path.lexical_compare(b.path))
  changes
}

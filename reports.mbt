///|
fn strings(items : Array[String]) -> Json {
  Json::array(items.map(item => Json::string(item)))
}

///|
fn optional_string(value : String?) -> Json {
  match value {
    Some(item) => Json::string(item)
    None => Json::null()
  }
}

///|
fn hex(value : UInt64) -> Json {
  Json::string("0x" + value.to_string(radix=16))
}

///|
fn optional_hex(value : UInt64?) -> Json {
  match value {
    Some(item) => hex(item)
    None => Json::null()
  }
}

///|
fn constraint_json(value : WriteConstraint?) -> Json {
  match value {
    None => Json::null()
    Some(AsRead(enabled)) =>
      { "kind": Json::string("writeAsRead"), "enabled": Json::boolean(enabled) }
    Some(Enumerated(enabled)) =>
      {
        "kind": Json::string("useEnumeratedValues"),
        "enabled": Json::boolean(enabled),
      }
    Some(Range(low, high)) =>
      {
        "kind": Json::string("range"),
        "minimum": hex(low),
        "maximum": hex(high),
      }
  }
}

///|
fn Field::json(self : Field) -> Json {
  {
    "name": Json::string(self.name),
    "bitOffset": Json::string(self.bit_offset.to_string()),
    "bitWidth": Json::string(self.bit_width.to_string()),
    "access": optional_string(self.access),
    "readAction": optional_string(self.behavior.read_action),
    "modifiedWriteValues": optional_string(self.behavior.modified_write_values),
    "writeConstraint": constraint_json(self.behavior.write_constraint),
    "line": Json(self.line),
  }
}

///|
/// Convert to a JSON record. Hex strings preserve all 64 address or value bits.
pub fn Register::json(self : Register) -> Json {
  {
    "path": Json::string(self.path),
    "address": hex(self.address),
    "size": Json(self.size),
    "access": optional_string(self.access),
    "readAction": optional_string(self.behavior.read_action),
    "modifiedWriteValues": optional_string(self.behavior.modified_write_values),
    "writeConstraint": constraint_json(self.behavior.write_constraint),
    "resetValue": optional_hex(self.reset_value),
    "resetMask": optional_hex(self.reset_mask),
    "alternateRegister": optional_string(self.alternate_register),
    "alternateGroup": optional_string(self.alternate_group),
    "fields": Json::array(self.fields.map(Field::json)),
    "line": Json(self.line),
  }
}

///|
pub fn Device::json(self : Device) -> Json {
  {
    "name": Json::string(self.name),
    "version": optional_string(self.version),
    "schemaVersion": optional_string(self.schema_version),
    "peripherals": strings(self.peripherals),
    "registers": Json::array(self.registers.map(Register::json)),
  }
}

///|
pub fn Diagnostic::json(self : Diagnostic) -> Json {
  {
    "code": Json::string(self.code),
    "path": Json::string(self.path),
    "line": Json(self.line),
    "message": Json::string(self.message),
  }
}

///|
fn optional_register(value : Register?) -> Json {
  match value {
    Some(reg) => reg.json()
    None => Json::null()
  }
}

///|
fn optional_field(value : Field?) -> Json {
  match value {
    Some(field) => field.json()
    None => Json::null()
  }
}

///|
pub fn FieldChange::json(self : FieldChange) -> Json {
  {
    "name": Json::string(self.name),
    "properties": strings(self.properties),
    "before": optional_field(self.before),
    "after": optional_field(self.after),
  }
}

///|
pub fn Change::json(self : Change) -> Json {
  {
    "path": Json::string(self.path),
    "properties": strings(self.properties),
    "before": optional_register(self.before),
    "after": optional_register(self.after),
    "fieldChanges": Json::array(self.field_changes.map(FieldChange::json)),
  }
}

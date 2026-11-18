///|
/// A decoded bit field. The offset is numbered from the least significant bit.
pub struct Field {
  name : String
  bit_offset : UInt64
  bit_width : UInt64
  access : String?
  line : Int32
}

///|
/// A concrete register instance after expanding the SVD declarations.
pub struct Register {
  path : String
  parent : String
  name : String
  address : UInt64
  size : Int32
  access : String?
  reset_value : UInt64?
  reset_mask : UInt64?
  alternate_register : String?
  alternate_group : String?
  fields : Array[Field]
  line : Int32
}

///|
/// A resolved CMSIS-SVD device in byte-addressed memory.
pub struct Device {
  name : String
  version : String?
  schema_version : String?
  peripherals : Array[String]
  registers : Array[Register]
}

///|
priv struct RegisterDefaults {
  size : Int32?
  access : String?
  reset_value : UInt64?
  reset_mask : UInt64?
}

///|
fn checked_size(
  value : UInt64?,
  parent : Int32?,
  node : Node,
) -> Int32? raise SvdError {
  match value {
    None => parent
    Some(width) => {
      if width == 0UL || width > 64UL {
        raise node.invalid("register size must be between 1 and 64 bits")
      }
      Some(width.to_int())
    }
  }
}

///|
fn checked_access(
  access : String?,
  parent : String?,
  node : Node,
) -> String? raise SvdError {
  match access {
    None => parent
    Some(
      "read-only"
      | "write-only"
      | "read-write"
      | "writeOnce"
      | "read-writeOnce"
    ) => access
    Some(value) => raise node.invalid("unknown register access '\{value}'")
  }
}

///|
fn Resolved::defaults(
  self : Resolved,
  parent : RegisterDefaults,
) -> RegisterDefaults raise SvdError {
  let node = self.declaration.node
  {
    size: checked_size(self.num("size"), parent.size, node),
    access: checked_access(self.text("access"), parent.access, node),
    reset_value: inherited(self.num("resetValue"), parent.reset_value),
    reset_mask: inherited(self.num("resetMask"), parent.reset_mask),
  }
}

///|
fn bounds(
  low : UInt64,
  high : UInt64,
  node : Node,
) -> (UInt64, UInt64) raise SvdError {
  if high < low {
    raise node.invalid("bit-range high bound precedes its low bound")
  }
  (low, checked_add(high - low, 1UL, node))
}

///|
fn Resolved::range(self : Resolved) -> (UInt64, UInt64) raise SvdError {
  let node = self.declaration.node
  if self.text("bitRange") is Some(raw) {
    let body = raw.strip_prefix("[").bind(text => text.strip_suffix("]"))
    if body is Some(text) {
      let parts = text.split(":").to_array()
      if parts.length() == 2 {
        let high = number(parts[0].trim().to_owned(), node, "bitRange high")
        let low = number(parts[1].trim().to_owned(), node, "bitRange low")
        return bounds(low, high, node)
      }
    }
    raise node.invalid("expected [msb:lsb] in <bitRange>")
  }
  match
    (
      self.num("lsb"),
      self.num("msb"),
      self.num("bitOffset"),
      self.num("bitWidth"),
    ) {
    (Some(low), Some(high), None, None) => bounds(low, high, node)
    (None, None, Some(offset), width) => (offset, width.unwrap_or(1UL))
    _ => raise node.invalid("field requires a complete bit-range declaration")
  }
}

///|
priv struct Expansion {
  resolver : Resolver
  names : Map[String, Bool]
  peripherals : Array[String]
  registers : Array[Register]
  mut count : Int32
}

///|
fn Expansion::record(
  self : Expansion,
  path : String,
  node : Node,
) -> Unit raise SvdError {
  self.count += 1
  if self.count > 250_000 {
    raise node.invalid("SVD expanded instance limit exceeded")
  }
  if self.names.contains(path) {
    raise node.invalid("expanded name collision '\{path}'")
  }
  self.names[path] = true
}

///|
fn Expansion::fields(
  self : Expansion,
  children : Array[String],
  parent : String,
  default_access : String?,
) -> Array[Field] raise SvdError {
  let result = []
  for child in children {
    let resolved = self.resolver.resolve(child)
    let node = resolved.declaration.node
    let (offset, width) = resolved.range()
    let access = checked_access(resolved.text("access"), default_access, node)
    for field in resolved.instances() {
      self.record("\{parent}.\{field.name}", node)
      result.push({
        name: field.name,
        bit_offset: checked_add(offset, field.offset, node),
        bit_width: width,
        access,
        line: node.line,
      })
    }
  }
  result
}

///|
fn Expansion::visit(
  self : Expansion,
  path : String,
  parent : String,
  base : UInt64,
  defaults : RegisterDefaults,
  depth : Int32,
) -> Unit raise SvdError {
  let item = self.resolver.resolve(path)
  let node = item.declaration.node
  if depth >= 32 {
    raise node.invalid("expanded SVD hierarchy exceeds 32 levels")
  }
  let defaults = item.defaults(defaults)
  let address_tag = if node.name == "peripheral" {
    "baseAddress"
  } else {
    "addressOffset"
  }
  let offset = match item.num(address_tag) {
    Some(value) => value
    None => raise node.invalid("missing <\{address_tag}> for '\{path}'")
  }
  for instance in item.instances() {
    let key = if parent == "" {
      instance.name
    } else {
      "\{parent}.\{instance.name}"
    }
    self.record(key, node)
    let address = checked_add(
      checked_add(base, offset, node),
      instance.offset,
      node,
    )
    if node.name == "register" {
      let size = match defaults.size {
        Some(value) => value
        None => raise node.invalid("missing effective register size")
      }
      self.registers.push({
        path: key,
        parent,
        name: instance.name,
        address,
        size,
        access: defaults.access,
        reset_value: defaults.reset_value,
        reset_mask: defaults.reset_mask,
        alternate_register: item.text("alternateRegister"),
        alternate_group: item.text("alternateGroup"),
        fields: self.fields(item.children, key, defaults.access),
        line: node.line,
      })
    } else {
      if node.name == "peripheral" {
        self.peripherals.push(key)
      }
      for child in item.children {
        self.visit(child, key, address, defaults, depth + 1)
      }
    }
  }
}

///|
/// Read a CMSIS-SVD device and resolve its declared register map.
pub fn parse(input : String) -> Device raise SvdError {
  let schema = read_schema(input)
  let node = schema.device
  let unit = node.small("addressUnitBits", 64).unwrap_or(8)
  if unit != 8 {
    raise node.invalid("only 8-bit addressable units are supported")
  }
  let defaults : RegisterDefaults = {
    size: checked_size(
      node.num("size"),
      checked_size(node.num("width"), None, node),
      node,
    ),
    access: checked_access(node.property("access"), None, node),
    reset_value: node.num("resetValue"),
    reset_mask: node.num("resetMask"),
  }
  let expansion : Expansion = {
    resolver: Resolver::new(schema),
    names: Map([]),
    peripherals: [],
    registers: [],
    count: 0,
  }
  for path in schema.roots {
    expansion.visit(path, "", 0UL, defaults, 0)
  }
  {
    name: schema.name,
    version: node.property("version"),
    schema_version: node.attributes.get("schemaVersion"),
    peripherals: expansion.peripherals,
    registers: expansion.registers,
  }
}

///|
fn[T] inherited(own : T?, fallback : T?) -> T? {
  match own {
    Some(_) => own
    None => fallback
  }
}

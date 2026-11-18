///|
/// A semantic diagnostic for a resolved device.
pub struct Diagnostic {
  code : String
  path : String
  line : Int32
  message : String
}

///|
fn finding(
  code : String,
  path : String,
  line : Int32,
  message : String,
) -> Diagnostic {
  { code, path, line, message, }
}

///|
fn bit_checks(reg : Register, output : Array[Diagnostic]) -> Unit {
  let mask = if reg.size == 64 { uint_limit } else { (1UL << reg.size) - 1UL }
  if reg.reset_value is Some(value) && value > mask {
    output.push(
      finding(
        "reset-width",
        reg.path,
        reg.line,
        "reset value is wider than the register",
      ),
    )
  }
  let occupied : Array[Field?] = Array::make(reg.size, None)
  for field in reg.fields {
    let path = "\{reg.path}.\{field.name}"
    let width = reg.size.to_uint64()
    if field.bit_width == 0UL ||
      field.bit_offset >= width ||
      field.bit_width > width - field.bit_offset {
      output.push(
        finding(
          "field-range",
          path,
          field.line,
          "field does not fit in the register",
        ),
      )
      continue
    }
    let mut collision : Field? = None
    for
      bit in field.bit_offset.to_int()..<(field.bit_offset + field.bit_width).to_int() {
      match occupied[bit] {
        Some(previous) => collision = Some(previous)
        None => occupied[bit] = Some(field)
      }
    }
    if collision is Some(previous) {
      output.push(
        finding(
          "field-overlap",
          path,
          field.line,
          "field overlaps '\{previous.name}'",
        ),
      )
    }
  }
}

///|
fn register_width(reg : Register) -> UInt64 {
  ((reg.size + 7) / 8).to_uint64()
}

///|
fn alias_path(reg : Register, target : String) -> String {
  if target.contains(".") {
    target
  } else {
    "\{reg.parent}.\{target}"
  }
}

///|
fn is_register_alias(a : Register, b : Register) -> Bool {
  a.address == b.address &&
  register_width(a) == register_width(b) &&
  (
    (
      (a.access == Some("read-only") && b.access == Some("write-only")) ||
      (b.access == Some("read-only") && a.access == Some("write-only"))
    ) ||
    (
      a.alternate_group is Some(left) &&
      left != "" &&
      b.alternate_group == Some(left) &&
      a.parent == b.parent
    ) ||
    (a.alternate_register is Some(target) && alias_path(a, target) == b.path) ||
    (b.alternate_register is Some(target) && alias_path(b, target) == a.path) ||
    (
      a.alternate_register is Some(left) &&
      b.alternate_register is Some(right) &&
      alias_path(a, left) == alias_path(b, right)
    )
  )
}

///|
/// Inspect field bounds, reset values, alternate-register links and address collisions.
/// Distinct peripherals are checked independently because vendor SVDs can expose alternate views.
pub fn Device::lint(self : Device) -> Array[Diagnostic] {
  let output = []
  let by_path = Map([])
  let by_peripheral : Map[String, Array[Register]] = Map([])
  for reg in self.registers {
    bit_checks(reg, output)
    by_path[reg.path] = reg
    let peripheral = reg.path.split(".").next().unwrap().to_owned()
    match by_peripheral.get(peripheral) {
      Some(group) => group.push(reg)
      None => by_peripheral[peripheral] = [reg]
    }
  }
  for reg in self.registers {
    if reg.alternate_register is Some(target) {
      let path = alias_path(reg, target)
      match by_path.get(path) {
        Some(peer) if peer.path != reg.path &&
          peer.address == reg.address &&
          register_width(peer) == register_width(reg) => ()
        _ =>
          output.push(
            finding(
              "alternate-register",
              reg.path,
              reg.line,
              "invalid alternate register '\{path}'",
            ),
          )
      }
    }
  }
  for _, registers in by_peripheral {
    registers.sort_by((a, b) => {
      if a.address == b.address {
        a.path.lexical_compare(b.path)
      } else {
        a.address.compare(b.address)
      }
    })
    let mut active : Array[(UInt64, Register)] = []
    for reg in registers {
      let extent = register_width(reg) - 1UL
      if reg.address > uint_limit - extent {
        output.push(
          finding(
            "register-range",
            reg.path,
            reg.line,
            "register extends beyond the address space",
          ),
        )
        continue
      }
      let end = reg.address + extent
      active = active.filter(item => item.0 >= reg.address)
      for (_, previous) in active {
        if !is_register_alias(previous, reg) {
          output.push(
            finding(
              "register-overlap",
              reg.path,
              reg.line,
              "address range overlaps '\{previous.path}'",
            ),
          )
          break
        }
      }
      if active.length() == 128 {
        output.push(
          finding(
            "overlap-density",
            reg.path,
            reg.line,
            "more than 128 overlapping registers at this address",
          ),
        )
      } else {
        active.push((end, reg))
      }
    }
  }
  output.sort_by((a, b) => {
    if a.path == b.path {
      a.code.lexical_compare(b.code)
    } else {
      a.path.lexical_compare(b.path)
    }
  })
  output
}

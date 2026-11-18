///|
let uint_limit : UInt64 = 18446744073709551615UL

///|
fn digit_value(c : Char) -> Int32 {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn number(raw : String, node : Node, label : String) -> UInt64 raise SvdError {
  if raw.length() > 128 {
    raise node.invalid(
      "numeric value for \{label} exceeds 128 UTF-16 code units",
    )
  }
  let chars = raw.to_array()
  let mut start = 0
  let mut end = chars.length()
  let mut base = 10
  let mut scale = 1UL
  if end > 0 && chars[0] == '+' {
    start = 1
  }
  if end - start >= 2 &&
    chars[start] == '0' &&
    (chars[start + 1] == 'x' || chars[start + 1] == 'X') {
    start += 2
    base = 16
  } else if end - start >= 2 &&
    chars[start] == '0' &&
    (chars[start + 1] == 'b' || chars[start + 1] == 'B') {
    start += 2
    base = 2
  } else if end > start && chars[start] == '#' {
    start += 1
    base = 2
  }
  if end > start {
    scale = match chars[end - 1] {
      'k' | 'K' => 1024UL
      'm' | 'M' => 1048576UL
      'g' | 'G' => 1073741824UL
      't' | 'T' => 1099511627776UL
      _ => 1UL
    }
    if scale > 1UL {
      end -= 1
    }
  }
  if start >= end {
    raise node.invalid("expected a number for \{label}")
  }
  let radix = base.to_uint64()
  let mut value = 0UL
  for i in start..<end {
    let digit = digit_value(chars[i])
    if digit < 0 || digit >= base {
      raise node.invalid("invalid numeric value for \{label}: '\{raw}'")
    }
    let digit = digit.to_uint64()
    if value > (uint_limit - digit) / radix {
      raise node.invalid("numeric overflow for \{label}")
    }
    value = value * radix + digit
  }
  if value > uint_limit / scale {
    raise node.invalid("scaled value overflows for \{label}")
  }
  value * scale
}

///|
fn Node::num(self : Node, tag : String) -> UInt64? raise SvdError {
  match self.child(tag) {
    Some(child) => Some(number(child.text(), child, tag))
    None => None
  }
}

///|
fn Node::small(self : Node, tag : String, max : Int32) -> Int32? raise SvdError {
  match self.num(tag) {
    Some(value) => {
      if value > max.to_uint64() {
        raise self.invalid("<\{tag}> exceeds \{max}")
      }
      Some(value.to_int())
    }
    None => None
  }
}

///|
fn checked_add(a : UInt64, b : UInt64, at : Node) -> UInt64 raise SvdError {
  if a > uint_limit - b {
    raise at.invalid("address addition overflows 64 bits")
  }
  a + b
}

///|
fn checked_mul(a : UInt64, b : UInt64, at : Node) -> UInt64 raise SvdError {
  if b != 0UL && a > uint_limit / b {
    raise at.invalid("address multiplication overflows 64 bits")
  }
  a * b
}

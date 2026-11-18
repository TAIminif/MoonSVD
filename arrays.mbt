///|
priv struct Instance {
  name : String
  offset : UInt64
}

///|
fn substitutions(
  raw : String?,
  count : Int32,
  node : Node,
) -> Array[String] raise SvdError {
  let values : Array[String] = []
  if raw is Some(text) {
    for segment in text.split(",") {
      if segment.length() > 2 * local_name_limit + 32 {
        raise node.invalid("dimIndex entry is too long")
      }
      let item = segment.trim().to_owned()
      let range = item.split("-").to_array()
      if range.length() == 2 {
        let start_text = range[0].trim().to_owned()
        let end_text = range[1].trim().to_owned()
        let start_chars = start_text.to_array()
        let end_chars = end_text.to_array()
        if start_chars.length() == 1 &&
          end_chars.length() == 1 &&
          (
            (start_chars[0] >= 'A' && end_chars[0] <= 'Z') ||
            (start_chars[0] >= 'a' && end_chars[0] <= 'z')
          ) &&
          start_chars[0] <= end_chars[0] {
          for code in start_chars[0].to_int()..<=end_chars[0].to_int() {
            values.push(code.unsafe_to_char().to_string())
          }
        } else {
          let first = number(start_text, node, "dimIndex start")
          let last = number(end_text, node, "dimIndex end")
          if last < first ||
            last > 100_000UL ||
            last - first >= count.to_uint64() {
            raise node.invalid("invalid or oversized dimIndex range '\{item}'")
          }
          for index in first.to_int()..<=last.to_int() {
            values.push(index.to_string())
          }
        }
      } else if range.length() == 1 &&
        item != "" &&
        !item.contains(".") &&
        !item.contains("%") {
        values.push(item)
      } else {
        raise node.invalid("invalid dimIndex entry '\{item}'")
      }
      if values.length() > count {
        raise node.invalid("dimIndex has more than dim entries")
      }
    }
  } else {
    for i in 0..<count {
      values.push(i.to_string())
    }
  }
  if values.length() != count {
    raise node.invalid("dimIndex count does not match dim")
  }
  let seen = Map([])
  for value in values {
    if seen.contains(value) {
      raise node.invalid("duplicate dimIndex '\{value}'")
    }
    seen[value] = true
  }
  values
}

///|
fn expand_instances(
  name : String,
  dim : UInt64?,
  stride : UInt64?,
  raw_index : String?,
  node : Node,
) -> Array[Instance] raise SvdError {
  match (dim, stride) {
    (None, None) => {
      if raw_index is Some(_) || name.contains("%s") {
        raise node.invalid(
          "array name or dimIndex requires <dim> and <dimIncrement>",
        )
      }
      [{ name, offset: 0UL, }]
    }
    (Some(count), Some(stride)) => {
      if count == 0UL ||
        count > 4096UL ||
        stride == 0UL ||
        name.split("%s").to_array().length() != 2 {
        raise node.invalid(
          "expected dim 1..4096, positive increment and one %s in array name",
        )
      }
      let labels = substitutions(raw_index, count.to_int(), node)
      let instances = []
      for i, label in labels {
        if name.length() + label.length() - 2 > local_name_limit {
          raise node.invalid(
            "expanded array name exceeds 256 UTF-16 code units",
          )
        }
        instances.push({
          name: name.replace_all(old="%s", new=label),
          offset: checked_mul(i.to_uint64(), stride, node),
        })
      }
      instances
    }
    _ => raise node.invalid("dim and dimIncrement must occur together")
  }
}

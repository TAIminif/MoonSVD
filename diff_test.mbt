///|
fn variant(body : String) -> @moonsvd.Device raise @moonsvd.SvdError {
  @moonsvd.parse(
    "<device><name>D</name><width>32</width><peripherals><peripheral><name>P</name><baseAddress>0</baseAddress><registers>" +
    body +
    "</registers></peripheral></peripherals></device>",
  )
}

///|
test "semantic diff reports added removed and changed registers in stable order" {
  let left = variant(
    "<register><name>R</name><addressOffset>4</addressOffset><access>read-only</access></register><register><name>DELETED</name><addressOffset>12</addressOffset></register>",
  )
  let right = variant(
    "<register><name>ADD</name><addressOffset>20</addressOffset></register><register><name>R</name><addressOffset>8</addressOffset><access>read-write</access></register>",
  )
  let changes = left.diff(right)
  assert_eq(changes.map(change => change.path), ["P.ADD", "P.DELETED", "P.R"])
  assert_eq(changes[0].properties, ["added"])
  assert_true(changes[0].before is None)
  assert_true(changes[0].field_changes.is_empty())
  assert_eq(changes[1].properties, ["removed"])
  assert_true(changes[1].after is None)
  assert_true(changes[1].field_changes.is_empty())
  assert_eq(changes[2].properties, ["address", "access"])
  assert_eq(changes[2].after.unwrap().address, 8UL)
}

///|
test "semantic diff ignores field order and detects field changes" {
  let prefix = "<register><name>R</name><addressOffset>0</addressOffset><fields>"
  let suffix = "</fields></register>"
  let a = "<field><name>A</name><bitOffset>0</bitOffset></field>"
  let b = "<field><name>B</name><bitOffset>4</bitOffset></field>"
  let edited = "<field><name>B</name><bitOffset>5</bitOffset></field>"
  let left = variant(prefix + a + b + suffix)
  assert_true(left.diff(variant(prefix + b + a + suffix)).is_empty())
  let changes = left.diff(variant(prefix + edited + a + suffix))
  assert_eq(changes[0].properties, ["fields"])
  let field_change = changes[0].field_changes[0]
  assert_eq(field_change.name, "B")
  assert_eq(field_change.properties, ["bitOffset"])
  assert_eq(field_change.before.unwrap().bit_offset, 4UL)
  assert_eq(field_change.after.unwrap().bit_offset, 5UL)
}

///|
test "diff finds access side effects even when address and width are unchanged" {
  let prefix = "<register><name>STATUS</name><addressOffset>0</addressOffset>"
  let suffix = "</fields></register>"
  let left = variant(
    prefix +
    "<readAction>clear</readAction><fields><field><name>OLD</name><bitOffset>4</bitOffset></field><field><name>PENDING</name><bitOffset>0</bitOffset><modifiedWriteValues>oneToClear</modifiedWriteValues></field>" +
    suffix,
  )
  let right = variant(
    prefix +
    "<readAction>modifyExternal</readAction><fields><field><name>ADDED</name><bitOffset>4</bitOffset></field><field><name>PENDING</name><bitOffset>0</bitOffset><modifiedWriteValues>oneToSet</modifiedWriteValues></field>" +
    suffix,
  )
  let change = left.diff(right)[0]
  assert_eq(change.properties, ["readAction", "fields"])
  assert_eq(change.field_changes.map(entry => entry.name), [
    "ADDED", "OLD", "PENDING",
  ])
  assert_eq(change.field_changes[0].properties, ["added"])
  assert_eq(change.field_changes[1].properties, ["removed"])
  assert_eq(change.field_changes[2].properties, ["modifiedWriteValues"])
  assert_eq(
    change.field_changes[2].before.unwrap().behavior.modified_write_values,
    Some("oneToClear"),
  )
  assert_eq(
    change.field_changes[2].after.unwrap().behavior.modified_write_values,
    Some("oneToSet"),
  )
}

///|
test "diff compares alternate register references by their qualified paths" {
  let originals =
    #|<register><name>A</name><addressOffset>0</addressOffset></register>
    #|<register><name>B</name><addressOffset>0</addressOffset><alternateRegister>A</alternateRegister></register>
  let alias_xml = "<register><name>C</name><addressOffset>0</addressOffset><alternateRegister>A</alternateRegister></register>"
  let unqualified = variant(originals + alias_xml)
  let qualified = variant(
    originals +
    alias_xml.replace_all(
      old=">A</alternateRegister>",
      new=">P.A</alternateRegister>",
    ),
  )
  assert_true(unqualified.diff(qualified).is_empty())
  let different = variant(
    originals +
    alias_xml.replace_all(
      old=">A</alternateRegister>",
      new=">B</alternateRegister>",
    ),
  )
  let changes = unqualified.diff(different)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].path, "P.C")
  assert_eq(changes[0].properties, ["alternate"])
}

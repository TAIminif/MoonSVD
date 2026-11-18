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
  assert_eq(changes[1].properties, ["removed"])
  assert_true(changes[1].after is None)
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
}

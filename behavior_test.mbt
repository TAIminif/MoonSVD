///|
fn access_device(body : String) -> @moonsvd.Device raise @moonsvd.SvdError {
  @moonsvd.parse(
    "<device><name>Demo</name><width>32</width><peripherals><peripheral><name>P</name><baseAddress>0</baseAddress><registers>" +
    body +
    "</registers></peripheral></peripherals></device>",
  )
}

///|
test "read and write behavior keep SVD declarations and write constraint overrides" {
  let xml =
    #|<register><name>STATUS</name><addressOffset>0</addressOffset>
    #| <modifiedWriteValues>oneToClear</modifiedWriteValues>
    #| <readAction>modifyExternal</readAction>
    #| <writeConstraint><useEnumeratedValues>1</useEnumeratedValues></writeConstraint>
    #| <fields>
    #|  <field><name>PENDING</name><bitOffset>0</bitOffset><readAction>clear</readAction><modifiedWriteValues>zeroToClear</modifiedWriteValues></field>
    #|  <field><name>LEVEL</name><bitOffset>4</bitOffset><bitWidth>4</bitWidth><writeConstraint><range><minimum>2</minimum><maximum>5</maximum></range></writeConstraint></field>
    #|  <field><name>RAW</name><bitOffset>8</bitOffset><writeConstraint><useEnumeratedValues>false</useEnumeratedValues></writeConstraint></field>
    #| </fields>
    #|</register>
    #|<register derivedFrom="STATUS"><name>COPY</name><addressOffset>4</addressOffset></register>
  let device = access_device(xml)
  for name in ["P.STATUS", "P.COPY"] {
    let register = device.find(name).unwrap()
    assert_eq(register.behavior.read_action, Some("modifyExternal"))
    assert_eq(register.behavior.modified_write_values, Some("oneToClear"))
    assert_true(register.behavior.write_constraint is Some(Enumerated(true)))
    assert_eq(register.fields[0].behavior.read_action, Some("clear"))
    assert_eq(
      register.fields[0].behavior.modified_write_values,
      Some("zeroToClear"),
    )
    assert_true(
      register.fields[0].behavior.write_constraint is Some(Enumerated(true)),
    )
    assert_true(
      register.fields[1].behavior.write_constraint is Some(Range(2UL, 5UL)),
    )
    assert_true(register.fields[1].behavior.read_action is None)
    assert_true(register.fields[1].behavior.modified_write_values is None)
    assert_true(
      register.fields[2].behavior.write_constraint is Some(Enumerated(false)),
    )
  }
}

///|
test "reject invalid side effects and malformed write constraints with source locations" {
  let prefix = "<register><name>R</name><addressOffset>0</addressOffset>\n"
  for
    (tag, expected) in [
      ("<readAction>toggle</readAction>", "readAction"),
      (
        "<modifiedWriteValues>writeOne</modifiedWriteValues>", "modifiedWriteValues",
      ),
      (
        "<writeConstraint><writeAsRead>yes</writeAsRead></writeConstraint>", "expected an XML boolean",
      ),
      (
        "<writeConstraint><range><minimum>2</minimum><maximum>1</maximum></range></writeConstraint>",
        "minimum exceeds maximum",
      ),
      (
        "<writeConstraint><writeAsRead>true</writeAsRead><useEnumeratedValues>true</useEnumeratedValues></writeConstraint>",
        "exactly one choice",
      ),
      (
        "<writeConstraint><range><maximum>1</maximum></range></writeConstraint>",
        "minimum and maximum",
      ),
    ] {
    try access_device(prefix + tag + "</register>") catch {
      error => {
        assert_true(error.message().contains("line 2"))
        assert_true(error.message().contains(expected))
      }
    } noraise {
      _ => fail("expected invalid access behavior")
    }
  }
}

///|
test "Nordic write-once spellings preserve field inheritance and produce no diff" {
  let canonical =
    #|<register><name>R</name><addressOffset>0</addressOffset><access>read-writeOnce</access><fields>
    #|<field><name>F</name><bitOffset>0</bitOffset><access>writeOnce</access></field>
    #|<field><name>G</name><bitOffset>1</bitOffset></field>
    #|</fields></register>
  let vendor = canonical.replace_all(old="Once", new="once")
  let before = access_device(canonical)
  let after = access_device(vendor)
  let register = after.find("P.R").unwrap()
  assert_eq(register.access, Some("read-writeOnce"))
  assert_eq(register.fields[0].access, Some("writeOnce"))
  assert_eq(register.fields[1].access, Some("read-writeOnce"))
  assert_true(before.diff(after).is_empty())
  let unknown = canonical.replace_all(
    old="read-writeOnce",
    new="read-Writeonce",
  )
  try access_device(unknown) catch {
    error => assert_true(error.message().contains("unknown register access"))
  } noraise {
    _ => fail("expected an unknown access token to fail")
  }
}

///|
test "lint reports distinct input faults including bad ranges and missing aliases" {
  let input =
    #|<device><name>D</name><size>16</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0x1000</baseAddress><registers>
    #|<register><name>R</name><addressOffset>0</addressOffset><resetValue>0x1ffff</resetValue><fields>
    #|<field><name>A</name><bitOffset>0</bitOffset><bitWidth>4</bitWidth></field>
    #|<field><name>B</name><bitOffset>1</bitOffset><bitWidth>1</bitWidth></field>
    #|<field><name>C</name><bitOffset>15</bitOffset><bitWidth>2</bitWidth></field>
    #|</fields></register><register><name>S</name><addressOffset>1</addressOffset>
    #|<alternateRegister>NOPE</alternateRegister></register></registers></peripheral></peripherals></device>
  let device = @moonsvd.parse(input)
  let diagnostics = device.lint()
  assert_eq(diagnostics.map(item => item.code), [
    "reset-width", "field-overlap", "field-range", "alternate-register", "register-overlap",
  ])
  assert_eq(diagnostics[2].path, "P.R.C")
  assert_true(diagnostics[2].line > 0)
}

///|
test "an authored alternate register and a peripheral alias do not collide" {
  let input =
    #|<device><name>D</name><size>32</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0x1000</baseAddress><registers>
    #|<register><name>R</name><addressOffset>0</addressOffset></register>
    #|<register><name>ALT_R</name><addressOffset>0</addressOffset><alternateRegister>R</alternateRegister></register>
    #|</registers></peripheral>
    #|<peripheral derivedFrom="P"><name>Q</name><baseAddress>0x1000</baseAddress></peripheral>
    #|</peripherals></device>
  let device = @moonsvd.parse(input)
  assert_eq(device.lint().length(), 0)
}

///|
test "split read and write views are allowed but a second write view conflicts" {
  let prefix =
    #|<device><name>Split</name><width>32</width><peripherals>
    #|<peripheral><name>P</name><baseAddress>0</baseAddress><registers>
    #|<register><name>A_RD</name><addressOffset>0</addressOffset><access>read-only</access></register>
    #|<register><name>B_WR</name><addressOffset>0</addressOffset><access>write-only</access></register>
  let end = "</registers></peripheral></peripherals></device>"
  assert_true(@moonsvd.parse(prefix + end).lint().is_empty())
  let extra = "<register><name>C_WR</name><addressOffset>0</addressOffset><access>write-only</access></register>"
  let findings = @moonsvd.parse(prefix + extra + end).lint()
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].path, "P.C_WR")
  assert_true(findings[0].message.contains("P.B_WR"))
}

///|
test "lint checks reset masks and write ranges against effective widths" {
  let input =
    #|<device><name>D</name><size>8</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0</baseAddress><registers>
    #|<register><name>R</name><addressOffset>0</addressOffset><resetMask>0x100</resetMask>
    #|<writeConstraint><range><minimum>0</minimum><maximum>256</maximum></range></writeConstraint>
    #|<fields><field><name>F</name><bitOffset>0</bitOffset><bitWidth>4</bitWidth>
    #|<writeConstraint><range><minimum>0</minimum><maximum>16</maximum></range></writeConstraint>
    #|</field></fields></register>
    #|</registers></peripheral></peripherals></device>
  let findings = @moonsvd.parse(input).lint()
  assert_eq(findings.map(item => (item.path, item.code)), [
    ("P.R", "reset-mask-width"),
    ("P.R", "write-constraint-width"),
    ("P.R.F", "write-constraint-width"),
  ])
  assert_true(findings.all(item => item.line > 0))
}

///|
test "lint accepts full width masks and inherited field range overrides" {
  for
    (size, maximum) in [
      (8, "0xff"),
      (63, "0x7fffffffffffffff"),
      (64, "0xffffffffffffffff"),
    ] {
    let prefix =
      #|<device><name>D</name><peripherals>
      #|<peripheral><name>P</name><baseAddress>0</baseAddress><registers>
      #|<register><name>R</name><addressOffset>0</addressOffset>
    let properties = "<size>\{size}</size><resetValue>\{maximum}</resetValue><resetMask>\{maximum}</resetMask>" +
      "<writeConstraint><range><minimum>0</minimum><maximum>\{maximum}</maximum></range></writeConstraint>"
    let suffix =
      #|<fields><field><name>F</name><bitOffset>0</bitOffset><bitWidth>4</bitWidth>
      #|<writeConstraint><range><minimum>0</minimum><maximum>15</maximum></range></writeConstraint>
      #|</field></fields></register>
      #|<register derivedFrom="R"><name>COPY</name><addressOffset>8</addressOffset></register>
      #|</registers></peripheral></peripherals></device>
    assert_true(@moonsvd.parse(prefix + properties + suffix).lint().is_empty())
  }
}

///|
test "field read and write views keep separate collision tracking" {
  let prefix =
    #|<device><name>D</name><size>8</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0</baseAddress><registers>
    #|<register><name>R</name><addressOffset>0</addressOffset><fields>
  let suffix = "</fields></register></registers></peripheral></peripherals></device>"
  for write_access in ["write-only", "writeOnce"] {
    let views = "<field><name>A_READ</name><bitOffset>0</bitOffset><bitWidth>4</bitWidth><access>read-only</access></field>" +
      "<field><name>B_WRITE</name><bitOffset>0</bitOffset><bitWidth>4</bitWidth><access>\{write_access}</access></field>"
    assert_true(@moonsvd.parse(prefix + views + suffix).lint().is_empty())
    for
      (name, access, previous) in [
        ("C_READ", "read-only", "A_READ"),
        ("C_WRITE", write_access, "B_WRITE"),
      ] {
      let duplicate = "<field><name>\{name}</name><bitOffset>0</bitOffset><access>\{access}</access></field>"
      let findings = @moonsvd.parse(prefix + views + duplicate + suffix).lint()
      assert_eq(findings.length(), 1)
      assert_eq(findings[0].code, "field-overlap")
      assert_eq(findings[0].path, "P.R.\{name}")
      assert_true(findings[0].message.contains(previous))
    }
  }
}

///|
test "register write-once views are paired with read-only views" {
  let prefix =
    #|<device><name>D</name><size>8</size><peripherals>
    #|<peripheral><name>P</name><baseAddress>0</baseAddress><registers>
    #|<register><name>A_READ</name><addressOffset>0</addressOffset><access>read-only</access></register>
    #|<register><name>B_WRITE</name><addressOffset>0</addressOffset><access>writeOnce</access></register>
  let suffix = "</registers></peripheral></peripherals></device>"
  assert_true(@moonsvd.parse(prefix + suffix).lint().is_empty())
  let duplicate = "<register><name>C_WRITE</name><addressOffset>0</addressOffset><access>write-only</access></register>"
  let findings = @moonsvd.parse(prefix + duplicate + suffix).lint()
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].code, "register-overlap")
  assert_eq(findings[0].path, "P.C_WRITE")
  assert_true(findings[0].message.contains("P.B_WRITE"))
}

///|
test "alternate register chains resolve transitively in both declaration orders" {
  let prefix = "<device><name>D</name><size>32</size><peripherals><peripheral><name>P</name><baseAddress>0</baseAddress><registers>"
  let suffix = "</registers></peripheral></peripherals></device>"
  let a = "<register><name>A</name><addressOffset>0</addressOffset></register>"
  let b = "<register><name>B</name><addressOffset>0</addressOffset><alternateRegister>A</alternateRegister></register>"
  let c = "<register><name>C</name><addressOffset>0</addressOffset><alternateRegister>B</alternateRegister></register>"
  for body in [a + b + c, c + b + a] {
    assert_true(@moonsvd.parse(prefix + body + suffix).lint().is_empty())
  }
}

///|
test "cyclic or incompatible alternate chains fail for each dependent register" {
  let prefix = "<device><name>D</name><size>32</size><peripherals><peripheral><name>P</name><baseAddress>0</baseAddress><registers>"
  let suffix = "</registers></peripheral></peripherals></device>"
  for target in ["B", "MISSING"] {
    let body = "<register><name>A</name><addressOffset>0</addressOffset><alternateRegister>\{target}</alternateRegister></register>" +
      "<register><name>B</name><addressOffset>0</addressOffset><alternateRegister>A</alternateRegister></register>" +
      "<register><name>C</name><addressOffset>0</addressOffset><alternateRegister>B</alternateRegister></register>"
    let findings = @moonsvd.parse(prefix + body + suffix).lint()
    let aliases = findings.filter(item => item.code == "alternate-register")
    assert_eq(aliases.map(item => item.path), ["P.A", "P.B", "P.C"])
  }
  let incompatible = "<register><name>A</name><addressOffset>4</addressOffset></register>" +
    "<register><name>B</name><addressOffset>0</addressOffset><alternateRegister>A</alternateRegister></register>" +
    "<register><name>C</name><addressOffset>0</addressOffset><alternateRegister>B</alternateRegister></register>"
  let findings = @moonsvd.parse(prefix + incompatible + suffix).lint()
  assert_eq(
    findings
    .filter(item => item.code == "alternate-register")
    .map(item => item.path),
    ["P.B", "P.C"],
  )
}

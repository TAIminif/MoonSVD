///|
test "concrete peripheral, nested clusters, arrays and field inheritance" {
  let input =
    #|<device schemaVersion="1.3"><name>TimerBoard</name><version>1</version>
    #|<addressUnitBits>8</addressUnitBits><width>32</width><access>read-write</access>
    #|<resetValue>0</resetValue><peripherals>
    #|<peripheral><name>TIMER0</name><baseAddress>0x40000000</baseAddress>
    #|<registers><cluster><name>BANK[%s]</name><addressOffset>32</addressOffset><dim>2</dim><dimIncrement>16</dimIncrement>
    #|<register><name>CFG</name><addressOffset>4</addressOffset><size>16</size>
    #|<fields><field><name>MODE</name><bitRange>[3:2]</bitRange></field>
    #|<field derivedFrom="MODE"><name>ENABLE</name><bitOffset>5</bitOffset><bitWidth>1</bitWidth><access>read-only</access></field>
    #|</fields></register></cluster></registers></peripheral>
    #|<peripheral derivedFrom="TIMER0"><name>TIMER1</name><baseAddress>0x40000100</baseAddress></peripheral>
    #|</peripherals></device>
  let device = @moonsvd.parse(input)
  assert_eq(device.name, "TimerBoard")
  assert_eq(device.version, Some("1"))
  assert_eq(device.schema_version, Some("1.3"))
  assert_eq(device.peripherals, ["TIMER0", "TIMER1"])
  assert_eq(device.registers.length(), 4)
  let reg = device.registers[3]
  assert_eq(reg.path, "TIMER1.BANK[1].CFG")
  assert_eq(reg.address, 0x40000134UL)
  assert_eq(reg.size, 16)
  assert_eq(reg.reset_value, Some(0UL))
  assert_eq(reg.fields[0].bit_offset, 2UL)
  assert_eq(reg.fields[0].bit_width, 2UL)
  assert_eq(reg.fields[1].bit_offset, 5UL)
  assert_eq(reg.fields[1].access, Some("read-only"))
}

///|
test "invalid effective address and unsupported addressing raise typed errors" {
  let fragment =
    #|<width>32</width><peripherals><peripheral><name>P</name>
    #|<baseAddress>0xffffffffffffffff</baseAddress><registers>
    #|<register><name>R</name><addressOffset>1</addressOffset></register>
    #|</registers></peripheral></peripherals>
  for units in [8, 16] {
    let input = "<device><name>D</name><addressUnitBits>\{units}</addressUnitBits>" +
      fragment +
      "</device>"
    try @moonsvd.parse(input) catch {
      error =>
        assert_true(
          error
          .message()
          .contains(if units == 8 { "overflows" } else { "addressable" }),
        )
    } noraise {
      _ => fail("invalid device parsed")
    }
  }
}

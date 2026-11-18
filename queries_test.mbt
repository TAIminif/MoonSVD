///|
test "query chip registers by path and exact address with 64-bit field decoding" {
  let input =
    #|<device><name>D</name><size>64</size><peripherals><peripheral><name>RCC</name>
    #|<baseAddress>0x40000000</baseAddress><registers><register><name>CR</name>
    #|<addressOffset>0</addressOffset><fields>
    #|<field><name>FULL</name><lsb>0</lsb><msb>63</msb></field>
    #|<field><name>TOP</name><bitOffset>60</bitOffset><bitWidth>4</bitWidth></field>
    #|<field><name>OUT</name><bitOffset>64</bitOffset></field>
    #|</fields></register></registers></peripheral></peripherals></device>
  let device = @moonsvd.parse(input)
  let reg = device.find("RCC.CR").unwrap()
  assert_eq(device.at(0x40000000UL).length(), 1)
  assert_true(device.at(0x40000001UL).is_empty())
  assert_true(device.find("CR") is None)
  assert_eq(reg.decode_field("FULL", 0xF000000000000001UL), Some(0xF000000000000001UL))
  assert_eq(reg.decode_field("TOP", 0xF000000000000001UL), Some(15UL))
  assert_true(reg.decode_field("OUT", 0UL) is None)
}

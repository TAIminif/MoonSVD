///|
fn main {
  let xml =
    #|<device><name>Demo</name><width>32</width><peripherals>
    #|<peripheral><name>TIMER</name><baseAddress>0x40000000</baseAddress>
    #|<registers><register><name>CTRL</name><addressOffset>4</addressOffset>
    #|<fields><field><name>EN</name><bitOffset>0</bitOffset></field></fields>
    #|</register></registers></peripheral></peripherals></device>
  let device = try! @svd.parse(xml)
  let control = device.find("TIMER.CTRL").unwrap()
  let enabled = control.decode_field("EN", 1UL).unwrap()
  println(
    "\{control.path} @ \{control.address.to_string(radix=16)}, EN=\{enabled}",
  )
}

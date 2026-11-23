///|
priv struct Declaration {
  path : String
  scope : String
  name : String
  node : Node
  children : Array[String]
}

///|
priv struct Schema {
  device : Node
  name : String
  roots : Array[String]
  declarations : Map[String, Declaration]
}

///|
let local_name_limit = 256

///|
let qualified_name_limit = 4096

///|
priv struct NameBudget {
  mut remaining : Int32
}

///|
fn NameBudget::new() -> NameBudget {
  { remaining: 8_388_608, }
}

///|
fn NameBudget::reserve(
  self : NameBudget,
  path : String,
  at : Node,
) -> Unit raise SvdError {
  let length = path.length()
  if length > qualified_name_limit {
    raise at.invalid("SVD qualified name exceeds 4096 UTF-16 code units")
  }
  if length > self.remaining {
    raise at.invalid("SVD cumulative name limit exceeded")
  }
  self.remaining -= length
}

///|
fn Node::identifier(self : Node) -> String raise SvdError {
  let tag = self.required("name")
  let value = tag.text()
  if value.length() > local_name_limit {
    raise tag.invalid("SVD local name exceeds 256 UTF-16 code units")
  }
  if value == "" || value.contains(".") {
    raise tag.invalid("expected a nonempty local identifier without '.'")
  }
  value
}

///|
fn add_declarations(
  owner : Node,
  scope : String,
  declarations : Map[String, Declaration],
  names : NameBudget,
) -> Array[String] raise SvdError {
  let (container, first_tag, second_tag) = match owner.name {
    "device" => (Some(owner.required("peripherals")), "peripheral", "")
    "peripheral" => (owner.child("registers"), "register", "cluster")
    "cluster" => (Some(owner), "register", "cluster")
    "register" => (owner.child("fields"), "field", "")
    _ => (None, "", "")
  }
  let paths = []
  if container is Some(container) {
    for child in container.children {
      if child.name == first_tag || child.name == second_tag {
        let name = child.identifier()
        let path = if scope == "" { name } else { "\{scope}.\{name}" }
        names.reserve(path, child)
        if declarations.contains(path) {
          raise child.invalid("duplicate definition '\{path}'")
        }
        let children = add_declarations(child, path, declarations, names)
        declarations[path] = { path, scope, name, node: child, children, }
        paths.push(path)
      } else if container.name == "peripherals" ||
        container.name == "registers" ||
        container.name == "fields" {
        raise child.invalid(
          "unexpected <\{child.name}> within <\{container.name}>",
        )
      }
    }
  }
  paths
}

///|
fn read_schema(input : String) -> Schema raise SvdError {
  let device = read_tree(input)
  if device.name != "device" {
    raise device.invalid("expected CMSIS-SVD <device> root")
  }
  let name_tag = device.required("name")
  let name = name_tag.text()
  if name == "" || name.length() > local_name_limit {
    raise name_tag.invalid("device name must contain 1..256 UTF-16 code units")
  }
  let declarations = Map([])
  let roots = add_declarations(device, "", declarations, NameBudget::new())
  if roots.is_empty() {
    raise device.invalid("expected at least one peripheral")
  }
  { device, name, roots, declarations, }
}

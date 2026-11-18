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
fn Node::identifier(self : Node) -> String raise SvdError {
  let tag = self.required("name")
  let value = tag.text()
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
        if declarations.contains(path) {
          raise child.invalid("duplicate definition '\{path}'")
        }
        let children = add_declarations(child, path, declarations)
        declarations[path] = { path, scope, name, node: child, children }
        paths.push(path)
      } else if container.name == "peripherals" || container.name == "registers" ||
        container.name == "fields" {
        raise child.invalid("unexpected <\{child.name}> within <\{container.name}>")
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
  let name = device.identifier()
  let declarations = Map([])
  let roots = add_declarations(device, "", declarations)
  if roots.is_empty() {
    raise device.invalid("expected at least one peripheral")
  }
  { device, name, roots, declarations }
}

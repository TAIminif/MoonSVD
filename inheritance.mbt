///|
priv struct Resolved {
  declaration : Declaration
  values : Map[String, Node]
  children : Array[String]
}

///|
priv struct Resolver {
  schema : Schema
  active : Map[String, Bool]
  cached : Map[String, Resolved]
}

///|
fn Resolver::new(schema : Schema) -> Resolver {
  { schema, active: Map([]), cached: Map([]) }
}

///|
fn Resolver::definition(self : Resolver, path : String) -> Declaration {
  self.schema.declarations.get(path).unwrap()
}

///|
fn Resolver::reference(
  self : Resolver,
  item : Declaration,
  reference : String,
) -> String raise SvdError {
  if reference == "" {
    raise item.node.invalid("empty derivedFrom in '\{item.path}'")
  }
  let target = if item.scope != "" && !reference.contains(".") {
    "\{item.scope}.\{reference}"
  } else {
    reference
  }
  match self.schema.declarations.get(target) {
    Some(decl) if decl.node.name == item.node.name => target
    Some(_) => raise item.node.invalid("incorrect kind for derivedFrom '\{target}'")
    None => raise item.node.invalid("unknown derivedFrom '\{target}' in '\{item.path}'")
  }
}

///|
fn geometry_scheme(name : String) -> Int {
  match name {
    "bitRange" => 1
    "lsb" | "msb" => 2
    "bitOffset" | "bitWidth" => 3
    _ => 0
  }
}

///|
fn declaration_values(node : Node) -> Map[String, Node] raise SvdError {
  let values = Map([])
  let mut scheme = 0
  for child in node.children {
    if child.name == "name" || child.name == "registers" || child.name == "fields" ||
      child.name == "cluster" || child.name == "register" || child.name == "field" ||
      child.name == "addressBlock" || child.name == "interrupt" ||
      child.name == "enumeratedValues" {
      continue
    }
    if values.contains(child.name) {
      raise child.invalid("duplicate <\{child.name}> in <\{node.name}>")
    }
    let geometry = if node.name == "field" { geometry_scheme(child.name) } else { 0 }
    if geometry != 0 {
      if scheme != 0 && geometry != scheme {
        raise child.invalid("mixed field bit-range conventions")
      }
      scheme = geometry
    }
    values[child.name] = child
  }
  values
}

///|
fn Resolver::resolve(
  self : Resolver,
  path : String,
  depth? : Int = 0,
) -> Resolved raise SvdError {
  if self.cached.get(path) is Some(value) {
    return value
  }
  let declaration = self.definition(path)
  let node = declaration.node
  if depth >= 64 {
    raise node.invalid("inheritance depth limit exceeded")
  }
  if self.active.contains(path) {
    raise node.invalid("derivedFrom cycle at '\{path}'")
  }
  self.active[path] = true
  let own_values = declaration_values(node)
  let result = match node.attributes.get("derivedFrom") {
    None => { declaration, values: own_values, children: declaration.children }
    Some(reference) => {
      let key = self.reference(declaration, reference)
      let base = self.resolve(key, depth=depth + 1)
      let values = Map([])
      let mut new_geometry = 0
      for tag, _ in own_values {
        let geometry = geometry_scheme(tag)
        if node.name == "field" && geometry != 0 {
          new_geometry = geometry
          break
        }
      }
      for tag, value in base.values {
        let old_geometry = geometry_scheme(tag)
        if new_geometry == 0 || old_geometry == 0 || old_geometry == new_geometry {
          values[tag] = value
        }
      }
      for tag, value in own_values {
        values[tag] = value
      }
      let children = base.children.copy()
      let positions = Map([])
      for i, base_child in children {
        positions[self.definition(base_child).name] = i
      }
      for child in declaration.children {
        let name = self.definition(child).name
        match positions.get(name) {
          Some(index) => children[index] = child
          None => children.push(child)
        }
      }
      { declaration, values, children }
    }
  }
  self.active.remove(path)
  self.cached[path] = result
  result
}

///|
fn Resolved::text(self : Resolved, tag : String) -> String? raise SvdError {
  match self.values.get(tag) {
    Some(node) => Some(node.text())
    None => None
  }
}

///|
fn Resolved::num(self : Resolved, tag : String) -> UInt64? raise SvdError {
  match self.values.get(tag) {
    Some(node) => Some(number(node.text(), node, tag))
    None => None
  }
}

///|
fn Resolved::instances(self : Resolved) -> Array[Instance] raise SvdError {
  expand_instances(
    self.declaration.name,
    self.num("dim"),
    self.num("dimIncrement"),
    self.text("dimIndex"),
    self.declaration.node,
  )
}

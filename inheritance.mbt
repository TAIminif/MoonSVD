///|
priv struct ResolvedChildren {
  paths : Array[String]
  mut by_name : Map[String, String]?
}

///|
priv struct Resolved {
  declaration : Declaration
  values : Map[String, Node]
  children : ResolvedChildren
  inheritance_length : Int32
}

///|
let inheritance_limit = 64

///|
priv struct Resolver {
  schema : Schema
  active : Map[String, Bool]
  cached : Map[String, Resolved]
  mut remaining_child_slots : Int32
}

///|
fn Resolver::new(schema : Schema) -> Resolver {
  {
    schema,
    active: Map([]),
    cached: Map([]),
    remaining_child_slots: 1_000_000,
  }
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
  depth : Int32,
) -> String raise SvdError {
  if reference == "" {
    raise item.node.invalid("empty derivedFrom in '\{item.path}'")
  }
  if reference.length() > qualified_name_limit {
    raise item.node.invalid(
      "derivedFrom reference exceeds 4096 UTF-16 code units",
    )
  }
  let target = if item.scope != "" && !reference.contains(".") {
    "\{item.scope}.\{reference}"
  } else {
    reference
  }
  if target.length() > qualified_name_limit {
    raise item.node.invalid("derivedFrom path exceeds 4096 UTF-16 code units")
  }
  match self.effective_path(target, depth) {
    Some(path) if self.definition(path).node.name == item.node.name => path
    Some(_) =>
      raise item.node.invalid("incorrect kind for derivedFrom '\{target}'")
    None =>
      raise item.node.invalid(
        "unknown derivedFrom '\{target}' in '\{item.path}'",
      )
  }
}

///|
fn Resolver::child_lookup(
  self : Resolver,
  children : ResolvedChildren,
  name : String,
) -> String? {
  let index = match children.by_name {
    Some(index) => index
    None => {
      let index = Map([])
      for path in children.paths {
        index[self.definition(path).name] = path
      }
      children.by_name = Some(index)
      index
    }
  }
  index.get(name)
}

///|
fn Resolver::effective_path(
  self : Resolver,
  target : String,
  depth : Int32,
) -> String? raise SvdError {
  if self.schema.declarations.contains(target) {
    return Some(target)
  }
  let parts = target.split(".").to_array()
  let mut path = parts[0].to_owned()
  if !self.schema.declarations.contains(path) {
    return None
  }
  for i in 1..<parts.length() {
    let parent = self.resolve(path, depth~)
    match self.child_lookup(parent.children, parts[i].to_owned()) {
      Some(child) => path = child
      None => return None
    }
  }
  Some(path)
}

///|
fn geometry_scheme(name : String) -> Int32 {
  match name {
    "bitRange" => 1
    "lsb" | "msb" => 2
    "bitOffset" | "bitWidth" => 3
    _ => 0
  }
}

///|
fn supported_value(tag : String) -> Bool {
  match tag {
    "dim"
    | "dimIncrement"
    | "dimIndex"
    | "baseAddress"
    | "addressOffset"
    | "size"
    | "access"
    | "resetValue"
    | "resetMask"
    | "bitRange"
    | "lsb"
    | "msb"
    | "bitOffset"
    | "bitWidth"
    | "alternateRegister"
    | "alternateGroup"
    | "modifiedWriteValues"
    | "readAction"
    | "writeConstraint" => true
    _ => false
  }
}

///|
fn declaration_values(node : Node) -> Map[String, Node] raise SvdError {
  let values = Map([])
  let mut scheme = 0
  for child in node.children {
    if !supported_value(child.name) {
      continue
    }
    if values.contains(child.name) {
      raise child.invalid("duplicate <\{child.name}> in <\{node.name}>")
    }
    let geometry = if node.name == "field" {
      geometry_scheme(child.name)
    } else {
      0
    }
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
fn Resolver::merge_children(
  self : Resolver,
  base : ResolvedChildren,
  declaration : Declaration,
) -> ResolvedChildren raise SvdError {
  if declaration.children.is_empty() {
    return base
  }
  if base.paths.is_empty() {
    return { paths: declaration.children, by_name: None, }
  }
  let slots = base.paths.length() + declaration.children.length()
  if slots > self.remaining_child_slots {
    raise declaration.node.invalid("SVD inherited children limit exceeded")
  }
  self.remaining_child_slots -= slots
  let children = base.paths.copy()
  let positions = Map([])
  for i, path in children {
    positions[self.definition(path).name] = i
  }
  for child in declaration.children {
    let name = self.definition(child).name
    match positions.get(name) {
      Some(index) => children[index] = child
      None => children.push(child)
    }
  }
  { paths: children, by_name: None, }
}

///|
fn Resolver::resolve(
  self : Resolver,
  path : String,
  depth~ : Int32 = 0,
) -> Resolved raise SvdError {
  if self.cached.get(path) is Some(value) {
    return value
  }
  let declaration = self.definition(path)
  let node = declaration.node
  if depth >= inheritance_limit {
    raise node.invalid("inheritance depth limit exceeded")
  }
  if self.active.contains(path) {
    raise node.invalid("derivedFrom cycle at '\{path}'")
  }
  self.active[path] = true
  let own_values = declaration_values(node)
  let result = match node.attributes.get("derivedFrom") {
    None =>
      {
        declaration,
        values: own_values,
        children: { paths: declaration.children, by_name: None, },
        inheritance_length: 1,
      }
    Some(reference) => {
      let key = self.reference(declaration, reference, depth + 1)
      let base = self.resolve(key, depth=depth + 1)
      if base.inheritance_length >= inheritance_limit {
        raise node.invalid("inheritance depth limit exceeded")
      }
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
        if new_geometry == 0 ||
          old_geometry == 0 ||
          old_geometry == new_geometry {
          values[tag] = value
        }
      }
      for tag, value in own_values {
        values[tag] = value
      }
      {
        declaration,
        values,
        children: self.merge_children(base.children, declaration),
        inheritance_length: base.inheritance_length + 1,
      }
    }
  }
  self.active.remove(path)
  self.cached[path] = result
  result
}

///|
fn Resolved::text(self : Resolved, tag : String) -> String? raise SvdError {
  match self.values.get(tag) {
    Some(node) => {
      let value = node.text()
      if tag != "dimIndex" && value.length() > qualified_name_limit {
        raise node.invalid("<\{tag}> exceeds 4096 UTF-16 code units")
      }
      Some(value)
    }
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

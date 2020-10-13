import macros, json, strutils, runtime, exprlang

type
  TypeKey* {.pure.} = enum
    id, types, meta, doc, `doc-ref`, params, seq, instances, enums
  Type* = ref object
    set: set[TypeKey]
    supertype*: Type
    id*: string
    types*: seq[Type]
    meta*: Meta
    doc*: string
    `doc-ref`*: string
    params*: JsonNode
    seq*: seq[Attr]
    instances*: seq[Attr]
    enums*: JsonNode
  EndianKind {.pure.} = enum
    le, be
  MetaKey* {.pure.} = enum
    id, title, application, `file-extension`, xref, license, `ks-version`,
    `ks-debug`, `ks-opaque-types`, imports, encoding, endian
  Meta = ref object
    set*: set[MetaKey]
    id*: string
    title*: string
    application*: seq[string]
    `file-extension`*: seq[string]
    xref*: JsonNode
    license*: string
    `ks-version`*: string
    `ks-debug`*: bool
    `ks-opaque-types`*: bool
    imports*: seq[string]
    encoding*: string
    endian*: EndianKind
  RepeatKind* {.pure.} = enum
    eos, expr, until
  AttrKey* {.pure.} = enum
    id, doc, `doc-ref`, contents, `type`, repeat, `repeat-expr`, `repeat-until`,
    `if`, size, `size-eos`, process, `enum`, encoding, terminator, consume,
    `include`, `eos-error`, pos, io, value
  Attr* = ref object
    set*: set[AttrKey]
    id*: string
    doc*: string
    `doc-ref`*: string
    contents*: seq[byte]
    `type`*: tuple[parsed: NimNode, raw: string]
    repeat*: RepeatKind
    `repeat-expr`*: NimNode
    `repeat-until`*: NimNode
    `if`*: NimNode
    size*: NimNode
    `size-eos`*: bool
    process*: proc()
    `enum`*: string
    encoding*: string
    `pad-right`*: byte
    terminator*: byte
    consume*: bool
    `include`*: bool
    `eos-error`*: bool
    pos*: int
    io*: KaitaiStream
    value*: NimNode

proc ksAsJsonToNim(json: JsonNode): NimNode =
  case json.kind
  of JString:
    result = expr(json.getStr)
  of JInt:
    result = newLit(json.getInt)
  of JBool:
    result = newLit(json.getBool)
  of JNull:
    result = newNilLit()
  else: discard # Should not occur

proc attrKeySet*(json: JsonNode): set[AttrKey] =
  for key in json.keys:
    result.incl(parseEnum[AttrKey](key))

proc toKsType*(json: JsonNode): Type =
  result = Type()
  for key in json.keys:
    result.set.incl(parseEnum[TypeKey](key))
  if json.hasKey("meta") and json["meta"].hasKey("id"):
    result.id = json["meta"]["id"].getStr.capitalizeAscii
  if TypeKey.meta in result.set:
    var meta = Meta()
    for key in json["meta"].keys:
      meta.set.incl(parseEnum[MetaKey](key))
    if MetaKey.id in meta.set:
      meta.id = json["meta"]["id"].getStr
    if MetaKey.title in meta.set:
      meta.title = json["meta"]["title"].getStr
    if MetaKey.application in meta.set:
      let jnode = json["meta"]["application"]
      case jnode.kind
      of JArray:
        for s in jnode.items:
          meta.application.add(s.getStr)
      of JString:
          meta.application.add(jnode.getStr)
      else: discard # should not occur
    if MetaKey.`file-extension` in meta.set:
      let jnode = json["meta"]["file-extension"]
      case jnode.kind
      of JArray:
        for s in jnode.items:
          meta.`file-extension`.add(s.getStr)
      of JString:
          meta.`file-extension`.add(jnode.getStr)
      else: discard # should not occur
    if MetaKey.xref in meta.set:
      meta.xref = json["meta"]["xref"] # XXX
    if MetaKey.license in meta.set:
      meta.license = json["meta"]["license"].getStr
    if MetaKey.`ks-version` in meta.set:
      meta.`ks-version` = json["meta"]["ks-version"].getStr
    if MetaKey.`ks-debug` in meta.set:
      meta.`ks-debug` = json["meta"]["ks-debug"].getBool
    if MetaKey.`ks-opaque-types` in meta.set:
      meta.`ks-opaque-types` = json["meta"]["ks-debug"].getBool
    if MetaKey.imports in meta.set:
      let jnode = json["meta"]["imports"]
      case jnode.kind
      of JArray:
        for s in jnode.items:
          meta.imports.add(s.getStr)
      of JString:
          meta.imports.add(jnode.getStr)
      else: discard # should not occur
    if MetaKey.encoding in meta.set:
      meta.encoding = json["meta"]["encoding"].getStr
    if MetaKey.endian in meta.set:
      meta.endian = parseEnum[EndianKind](json["meta"]["endian"].getStr)
    result.meta = meta
  if TypeKey.doc in result.set:
    result.doc = json["doc"].getStr
  if TypeKey.`doc-ref` in result.set:
    result.`doc-ref` = json["doc-ref"].getStr
  result.params = json.getOrDefault("params") # XXX
  result.enums = json.getOrDefault("enums") # XXX
  for e in json["seq"].items:
    var a = Attr(id: e["id"].getStr)
    for key in e.keys:
      a.set.incl(parseEnum[AttrKey](key))
    if AttrKey.doc in a.set:
      a.doc = e["doc"].getStr
    if AttrKey.`doc-ref` in a.set:
      a.`doc-ref` = e["doc-ref"].getStr
    # XXX if AttrKey.contents in a.set:
    if AttrKey.`type` in a.set:
      let t = e["type"].getStr
      a.`type` = (nativeType(t), t)
    if AttrKey.repeat in a.set:
      a.repeat = parseEnum[RepeatKind](e["repeat"].getStr)
    # XXX if AttrKey.`repeat-expr` in a.set:
    # XXX if AttrKey.`repeat-until` in a.set:
    # XXX if AttrKey.`if` in a.set:
    if AttrKey.size in a.set:
      a.size = ksAsJsonToNim(e["size"])
    if AttrKey.`size-eos` in a.set:
      a.`size-eos` = e["size-eos"].getBool
    # XXX if AttrKey.process in a.set:
    # XXX if AttrKey.`enum` in a.set:
    if AttrKey.encoding in a.set:
      a.encoding = e["encoding"].getStr
    # XXX if AttrKey.`pad-right` in a.set:
    # XXX if AttrKey.terminator in a.set:
    if AttrKey.consume in a.set:
      a.consume = e["consume"].getBool
    else:
      a.consume = true
    if AttrKey.`include` in a.set:
      a.`include` = e["include"].getBool
    if AttrKey.`eos-error` in a.set:
      a.`eos-error` = e["eos-error"].getBool
    else:
      a.`eos-error` = true
    # XXX if AttrKey.io in a.set:
    result.seq.add(a)

  if TypeKey.types in result.set:
    for k, v in json["types"].pairs:
      let node = v.toKsType
      node.id = k.capitalizeAscii
      node.supertype = result
      result.types.add(node)

  if TypeKey.instances in result.set:
    for k, v in json["instances"].pairs:
      var a = Attr(id: k)
      for key in v.keys:
        a.set.incl(parseEnum[AttrKey](key))
      if AttrKey.doc in a.set:
        a.doc = v["doc"].getStr
      if AttrKey.`doc-ref` in a.set:
        a.`doc-ref` = v["doc-ref"].getStr
      # XXX if AttrKey.contents in a.set:
      if AttrKey.`type` in a.set:
        let t = v["type"].getStr
        a.`type` = (nativeType(t), t)


      if AttrKey.repeat in a.set:
        a.repeat = parseEnum[RepeatKind](v["repeat"].getStr)
      # XXX if AttrKey.`repeat-expr` in a.set:
      # XXX if AttrKey.`repeat-until` in a.set:
      # XXX if AttrKey.`if` in a.set:
      if AttrKey.size in a.set:
        a.size = ksAsJsonToNim(v["size"])
      if AttrKey.`size-eos` in a.set:
        a.`size-eos` = v["size-eos"].getBool
      # XXX if AttrKey.process in a.set:
      # XXX if AttrKey.`enum` in a.set:
      if AttrKey.encoding in a.set:
        a.encoding = v["encoding"].getStr
      # XXX if AttrKey.`pad-right` in a.set:
      # XXX if AttrKey.terminator in a.set:
      if AttrKey.consume in a.set:
        a.consume = v["consume"].getBool
      else:
        a.consume = true
      if AttrKey.`include` in a.set:
        a.`include` = v["include"].getBool
      if AttrKey.`eos-error` in a.set:
        a.`eos-error` = v["eos-error"].getBool
      else:
        a.`eos-error` = true
      # XXX if AttrKey.pos in a.set:
      # XXX if AttrKey.io in a.set:
      if AttrKey.value in a.set:
        a.value = ksAsJsonToNim(v["value"])
        a.`type` = (ident"int", "int") # XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
      result.instances.add(a)

#[ For debugging
proc `$`*(node: Type): string =
  result &= "name: " & node.id & "\n"

  result &= "parent: "
  if node.supertype != nil:
    result &= $node.supertype.id
  else:
    result &= "nil"
  result &= "\n"

  result &= "children: "
  if node.types.len != 0:
    result &= "\n"
    for c in node.types:
      result &= "  " & c.id & "\n"
  else:
    result &= "nil"
  result &= "\n"

  result &= "meta: "
  if node.meta != nil:
    result &= $node.meta
  else:
    result &= "nil"
  result &= "\n"

  result &= "doc: "
  if node.doc != nil:
    result &= $node.doc
  else:
    result &= "nil"
  result &= "\n"

  result &= "doc-ref: "
  if node.`doc-ref` != nil:
    result &= $node.`doc-ref`
  else:
    result &= "nil"
  result &= "\n"

  result &= "params: "
  if node.params != nil:
    result &= $node.params
  else:
    result &= "nil"
  result &= "\n"

  result &= "seq: "
  if node.seq != nil:
    result &= $node.seq
  else:
    result &= "nil"
  result &= "\n"

  result &= "instances: "
  if node.instances != nil:
    result &= $node.instances
  else:
    result &= "nil"
  result &= "\n"

  result &= "enums: "
  if node.enums != nil:
    result &= $node.enums
  else:
    result &= "nil"
  result &= "\n"
]#
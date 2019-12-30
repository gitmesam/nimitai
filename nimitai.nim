import macros, tables, strutils, sequtils, parseutils
import nimitai/[parser, exprlang]

var
  rootType {.compileTime.}: NimNode
  mt {.compileTime.}: Type

proc nim(e: Expr): NimNode =
  case e.kind
  of ekId:      result = ident(e.strVal)
  of ekInteger: result = newLit(e.intVal)
  of ekFloat:   result = newLit(e.floatVal)
  of ekBoolean: result = newLit(e.boolVal)
  of ekArray:   result = newLit[byte](e.arrayVal)
  of ekString:  result = newLit(e.strVal)
  of ekInfix:   result = infix(nim(e.left), e.infix, nim(e.right))
  of ekPrefix:  result = prefix(nim(e.operant), e.prefix)

proc id(t: Type): string =
  var
    t = t
    res: seq[string]
  while t != nil:
    res.insert(t.name.capitalizeAscii)
    t = t.parent
  res.join

proc parentType(t: Type): NimNode =
  if t.parent == nil:
    nnkRefTy.newTree(ident"RootObj")
  else:
    ident(id(t.parent))

proc nimType(t: Type, a: Keys): NimNode =
  if kkType notin a:
    result = nnkBracketExpr.newTree(
               ident"seq",
               ident"byte")
  else:
    let ksType = a[kkType].item
    case ksType
    of "u1":
      result = ident"uint8"
    of "u2", "u2le", "u2be":
      result = ident"uint16"
    of "u4", "u4le", "u4be":
      result = ident"uint32"
    of "u8", "u8le", "u8be":
      result = ident"uint64"
    of "s1":
      result = ident"int8"
    of "s2", "s2le", "s2be":
      result = ident"int16"
    of "s4", "s4le", "s4be":
      result = ident"int32"
    of "s8", "s8le", "s8be":
      result = ident"int64"
    of "f4", "f4le", "f4be":
      result = ident"float32"
    of "f8", "f8le", "f8be":
      result = ident"float64"
    of "str", "strz":
      result = ident"string"
    of "b1":
      result = ident"bool"
    else:
      var bits: int
      let parsedChars = ksType[1..^1].parseInt(bits)
      if ksType.startsWith("b") and parsedChars == ksType.len - 1:
        case bits
        of  1 ..  8: result = ident"uint8"
        of  9 .. 16: result = ident"uint16"
        of 17 .. 32: result = ident"uint32"
        of 33 .. 64: result = ident"uint64"
        else:        result = nnkBracketExpr.newTree(
                              ident"seq",
                              ident"byte")
      else:
        # User type
        var t = t
        while skTypes in t.sects and
              ksType notin t.sects[skTypes].types.mapIt(it.name):
          t = t.parent
        result = ident(id(t) & ksType.capitalizeAscii)

proc attributes(t: Type): seq[NimNode] =
  for attr in t.sects[skSeq].`seq`:
    result.add(
      nnkIdentDefs.newTree(
        ident(attr[kkId].item),
        t.nimType(attr),
        newEmptyNode()))

proc typeDecl(t: Type): seq[NimNode] =
  result = newSeq[NimNode](2)

  let name = id(t)

  result[0] = nnkTypeDef.newTree(
    ident(name),
    newEmptyNode(),
    nnkRefTy.newTree(
      ident(name & "Obj")))

  result[1] = nnkTypeDef.newTree(
    ident(name & "Obj"),
    newEmptyNode())

  var
    obj = nnkObjectTy.newTree(
      newEmptyNode(),
      newEmptyNode())
    fields = newTree(nnkRecList)

  fields.add(
    nnkIdentDefs.newTree(
      ident"io",
      ident"KaitaiStream",
      newEmptyNode()),
    nnkIdentDefs.newTree(
      ident"root",
      rootType,
      newEmptyNode()),
    nnkIdentDefs.newTree(
      ident"parent",
      t.parentType,
      newEmptyNode()))

  fields.add t.attributes

  obj.add(fields)
  result[1].add(obj)

proc addTypeDecl(ts: var NimNode, t: Type) =
  if skTypes in t.sects:
    for typ in t.sects[skTypes].types:
      ts.addTypeDecl(typ)
  ts.add typeDecl(t)

proc types(): NimNode =
  result = newTree(nnkTypeSection)
  rootType = ident(mt.name.capitalizeAscii)
  if skTypes in mt.sects:
    for t in mt.sects[skTypes].types:
      result.addTypeDecl(t)
  result.add typeDecl(mt)

# Template for pythonic @property behavior
proc property(): NimNode =
  nnkTemplateDef.newTree(
    nnkAccQuoted.newTree(
      ident"."),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      ident"untyped",
      newIdentDefs(
        ident"a",
        rootType),
      newIdentDefs(
        ident"b",
        ident"untyped")),
    newEmptyNode(),
    newEmptyNode(),
    newStmtList(
      newCall(
        newPar(
          newDotExpr(
            ident"a",
            nnkAccQuoted.newTree(
              ident"b",
              ident"inst"))))))

proc callApi(t: Type, a: Keys): NimNode =
  if kkType notin a:
    return newCall(
      ident"read_bytes",
      ident"io",
      a[kkSize].expr.nim)
  let typ = a[kkType].item
  case typ
  of "u1", "u2le", "u2be", "u4le", "u4be", "u8le", "u8be",
     "s1", "s2le", "s2be", "s4le", "s4be", "s8le", "s8be":
    return newCall(
      ident("read" & typ),
      ident"io")
  else: discard

proc read(t: Type, a: Keys): NimNode =
  let name = ident(a[kkId].item)
  newStmtList(
    newLetStmt(
      name,
      t.callApi(a)),
    newAssignment(
      newDotExpr(
        ident"result",
        name),
      name))

proc read(t: Type): NimNode =
  let
    tIo = newIdentDefs(
      ident"io",
      ident"KaitaiStream")
    tRoot = newIdentDefs(
      ident"root",
      rootType)
    tParent = newIdentDefs(
      ident"parent",
      parentType(t))
    tThis = ident(t.id)
    tDesc = newIdentDefs(
      ident"_",
      nnkBracketExpr.newTree(
        ident"typedesc",
        tThis))

  result = newProc(
    ident"read",
    @[tThis,
      tDesc,
      tIo,
      tRoot,
      tParent])
  result.body = newStmtList(
    newAssignment(
      ident"result",
      nnkObjConstr.newTree(
        tThis,
        newColonExpr(
          ident"io",
          ident"io"),
        newColonExpr(
          ident"parent",
          ident"parent"))),
    newLetStmt(
      ident"root",
      nnkIfExpr.newTree(
        nnkElifExpr.newTree(
          infix(
            ident"root",
            "==",
            newNilLit()),
          nnkCast.newTree(
            rootType,
            ident"result")),
        nnkElseExpr.newTree(
          ident"root"))),
    newAssignment(
      newDotExpr(
        ident"result",
        ident"root"),
      ident"root"))

  for attr in t.sects[skSeq].`seq`:
    result.body.add(t.read(attr))

proc addRead(sl: var NimNode, t: Type) =
  if skTypes in t.sects:
    for typ in t.sects[skTypes].types:
      sl.addRead(typ)
  sl.add read(t)

proc reads(): NimNode =
  result = newStmtList()
  if skTypes in mt.sects:
    for t in mt.sects[skTypes].types:
      result.addRead(t)
  result.add read(mt)

proc destructor(t: Type): NimNode =
  let tObj = newIdentDefs(
    ident"x",
    nnkVarTy.newTree(
      ident(id(t) & "Obj")))
  result = newProc(
    ident"destroy=",
    @[newEmptyNode(),
      tObj])
  result.body = newCall(
    ident"close",
    newDotExpr(
      ident"x",
      ident"io"))

proc addDestructor(sl: var NimNode, t: Type) =
  if skTypes in t.sects:
    for typ in t.sects[skTypes].types:
      sl.addDestructor(typ)
  sl.add destructor(t)

proc destructors(): NimNode =
  result = newStmtList()
  if skTypes in mt.sects:
    for t in mt.sects[skTypes].types:
      result.addDestructor(t)
  result.add destructor(mt)
  
macro injectParser*(path: static[string]) =
  mt = parse(path)
  result = newStmtList(
    types(),
    property(),
    reads(),
    destructors())

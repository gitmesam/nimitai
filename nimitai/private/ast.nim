import tables, strutils, sequtils, npeg, ksyast

# KSY creates the symbol table which KSEL uses; so they have to be defined
# in the same file because of cyclic dependency issue
type
  # Kaitai Struct YAML AST
  Nimitype* = ref object
    id*: string
    parent*: string
    root*: string
    title*: string
    app*: string
    imports*: seq[string]
    encoding*: string
    endian*: Endian
    license*: string
    exts*: seq[string]
    doc*: string
    docRef*: string
    fields*: seq[Field]
    enums*: seq[Enum]
  Field* = ref object
    id*: string
    doc*: string
    docRef*: string
    contents*: seq[byte]
    endian*: Endian
    typ*: KsType
    size*: KsNode
    repeat*: Repeat
    repeatExpr*: KsNode
    repeatUntil*: KsNode
    ifExpr*: KsNode
    case isLazy*: bool
    of true:
      pos*: KsNode
      io*: string
      value*: KsNode
    of false: discard
  Repeat* = enum
    rExpr
    rEos
    rUntil
  Process* = enum
    pXor
  Endian* = enum
    eNone
    eLe
    eBe

  # Kaitai Struct Expression Language AST
  Radix* = enum
    rBin
    rDec
    rHex
  KsTypeKind* = enum
    ktkBit
    ktkBool
    ktkInt
    ktkFloat
    ktkArray
    ktkStr
    ktkStrz
    ktkUser
  KsType* = ref object
    case kind*: KsTypeKind
    of ktkBit:
      bits*: int
    of ktkBool:
      discard
    of ktkInt:
      radix*: Radix
      size*: int
      isSigned*: bool
      label: string
    of ktkFloat:
      precision*: int
    of ktkArray:
      arrType: KsType
      sizeEos*: bool
      process*: Process
    of ktkStr:
      lenEos*: bool
      encoding*: string
    of ktkStrz:
      terminator*: char
      consume*: bool
      includeTerminator*: bool
      eosError*: bool
    of ktkUser:
      id*: string
  ArithOp* = enum
    aoAdd
    aoSub
    aoMul
    aoDiv
    aoMod
  BitOp* = enum
    boLShift
    boRShift
    boAnd
    boOr
    boXor
  CmpOp* = enum
    coGtE
    coGt
    coLtE
    coLt
    coEq
    coNEq
  RelOp* = enum
    roAnd
    roOr
  UnaryOp* = enum
    uoMinus
    uoInvert
    uoNot
  KsNodeKind* = enum
    knkIdentifier
    knkLiteral
    knkArithOp
    knkBitOp
    knkCmpOp
    knkRelOp
    knkUnaryOp
  KsNode* = ref object
    case kind*: KsNodeKind
    of knkIdentifier:
      id*: string
    of knkLiteral:
      typ*: KsType
      val*: string
    of knkArithOp:
      aoL*: KsNode
      ao*: ArithOp
      aoR*: KsNode
    of knkBitOp:
      boL*: KsNode
      bo*: BitOp
      boR*: KsNode
    of knkCmpOp:
      coL*: KsNode
      co*: CmpOp
      coR*: KsNode
    of knkRelOp:
      roL*: KsNode
      ro*: RelOp
      roR*: KsNode
    of knkUnaryOp:
      uoO*: KsNode
      uo*: UnaryOp

var symbolTable* {.compileTime.}: Table[string, Field]

proc parseKsExpr*(expr: string): KsNode =
  let p = peg(kse, stack: seq[KsNode]):
    kse      <- Lexeme * B * *BinaryOp

    B        <- *Blank

    Lexeme   <- UnaryOp | Literal | Id
    Id       <- Lower * *(Alnum | '_'):
      stack.add KsNode(kind: knkIdentifier, id: $0)
    Literal  <- Int | Float | Bool | String

    String   <- StringQuote | StringDoubleQuote

    StringQuote <- '\'' * *(Print - '\''):
      var s = $0
      s[0]  = '\\'
      s[^2] = '\\'
      s[^1] = '"'
      stack.add KsNode(kind: knkLiteral, typ: KsType(kind: ktkStr), val: s)
    StringDoubleQuote <- '\"' * >*(Print - '\"'):
      var s = $0
      s[0]  = '\\'
      s[^2] = '\\'
      s[^1] = '\''
      stack.add KsNode(kind: knkLiteral, typ: KsType(kind: ktkStr), val: s)

    Bool     <- "true" | "false":
      stack.add KsNode(kind: knkLiteral, typ: KsType(kind: ktkBool), val: $0)
    Float    <- Int * '.' * Int * ?('e' * Int):
      stack.add KsNode(kind: knkLiteral,
                       typ: KsType(kind: ktkFloat, precision: 8),
                       val: $0)
    Int      <- Hex | Bin | Dec
    
    Hex      <- "0x" * +Xdigit:
      stack.add KsNode(kind: knkLiteral, typ: KsType(kind: ktkInt,
                                                     radix: rHex,
                                                     size: 8,
                                                     isSigned: true), val: $0)
    Bin      <- "0b" * +{'0', '1'}:
      stack.add KsNode(kind: knkLiteral, typ: KsType(kind: ktkInt,
                                                     radix: rBin,
                                                     size: 8,
                                                     isSigned: true), val: $0)
    Dec      <- +Digit:
      stack.add KsNode(kind: knkLiteral, typ: KsType(kind: ktkInt,
                                                     radix: rDec,
                                                     size: 8,
                                                     isSigned: true), val: $0)

    UnaryOp  <- >("-"|"~"|"not") * (Literal | Id):
      var op: UnaryOp
      case $0
      of "-"  : op = uoMinus
      of "~"  : op = uoInvert
      of "not": op = uoNot
      let l = pop(stack)
      stack.add KsNode(kind:knkUnaryOp, uoO: l, uo: op)
    BinaryOp <- ArithOp | BitOp | CmpOp | RelOp

    ArithOp  <- >("+" | "-" | "*" | "/" | "%") * B * Lexeme:
      var op: ArithOp
      case $0
      of "+": op = aoAdd
      of "-": op = aoSub
      of "*": op = aoMul
      of "/": op = aoDiv
      of "%": op = aoMod
      let
        l = pop(stack)
        r = pop(stack)
      stack.add KsNode(kind: knkArithOp, aoL: l, ao: op, aoR: r)
    BitOp    <- >("<<" | ">>" | "&" | "|" | "^") * B * Lexeme:
      var op: BitOp
      case $0
      of "<<": op = boLShift
      of ">>": op = boRShift
      of "&" : op = boAnd
      of "|" : op = boOr
      of "^" : op = boXor
      let
        l = pop(stack)
        r = pop(stack)
      stack.add KsNode(kind: knkBitOp, boL: l, bo: op, boR: r)
    CmpOp    <- >("<=" | "<" | ">=" | ">" | "==" | "!=") * B * Lexeme:
      var op: CmpOp
      case $0
      of "<=": op = coLtE
      of "<" : op = coLt
      of ">=": op = coGtE
      of ">" : op = coGt
      of "==": op = coEq
      of "!=": op = coNEq
      let
        l = pop(stack)
        r = pop(stack)
      stack.add KsNode(kind: knkCmpOp, coL: l, co: op, coR: r)
    RelOp    <- >("and" | "or") * B * Lexeme:
      var op: RelOp
      case $0
      of "and": op = roAnd
      of "or" : op = roOr
      let
        l = pop(stack)
        r = pop(stack)
      stack.add KsNode(kind: knkRelOp, roL: l, ro: op, roR: r)

  var stack: seq[KsNode]
  assert p.match(expr, stack).ok
  assert stack.len == 1
  stack[0]

#XXX needs recursion
proc deriveType*(expr: KsNode): KsType =
  case expr.kind
  of knkIdentifier:
    result = symbolTable[expr.id].typ
  of knkLiteral:
    result = expr.typ
  of knkArithOp:
    result = expr.aoL.typ
  of knkBitOp:
    result = expr.boL.typ
  of knkCmpOp:
    result = expr.coL.typ
  of knkRelOp:
    result = expr.roL.typ
  of knkUnaryOp:
    result = expr.uoO.typ

proc hierarchy(t: Type): seq[string] =
  var t = t
  while t.id != "RootObj":
    result.insert(t.id.capitalizeAscii)
    t = t.parent

proc endian(s: string): Endian =
  if s == "le": eLe else: eBe

proc isBitType*(typ: string): tuple[isBit: bool, bits: int] =
  let p = peg(t, bits: int):
    t <- 'b' * >+Digit:
      bits = parseInt($1)
  var
    isBit: bool
    bits: int
  isBit = p.match(typ, bits).ok
  (isBit, bits)

proc parseField(f: Attr|Inst, isLazy: bool, currentType: Type): Field =
  result = Field(id: f.id, isLazy: isLazy)
  #XXX kkContents
  if kkDoc in f.keys:
    result.doc = f.keys[kkDoc].strval
  if kkDocRef in f.keys:
    result.docRef = f.keys[kkDocRef].strval
  if kkType in f.keys:
    let typ = f.keys[kkType].strval
    case typ
    of "u1", "u2", "u2le", "u2be", "u4", "u4le", "u4be", "u8", "u8le", "u8be",
       "s1", "s2", "s2le", "s2be", "s4", "s4le", "s4be", "s8", "s8le", "s8be":
      result.typ = KsType(kind: ktkInt)
      if kkEnum in f.keys:
        result.typ.label = f.keys[kkEnum].strval
      if typ.startsWith('u'):
        result.typ.isSigned = true
      result.typ.size = parseInt(typ[1..1])
      if typ.len > 2:
        result.endian = endian(typ[2..3])
    of "f4", "f8":
      result.typ = KsType(kind: ktkFloat)
      result.typ.precision = parseInt(typ[1..1])
    of "str":
      var
        lenEos: bool
        encoding: string
      if kkSizeEos in f.keys:
        lenEos = parseBool(f.keys[kkSizeEos].strval)
      if kkEncoding in f.keys:
        encoding = f.keys[kkEncoding].strval
      result.typ = KsType(kind: ktkStr, lenEos: lenEos, encoding: encoding)
    of "strz":
      var
        terminator: char
        consume: bool
        includeTerminator: bool
        eosError: bool
      if kkTerminator in f.keys:
        terminator = f.keys[kkTerminator].charval
      if kkConsume in f.keys:
        consume = parseBool(f.keys[kkConsume].strval)
      if kkInclude in f.keys:
        includeTerminator = parseBool(f.keys[kkInclude].strval)
      if kkEosError in f.keys:
        eosError = parseBool(f.keys[kkEosError].strval)
      result.typ = KsType(kind: ktkStrz,
                          terminator: terminator,
                          consume: consume,
                          includeTerminator: includeTerminator,
                          eosError: eosError)
    else:
      var (isBit, bits) = isBitType(typ)
      if isBit:
        result.typ = KsType(kind: ktkBit, bits: bits)
      else: # user type
        result.typ = KsType(kind: ktkUser)
        var t = currentType
        echo t.id
        while typ notin t.types.mapIt(it.id):
          t = t.parent
        result.typ.id = hierarchy(t).join & typ.capitalizeAscii
  else: # no type - byte array
    #XXX do enums
    var
      sizeEos: bool
      process: Process
    if kkSizeEos in f.keys:
      sizeEos = parseBool(f.keys[kkSizeEos].strval)
    if kkProcess in f.keys:
      case f.keys[kkProcess].strval:
      of "xor":
        process = pXor
      else: discard
    result.typ = KsType(kind: ktkArray,
                        arrType: KsType(kind: ktkInt, size: 1, isSigned: false),
                        sizeEos: sizeEos, process: process)
  if kkSize in f.keys:
    result.size = parseKsExpr(f.keys[kkSize].strval)
  # value calculated value instances
  if kkValue in f.keys:
    let val = parseKsExpr(f.keys[kkValue].strval)
    result.value = val
    result.typ = val.deriveType
  # kkIf

  # kkRepeat
  # kkRepeatExpr
  # kkRepeatUntil

  # kkIo
  # kkPos

proc parseType(types: var seq[Nimitype], t: Type) =
  for typ in t.types:
    parseType(types, typ)

  var h = hierarchy(t)
  let nt = new(Nimitype)
  nt.id = h.join
  discard h.pop
  nt.parent = h.join
  nt.root = t.root.id.capitalizeAscii
  if kkEndian in t.meta:
    nt.endian = endian(t.meta[kkEndian].strval)
  else:
    var pt = t
    while t.parent.id != "RootObj":
      if kkEndian in t.parent.meta:
        nt.endian = endian(t.parent.meta[kkEndian].strval)
        break
      pt = t.parent
  if kkTitle in t.meta:
    nt.title = t.meta[kkTitle].strval
  if kkApp in t.meta:
    nt.app = t.meta[kkApp].strval
  if kkImports in t.meta:
    nt.imports = t.meta[kkImports].list
  if kkEncoding in t.meta:
    nt.encoding = t.meta[kkEncoding].strval
  if kkLicense in t.meta:
    nt.license = t.meta[kkLicense].strval
  if kkExts in t.meta:
    nt.exts = t.meta[kkExts].list
  nt.doc = t.doc
  for a in t.attrs:
    let field = parseField(a, false, t)
    nt.fields.add field
    symbolTable[field.id] = field
  for i in t.insts:
    let field = parseField(i, true, t)
    nt.fields.add field
    symbolTable[field.id] = field
  nt.enums = t.enums
  types.add nt

proc parseKsyAst*(path: string): seq[Nimitype] =
  let ksy = parseKsy(path)
  result.parseType(ksy)

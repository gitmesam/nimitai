import os

let path = "../material/ksy/" & paramStr(1) & ".ksy"

writeFile("temp.nim", """
import ../../nimitai, ../../../kaitai_struct_nim_runtime/kaitai_struct_nim_runtime, macros, options
expandMacros:
  injectParser(""" & "\"" & path & "\")")

discard execShellCmd("nim c --hints:off -r temp")
discard execShellCmd("rm -f temp.nim temp")
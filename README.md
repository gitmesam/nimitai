# nimitai [WIP]
## Implementation of [Kaitai Struct](https://kaitai.io/) as a compile-time library

### How will it look like?
A vague usage demo:
```nim
import nimitai

generateParser("/path/to/my/ksy/file")

let x = myFileFormat.fromFile("/path/to/my/bin/file")

# Access x's structured data (fields) here.
```
### How does it work?
- [npeg](https://github.com/zevv/npeg) is used to parse a `.ksy` file (special thanks to [zevv](https://github.com/zevv) for this awesome library <3).
- The ksy AST is used to generate procedures for parsing a file into a structured Nim object.

*everything is done at CT*

### What does it bring to the table?
Up until now there is no library in any programming language for parsing an arbitary file. If a library for your specific format does not exist in your language, you have to create it. This can either be done **by hand** or by using a **file parser generator** like [Kaitai Struct](https://kaitai.io/) or if your format is relatively simple, serialization programs like [Protocol Buffers](https://developers.google.com/protocol-buffers) can work too.

Nimitai does away with all this machinary. You don't need to hand-write anything, nor do you need any external compiler tools and auto-generated parsers. The parser is created in-memory at compile-time; no files are generated!

This allows for better and easier integration of parsers into your project.

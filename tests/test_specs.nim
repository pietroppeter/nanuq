## The examples in openspec/specs that need no other package (see specsuite.nim).
import std/unittest
import specsuite, pluginfixture

# the plugin the expression-plugins example loads
discard doubleItLib()
specTests()

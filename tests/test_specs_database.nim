## The examples of the database-io spec (see specsuite.nim): in a program of their own, as
## their imports clash with the other specs' (quantile, ...).
import std/unittest
import specsuite
specTests("database-io")

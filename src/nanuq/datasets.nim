## Sample datasets for examples, tests and documentation.
##
## The data files ship with the library sources and are read from there, so a
## program needs the Nanuq sources on disk where it was compiled. They are a
## convenience for early development and are expected to move out of the
## library later.
##
## .. code-block:: nim
##   import nanuq, nanuq/datasets
##
##   let df = penguins()
##   echo df.shape  # (344, 8)

import std/os
import ../nanuq

const dataDir = currentSourcePath.parentDir / "data"

proc penguins*(): DataFrame =
  ## The Palmer penguins table (palmerpenguins, CC0): 344 rows, with columns
  ## species, island, bill_length_mm, bill_depth_mm, flipper_length_mm,
  ## body_mass_g, sex and year. "NA" fields are read as nulls.
  readCsv(dataDir / "penguins.csv", nullValues = ["NA"])

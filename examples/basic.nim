## Run with: nim r examples/basic.nim
import nanuq, nanuq/datasets

# Build a DataFrame from Nim data
let people = newDataFrame(
  series("name", ["Ada", "Grace", "Linus", "Margaret"]),
  series("age", [36, 85, 54, 87]),
  series("height", [1.65, 1.52, 1.80, 1.70]),
)
echo people
echo "shape: ", people.shape, " columns: ", people.columns

# Eager operations
echo people.filter(col("age") > 50).withColumns((col("age") * 12).alias("months"))

# Load the bundled penguins dataset and run a lazy query
let df = penguins()
let query = df.lazy
  .dropNulls("body_mass_g")
  .filter(col("year") >= 2008)
  .groupBy(col("species"))
  .agg(
    col("body_mass_g").mean.alias("mean_body_mass_g"),
    col("flipper_length_mm").max.alias("max_flipper_length_mm"),
    col("species").count.alias("n"),
  )
  .sort("mean_body_mass_g", descending = true)

echo query.explain
let summary = query.collect
echo summary
echo "heaviest species: ", summary["species", 0, string],
     " (", summary["mean_body_mass_g", 0, float], " g)"

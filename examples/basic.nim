## Run with: nim r examples/basic.nim
import std/os
import nanuq

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

# Read a CSV and run a lazy query
let iris = readCsv(currentSourcePath.parentDir / "iris_sample.csv")
let query = iris.lazy
  .filter(col("sepal_length") > 5.0)
  .groupBy(col("species"))
  .agg(
    col("sepal_length").mean.alias("mean_sepal_length"),
    col("petal_width").max.alias("max_petal_width"),
    col("species").count.alias("n"),
  )
  .sort("mean_sepal_length", descending = true)

echo query.explain
let summary = query.collect
echo summary
echo "top species: ", summary["species", 0, string],
     " (", summary["mean_sepal_length", 0, float], ")"

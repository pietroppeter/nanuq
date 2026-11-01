# Spec Delta

## REMOVED Requirements

### Requirement: Profiling
**Reason**: Polars 2.0 removed `LazyFrame.profile` (its timings were misleading under the streaming engine), and the py-2.1.0 crates no longer have it.
**Migration**: use `explain` to see the plan, and time `collect` for the run; calling `profile` is a compile-time error with this message.

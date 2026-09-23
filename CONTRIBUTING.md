# Contributing to OpenBucket

OpenBucket currently targets macOS 26+ and Swift 6. Use the installed Xcode toolchain, run the build and tests in `README.md`, and format changed Swift files with `swift format`.

Keep S3 concepts in `OpenBucketCore`, SDK calls in `OpenBucketS3`, and macOS-specific storage and views in `App`. Add protocols at external boundaries when substitution is useful. Preserve object keys exactly and treat prefixes as listing filters. Keep implementation comments rare; document public contracts and compatibility rules that are not obvious from code.

For behavior changes, add a test at the boundary where the behavior is visible. Endpoint construction tests should inspect the SDK-generated request. Local S3 integration tests use an isolated service and environment variables; never commit access keys, secrets, profile files, or captured authorization headers.

The first milestone is read-only. Proposals for writes should specify the S3 operation, progress and cancellation behavior, partial-failure handling, and a compatible-service test before changing the user interface.

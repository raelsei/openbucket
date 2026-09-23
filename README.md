# OpenBucket

OpenBucket is a native macOS 26+ app for browsing Amazon S3 and compatible object stores. It uses SwiftUI and the system Liquid Glass appearance. The current milestone is read-only: connect, discover buckets when permitted, browse a known bucket directly, navigate object-key prefixes, and inspect basic object details.

## What works today

- Multiple connection profiles with custom HTTP or HTTPS endpoint, region, and addressing style.
- Known-bucket access without requiring `ListBuckets` permission.
- Access key, secret key, and optional session token in macOS Keychain. The profile file contains only settings and a credential reference.
- `ListObjectsV2` with `/` delimiter and explicit continuation pages.
- One page of up to 500 entries in memory, with previous and next page controls.
- Direct `s3://bucket/prefix/` navigation, refresh, object details, and clear loading and failure states.
- Path-style S3 against Garage 2.4.1, including a nested prefix, verified with an isolated local fixture.

Uploads, downloads, deletion, synchronization, Finder mounting, and non-S3 protocols are not part of this milestone.

## Endpoint paths

The endpoint URL path and the object-key prefix are separate. For example, `https://store.example.com/s3/` with bucket `photos` and path-style addressing sends a request under `/s3/photos`; `photos/2026/` in the starting-prefix field filters object keys inside that bucket. The adapter has a test that captures the signed SDK request path and checks this join.

Soto uses path-style addressing for custom endpoints by default. Virtual-host addressing works with a pathless endpoint, such as `https://store.example.com`; the app rejects virtual-host addressing with an endpoint path because Soto produces an incompatible URL for that combination. A path-aware S3 gateway must receive the same path that was signed. The request-path test does not establish compatibility with a proxy that rewrites the path.

## Build

Requirements: macOS 26 or later and Xcode 27. The committed `OpenBucket.xcodeproj` can be opened directly in Xcode. To regenerate it after editing `project.yml`, install XcodeGen and run:

```sh
xcodegen generate --spec project.yml
```

Command-line build and tests:

```sh
xcodebuild -project OpenBucket.xcodeproj -scheme OpenBucket -destination 'platform=macOS' -derivedDataPath DerivedData build
xcodebuild -project OpenBucket.xcodeproj -scheme OpenBucket -destination 'platform=macOS' -derivedDataPath DerivedData test
swift test --package-path Packages/OpenBucket
```

Swift Package Manager resolves Soto 7.15.0 and its transitive dependencies on the first build. No AWS account is required for the unit tests.

## Optional S3 integration test

The Garage integration test is skipped unless these environment variables are set:

```text
OPENBUCKET_TEST_ENDPOINT
OPENBUCKET_TEST_REGION
OPENBUCKET_TEST_BUCKET
OPENBUCKET_TEST_ACCESS_KEY
OPENBUCKET_TEST_SECRET_KEY
OPENBUCKET_TEST_PREFIX
OPENBUCKET_TEST_EXPECT_KEY
```

Use an isolated test bucket with an existing object under the chosen prefix, then run:

```sh
swift test --package-path Packages/OpenBucket --filter listsKnownGarageBucketAndNestedPrefix
```

Do not add credentials or a credential-bearing test script to this repository.

## Code map

`OpenBucketCore` owns S3 values, the read-only repository port, and cancellable browsing state. `OpenBucketS3` adapts Soto S3 and keeps SDK types outside the app. `App` contains SwiftUI and the macOS profile and Keychain stores. `OpenBucketApp` is the composition root.

The first adapter candidate was the official AWS SDK for Swift. SwiftPM attempted to fetch its approximately 2.4 GB repository and did not complete within 18 minutes on this development machine. Soto resolved and passed the Garage and endpoint-path tests. The adapter boundary allows the SDK choice to change without rewriting views or the S3 domain.

OpenBucket is licensed under the MIT License; see `LICENSE`.

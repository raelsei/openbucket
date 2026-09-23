# OpenBucket

OpenBucket is a native macOS 26+ app for browsing Amazon S3 and compatible object stores. It uses SwiftUI and the system Liquid Glass appearance. The current milestone is read-only: connect, discover buckets when permitted, browse a known bucket directly, navigate object-key prefixes, and preview objects.

## What works today

- Multiple connection profiles with custom HTTP or HTTPS endpoint, region, and addressing style.
- Known-bucket access without requiring `ListBuckets` permission.
- Access key, secret key, and optional session token in macOS Keychain. The profile file contains only settings and a credential reference.
- `ListObjectsV2` with `/` delimiter and on-demand infinite scrolling. Each request fetches at most 500 entries; earlier entries remain visible while the next page loads.
- Grid and native macOS table layouts. The table supports column sorting and per-file selection checkboxes; grid selection mode supports choosing several files. Sorting and "Select All Loaded" apply only to objects fetched so far. Clicking a file row opens a right-side inspector with metadata and image or video artwork for objects up to 8 MB. Its Preview button opens macOS Quick Look for objects up to 64 MB; its Download button saves the full object to a chosen local file using a bounded-memory stream. Large objects retain a type icon and metadata without automatic content transfer.
- Download selected files into a new local export folder with progress, cancellation, and per-file failure reporting. Sanitized filename collisions receive unique names instead of overwriting another selected file.
- Direct `s3://bucket/prefix/` navigation, refresh, object details, and clear loading and failure states.
- Path-style S3 against Garage 2.4.1, including a nested prefix, verified with an isolated local fixture.

Quick Look uses a temporary local copy and removes it when the preview closes. Uploads, deletion, synchronization, Finder mounting, and non-S3 protocols are not part of this milestone.

## Local credential storage

There is no app database. Non-secret profile settings live in `~/Library/Application Support/OpenBucket/profiles.json` with user-only file permissions; the containing directory is user-only too. The JSON stores a random Keychain reference, never the access key or secret. Secrets live in macOS Keychain as a generic password item. The store prefers the data-protection Keychain with `WhenUnlockedThisDeviceOnly` and reads older login-Keychain items for migration. This repository currently builds an unsigned debug app, so macOS denies data-protection Keychain access and the app falls back to the login Keychain. A signed release must configure and verify the required Keychain entitlement before claiming the stronger accessibility setting.

Automatic thumbnails and Quick Look copies are kept in private temporary directories and deleted after use. A crash may leave a temporary preview file until the operating system cleans its temporary directory.

Downloads are written to a private temporary file beside the chosen destination and moved into place only after the transfer completes. A failed or canceled transfer leaves an existing destination intact.

A batch download creates a new `OpenBucket Export-*` folder inside the chosen directory. Completed files remain there if another file fails or the batch is canceled. The result bar can reveal the folder in Finder and copy the keys that failed.

## Endpoint paths

The endpoint URL path and the object-key prefix are separate. For example, `https://store.example.com/s3/` with bucket `photos` and path-style addressing sends a request under `/s3/photos`; `photos/2026/` in the starting-prefix field filters object keys inside that bucket. The adapter has a test that captures the signed SDK request path and checks this join. Percent-encoded endpoint paths are rejected because Soto can rewrite their bytes while constructing an S3 request.

Soto uses path-style addressing for custom endpoints by default. Virtual-host addressing works with a pathless endpoint, such as `https://store.example.com`; the app rejects virtual-host addressing with an endpoint path because Soto produces an incompatible URL for that combination. Soto selects virtual-host addressing for Amazon endpoints even when a regular bucket is configured for explicit path style; the app reports this unsupported combination instead of silently changing the request. A path-aware S3 gateway must receive the same path that was signed. The request-path test does not establish compatibility with a proxy that rewrites the path.

Listings request S3 URL encoding for keys that XML cannot represent. Returned keys and prefixes are decoded once only when the service marks the response as URL encoded; literal percent signs in object keys remain intact.

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

The provider-neutral integration test is skipped unless these environment variables are set:

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
swift test --package-path Packages/OpenBucket --filter listsKnownBucketAndNestedPrefix
```

Run the same case against each S3-compatible provider under evaluation. Garage 2.4.1 is verified; MinIO and RustFS still need a live compatibility run.

Do not add credentials or a credential-bearing test script to this repository.

## Code map

`OpenBucketCore` owns S3 values, the read-only repository port, and cancellable browsing state. `OpenBucketS3` adapts Soto S3 and keeps SDK types outside the app. `App` contains SwiftUI and the macOS profile and Keychain stores. `OpenBucketApp` is the composition root.

The first adapter candidate was the official AWS SDK for Swift. SwiftPM attempted to fetch its approximately 2.4 GB repository and did not complete within 18 minutes on this development machine. Soto resolved and passed the Garage and endpoint-path tests. The adapter boundary allows the SDK choice to change without rewriting views or the S3 domain.

OpenBucket is licensed under the MIT License; see `LICENSE`.

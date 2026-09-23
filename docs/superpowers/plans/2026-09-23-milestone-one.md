# OpenBucket Milestone One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a macOS 26+ SwiftUI app that saves generic S3 connections securely and browses known buckets and prefixes through Soto for Swift.

**Architecture:** A Swift package owns `OpenBucketCore` domain behavior and `OpenBucketS3` SDK adaptation. The Xcode app owns SwiftUI, Keychain, and profile persistence; it assembles concrete dependencies once and presents cancellable browsing state.

**Tech Stack:** Swift 6, SwiftUI, Security framework, Soto 7.15.0, Swift Testing, XcodeGen, Xcode 27.

**Spec:** `docs/superpowers/specs/2026-09-23-openbucket-design.md`

## Global Constraints

- Deployment target: macOS 26 or later, system Liquid Glass.
- S3-only product with provider-neutral profiles and a known-bucket path that never requires `ListBuckets`.
- Secrets reside in Keychain; profile JSON contains a credential reference only.
- Preserve endpoint paths and S3 key bytes; never silently rewrite a signed path.
- Read-only first milestone with bounded, explicitly paged listings.
- Swift 6 concurrency, narrow external protocols, sparse comments, public-contract documentation.

## Review Focus

- Endpoint URLs with a path, query, or fragment: retain path, reject query and fragment before saving.
- Keys containing slash, leading slash, or trailing slash: retain the exact key; treat prefixes as filters.
- List permission denied for a known bucket: show authorization rather than invalid credentials.
- Profile switch during an in-flight page: discard stale results and continuation tokens.
- Missing secret after profile import or Keychain reset: show a repairable connection error without logging credentials.

## File Structure

- `Packages/OpenBucket/Package.swift`: package manifest and SDK dependency.
- `Packages/OpenBucket/Sources/OpenBucketCore/`: S3 values, boundary protocols, location parsing, error vocabulary, browsing operation.
- `Packages/OpenBucket/Tests/OpenBucketCoreTests/`: domain, pagination, and profile-isolation tests.
- `Packages/OpenBucket/Sources/OpenBucketS3/`: SDK client factory, requests, response mapping, diagnostics.
- `Packages/OpenBucket/Tests/OpenBucketS3Tests/`: SDK endpoint construction and opt-in Garage integration checks.
- `App/`: SwiftUI app, connection editor, browser, inspector, Keychain, profile JSON store.
- `project.yml`: reproducible Xcode project generation.
- `README.md`: local build, scope, and Garage integration instructions.

---

### Task 1: Core S3 values and browsing behavior

**Files:** `Packages/OpenBucket/Package.swift`, `Sources/OpenBucketCore/*.swift`, `Tests/OpenBucketCoreTests/*.swift`

**Interfaces:** Produces `ConnectionProfile`, `S3Credentials`, `S3Location`, `ObjectPage`, `S3Repository`, `BrowseSession`. Later tasks consume these public names without SDK types.

- [ ] **Step 1: Write failing tests** for `S3Location.parse("s3://photos/2026/trip/")`, endpoint path retention, invalid endpoint query, `BrowseSession` continuation, and profile switch cancellation. Assert observable values and stale-result rejection.
- [ ] **Step 2: Run `swift test --package-path Packages/OpenBucket --filter OpenBucketCoreTests`; expected:** failures for missing public types or required behavior.
- [ ] **Step 3: Implement the smallest domain types and operation.** `S3Repository` exposes `listBuckets(profile:credentials:)` and `listObjects(profile:credentials:bucket:prefix:continuationToken:)` using `async throws`; `BrowseSession` is `@MainActor` and owns the active task and generation token.
- [ ] **Step 4: Run the focused tests and full package suite; expected:** all green. Commit `feat: add S3 domain and browsing session`.

### Task 2: SDK adapter and request proof

**Files:** `Sources/OpenBucketS3/*.swift`, `Tests/OpenBucketS3Tests/*.swift`, `README.md`

**Interfaces:** Consumes core values and `S3Repository`; produces `AWSS3Repository`. `OpenBucketMac` constructs it through `S3Repository`.

- [ ] **Step 1: Write failing adapter tests** for known-bucket `ListObjectsV2`, delimiter `/`, page token passthrough, and endpoint path request construction. The request proof must assert the actual SDK-generated path, not string concatenation in app code.
- [ ] **Step 2: Run `swift test --package-path Packages/OpenBucket --filter OpenBucketS3Tests`; expected:** missing adapter or failing assertions.
- [ ] **Step 3: Implement `SotoS3Repository`** with static identity resolver, explicit endpoint, region, addressing style, `ListBuckets` for discovery, and `ListObjectsV2` for a known bucket. Map SDK errors into redacted `S3Failure` categories using structured status/code when available.
- [ ] **Step 4: Run focused and full package tests; expected:** all green. Run opt-in integration against isolated Garage with `region=garage` and path-style, then record request-path probe outcome in README. Commit `feat: add AWS S3 adapter`.

### Task 3: Secure profile management and SwiftUI app

**Files:** `App/*.swift`, `App/Connections/*.swift`, `App/Browser/*.swift`, `App/Storage/*.swift`, `project.yml`, `README.md`

**Interfaces:** Consumes core and S3 package products; produces `OpenBucket.app` with native profile editor, sidebar, object table, inspector, and diagnostics.

- [ ] **Step 1: Write failing tests** for profile JSON excluding access key, secret, and session token; Keychain save/load/delete; and selecting another profile while listing. Use temporary file storage and an isolated Keychain service name.
- [ ] **Step 2: Run the app test scheme; expected:** failures for missing stores or wrong behavior.
- [ ] **Step 3: Implement profile persistence and Keychain**, then native `NavigationSplitView`, `Table`, inspector, connection sheet, connection test, direct `s3://` location, loading/empty/error states, refresh and next page. Use system toolbar and standard glass controls.
- [ ] **Step 4: Generate project with `xcodegen generate`, build with `xcodebuild`, run app tests, launch app locally, inspect the main window, and fix material issues. Commit `feat: build native OpenBucket browser`.

### Task 4: Finish and document the first milestone

**Files:** `README.md`, `.swift-format`, `.gitignore`, affected source/tests

**Interfaces:** No new public API; hardens the complete user path.

- [ ] **Step 1: Add a regression test** for any behavior found while exercising Garage and the UI; run it and confirm the failure.
- [ ] **Step 2: Fix the behavior, run the regression and full suites, format sources, and run the Xcode build; expected:** green suites and successful build.
- [ ] **Step 3: Document build, supported endpoint semantics, tested Garage path, and opt-in integration; review the diff for secrets and unnecessary comments. Commit `docs: document OpenBucket milestone one`.

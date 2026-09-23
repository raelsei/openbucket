# OpenBucket: macOS S3 client design

Date: 2026-09-23
Status: Design for review

## Product intent

OpenBucket is an open source, native macOS application for browsing and managing Amazon S3 and S3-compatible object storage. The first release targets macOS 26 or later and uses current SwiftUI with the system Liquid Glass design. Its first useful milestone is a trustworthy, read-only connection and browsing experience; object writes follow after that foundation is verified.

Success means a user can configure a generic S3 endpoint, connect to a known bucket without account-wide bucket-list permission, navigate object prefixes, inspect basic metadata, and understand a connection failure without reading an SDK error dump. The local Garage probe already established that a standard Garage endpoint works with path-style addressing and a known bucket; the Swift adapter must independently reproduce that result.

“Generic” means one S3 model and one default S3 adapter work across compatible providers. It does not mean every vendor implements every Amazon S3 API. Provider-specific behavior is isolated as small, documented compatibility settings or optional capabilities rather than separate copies of the entire client.

## Scope and release sequence

### Milestone 1: connection and read-only browsing

- Save multiple connection profiles with endpoint URL, region, addressing style (`automatic`, `path`, or `virtual host`), optional known bucket, and optional starting object prefix.
- Support access key ID, secret access key, and optional session token. Keep secrets in macOS Keychain; profile storage contains only a credential reference.
- Test a known bucket using a read-only S3 request. If no bucket is supplied, attempt bucket discovery and explain when that permission is unavailable.
- Browse a bucket with `ListObjectsV2`, delimiter-based prefixes, continuation tokens, and explicit loading of the next page. Open a known `s3://bucket/key-prefix` location directly.
- Show object key, size, modification time, and available metadata without claiming prefixes are real directories.
- Classify connection failures into network/TLS, authentication or signature, region/endpoint, authorization, unsupported operation, and unknown when the response provides enough evidence. Preserve a redacted technical detail view and avoid claiming a specific cause from an ambiguous response.
- Use native macOS navigation, selection, keyboard commands, accessibility labels, and empty/loading/error states.

### Later milestones

- Download and preview, then uploads with progress and cancellation.
- Copy, move, and delete with explicit object counts and safe handling of partial failures. S3 “move” is copy followed by delete, never an atomic rename.
- Optional S3 features such as versioning, ACLs, policies, and presigned URLs appear only when supported and tested for the selected provider.
- Additional credential sources, including shared AWS profiles and SSO, can be added behind the credential port.

The initial release is S3-only. Local files are used as import/export sources; SFTP, WebDAV, Finder mounting, synchronization, and Garage administration are outside its product scope.

## User experience and Liquid Glass

The primary window uses `NavigationSplitView`: connection profiles and accessible buckets in the sidebar, an object `Table` in the content area, and an optional metadata inspector. A connection editor is a standard SwiftUI sheet. Search and navigation actions live in the system toolbar. The app uses the macOS 26 system appearance of sidebars, toolbars, controls, and sheets; custom glass is reserved for a control that needs a distinct floating surface. Object rows and data panels remain legible content surfaces rather than decorative glass cards.

The connection editor names three separate concepts: bucket addressing style, an optional path in the endpoint URL, and the starting object-key prefix. It previews the effective request shape without showing credentials. It never silently strips an endpoint path. A failed test states which stage failed and offers the relevant setting to change.

## Architecture

The first codebase has three focused targets:

1. `OpenBucketCore` is a pure Swift package containing S3 domain values, narrow protocols, and application operations. It imports neither SwiftUI nor an S3 SDK.
2. `OpenBucketS3` implements the S3 port using the official AWS SDK for Swift. SDK request/response types and errors stay inside this target. A second adapter is justified only by a demonstrated compatibility gap.
3. `OpenBucketMac` is the SwiftUI app. It owns presentation state and macOS adapters such as Keychain-backed credentials and profile persistence. Views call application operations, not SDK methods.

Dependency direction is `OpenBucketS3 → OpenBucketCore`, while `OpenBucketMac` depends on both targets to assemble the app. Only the composition root references the concrete S3 adapter. Protocols are introduced at external boundaries that need substitution, not for every class or function. Features are grouped by connection, browsing, and object details; files stay small enough to read by responsibility rather than by an arbitrary line limit.

Core values include `ConnectionProfile`, `S3Endpoint`, `AddressingStyle`, `BucketName`, `ObjectKey`, `ObjectSummary`, and `ObjectPage`. Object keys preserve S3 semantics: a slash is part of a key, a zero-byte trailing-slash object is possible, and a prefix is a listing filter. The S3 port exposes only operations needed by the current milestone; write operations are added when their flows are implemented. A separate credential-store port prevents secrets from entering profile serialization.

UI state uses Swift Observation and structured concurrency. Network work runs off the main actor; UI updates return to the main actor. A per-connection browsing operation owns cancellation and continuation state so switching profiles cannot display stale results from another connection.

## SDK and compatibility decision

The official AWS SDK for Swift is the first S3 adapter candidate because it provides `S3Client`, configurable clients, S3 operations, and a maintained transfer manager. Soto is a credible alternative and remains an adapter-level fallback. The decisive technical probe is to use the official SDK against an isolated local Garage bucket for `ListObjectsV2`, then capture the generated request for an endpoint URL containing a path such as `/s3/`. Standard Garage does not by itself establish that a path-prefixed reverse proxy can preserve SigV4 signatures: a proxy that changes a signed path may cause authentication to fail. An end-to-end claim of path-prefix support requires a compatible path-aware service or gateway test. If the SDK cannot preserve the configured path reliably, the implementation plan must choose a supported resolver or change the adapter before the UI depends on it; the app must not claim support based on URL string concatenation.

Connection profiles are provider-neutral. Known-provider presets may fill endpoint and region defaults, but all fields remain editable. Optional operations are represented by capabilities established from provider documentation or explicit probes; absence of a capability never blocks basic object browsing. Diagnostics do not assume that a failed `ListBuckets` call means the bucket credentials are invalid.

## Security, reliability, and performance

- Store static secrets and session tokens in Keychain. Do not place them in profile files, previews, crash messages, or logs.
- Redact authorization headers, signed query parameters, access keys, and secret values from diagnostic output.
- Do not disable TLS certificate validation to make a connection succeed. Surface certificate errors clearly.
- Page listings and keep a bounded amount of objects in memory. Never scan an entire bucket automatically.
- Treat remote object keys as untrusted when mapping them to local download paths in later milestones.
- Preserve the full object key and endpoint path through request construction and error reporting; normalization must not change what is signed.

## Code and open source standards

Use Swift 6 language mode with strict concurrency checks, Swift API naming conventions, and `swift-format` for consistent formatting. Prefer descriptive names and simple composition. Keep implementation comments rare; add brief documentation to public contracts and comments only for non-obvious S3 compatibility invariants. Explain architecture and contribution workflow in repository documents rather than narrating straightforward code line by line.

Tests target behavior at the boundaries: endpoint and key handling, profile isolation, error classification, and real S3 calls against an isolated Garage fixture. The build gate includes compilation and relevant Swift tests. Integration tests requiring external credentials are opt-in. The repository will include a license, contribution guide, and CI before public publication; license selection is a publication decision, not an implicit choice made by the SDK dependency.

## Acceptance for milestone 1

1. The app builds and launches on macOS 26 with the current installed Xcode toolchain.
2. A user saves a profile without persisting secrets outside Keychain.
3. The app connects to isolated Garage with path-style addressing and `region=garage`, then lists a known bucket and a nested prefix without requiring `ListBuckets`.
4. The endpoint-path request-construction probe has an explicit pass/fail result; end-to-end support is advertised only after a compatible service test.
5. Switching connections or cancelling a request cannot show objects from the previous connection.
6. Wrong endpoint, signature or region responses, and denied bucket access produce redacted diagnostics that distinguish causes when the service supplies enough evidence and remain honest when it does not.
7. The UI uses system Liquid Glass on navigation and controls, with a readable object table and keyboard-accessible primary actions.

## Sources informing the design

- Apple: [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/) and [Landmarks with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- AWS: [AWS SDK for Swift S3](https://docs.aws.amazon.com/sdk-for-swift/latest/developer-guide/using-services-s3.html), [client configuration](https://docs.aws.amazon.com/sdk-for-swift/latest/developer-guide/config-code.html), and [S3 object keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-keys.html)
- AWS: [Signature Version 4 request matching](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sig-v4-authenticating-requests.html)
- Garage: [S3 compatibility status](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- Swift: [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)

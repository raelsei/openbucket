# S3 compatibility

OpenBucket currently implements read-only S3 browsing and downloads through the `OpenBucketS3` adapter. Provider compatibility is an observed result, not a guarantee implied by the phrase “S3-compatible.”

| Provider or configuration | Current evidence |
| --- | --- |
| Garage 2.4.1, direct endpoint, path style | Live test passed for a known bucket and nested prefix; the local demo screenshots use this setup |
| Custom endpoint with a path, path style | A request-construction test checks that Soto signs the endpoint path followed by the bucket path |
| Amazon S3 | Soto adapter implemented; no account-backed live test in this repository yet |
| MinIO and RustFS | No live compatibility result yet |
| Path-rewriting reverse proxy | Not verified; rewriting a SigV4-signed path can break authentication |

The app uses `ListObjectsV2` with `/` as the delimiter. Each request asks for at most 500 entries; more entries load as you scroll. A known bucket lets an account browse even if it cannot call account-wide `ListBuckets`. Listings request S3 URL encoding for keys that XML cannot represent, and decode only when the response declares URL encoding. Literal percent signs in keys remain intact.

## Endpoint paths

The endpoint path and the object-key prefix are separate settings. With endpoint `https://store.example.com/s3/`, bucket `photos`, and path-style addressing, requests use a path beneath `/s3/photos`. Starting prefix `2026/travel/` filters keys **inside** that bucket; it does not change the endpoint base path.

Soto uses path-style addressing by default for custom endpoints. Virtual-host addressing works with a pathless endpoint such as `https://store.example.com`. OpenBucket rejects virtual-host addressing with an endpoint path because Soto constructs an incompatible URL for that combination. It also rejects percent-encoded endpoint paths, which Soto can rewrite while building the signed request.

Soto selects virtual-host addressing for standard Amazon endpoints even when path style is requested for a regular named bucket. OpenBucket reports that unsupported combination instead of silently changing the requested addressing mode. A gateway with a path prefix must receive the path that was signed; a proxy that rewrites it is a different configuration and needs its own live test.

## Live compatibility test

The provider-neutral integration test is opt-in. Supply an isolated bucket with an existing object under the test prefix:

```text
OPENBUCKET_TEST_ENDPOINT
OPENBUCKET_TEST_REGION
OPENBUCKET_TEST_BUCKET
OPENBUCKET_TEST_ACCESS_KEY
OPENBUCKET_TEST_SECRET_KEY
OPENBUCKET_TEST_PREFIX
OPENBUCKET_TEST_EXPECT_KEY
```

Then run:

```sh
swift test --package-path Packages/OpenBucket --filter listsKnownBucketAndNestedPrefix
```

Use the same test against each provider before calling it verified. Never commit credentials or captured authorization headers.

## SDK boundary

The first adapter candidate was the official AWS SDK for Swift, but its approximately 2.4 GB repository did not finish fetching on the development machine within 18 minutes. Soto 7.15.0 resolved and passed the Garage and endpoint-path tests. `OpenBucketCore` depends on an S3 repository protocol, so the SDK can be changed without rewriting browser views.

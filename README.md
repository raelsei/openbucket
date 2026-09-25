<div align="center">

<img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon-128.png" width="88" alt="OpenBucket app icon">

# OpenBucket

**A native S3 browser for macOS. See your objects, inspect media, and download what you need.**

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-18181b?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-f05138?logo=swift&logoColor=white)
![S3 focused](https://img.shields.io/badge/S3-focused-54b6cb)
![MIT license](https://img.shields.io/badge/license-MIT-8b8bd4)

</div>

OpenBucket is an early, read-only macOS app for Amazon S3 and S3-compatible object stores. It uses SwiftUI, the macOS 26 Liquid Glass appearance, and [Soto](https://github.com/soto-project/soto) behind a replaceable S3 adapter. It stays focused on S3 rather than adding unrelated file protocols.

## Download

Download the latest signed and notarized build from [GitHub Releases](https://github.com/raelsei/openbucket/releases/latest). Open the macOS DMG, drag OpenBucket to Applications, and launch it there. The release includes a SHA-256 checksum; the app supports Apple silicon and Intel Macs running macOS 26 or later. See [how releases are prepared](docs/RELEASING.md).

## See it in action

The screenshots show a real OpenBucket window connected to a local Garage bucket with the [included demo objects](#demo-data).

![Grid view showing S3 image and video objects with a right-side information panel](docs/media/browser-grid.jpg)

![List view showing per-file selection, sorting, and batch download controls](docs/media/browser-list.jpg)

## What works

| Area | Current behavior |
| --- | --- |
| Connections | Multiple profiles, custom HTTP or HTTPS endpoints, region and addressing style, optional session token |
| Restricted accounts | Open a known bucket without account-wide `ListBuckets` permission; start at a chosen object-key prefix |
| Browsing | Grid and sortable native table, prefix navigation, direct `s3://bucket/prefix/` jump, refresh, incremental `ListObjectsV2` loading |
| Media | Image and video thumbnails; metadata and artwork in the Info panel; Quick Look preview on demand |
| Downloads | Single-object download and per-file selection for batch download, with progress, cancellation, and failed-key reporting |
| Secrets | Access keys and session tokens in macOS Keychain; non-secret connection settings in a user-only profile file |

Browsing, inspection, previews, and downloads do not modify S3 objects. Upload, delete, sync, Finder mounting, and non-S3 protocols are outside this preview. [Compatibility details](docs/compatibility.md) document endpoint paths and provider test status; [security details](docs/security.md) explain local storage and temporary files.

## Connect to S3

After installing the app:

1. Choose **Add Connection**.
2. Enter the S3 endpoint URL and region. For a custom service such as Garage, choose **Path style** if its buckets live beneath the endpoint path.
3. Enter an access key and secret. Set **Known bucket** when the key cannot list all buckets. **Object key prefix** is an optional starting folder inside that bucket.
4. Test the connection, save it, and browse. Use the toolbar's location action to jump directly to `s3://bucket/prefix/`.

The endpoint URL path and object-key prefix are separate. For example, endpoint `https://store.example.com/s3/`, known bucket `photos`, and prefix `2026/travel/` address objects under the bucket without dropping `/s3/` from the signed request. A proxy must preserve the signed request path. See [endpoint behavior](docs/compatibility.md#endpoint-paths).

## Demo data

The repository includes six small demo objects in [`docs/demo-assets/travel`](docs/demo-assets/travel) and an opt-in [seed script](scripts/seed-demo.sh). It uploads them to a **bucket you specify**, under `openbucket-demo/travel/` by default; set `OPENBUCKET_DEMO_PREFIX` to choose another isolated prefix. The script needs `curl` with SigV4 support and these environment variables:

| Variable | Example or purpose |
| --- | --- |
| `OPENBUCKET_DEMO_ENDPOINT` | `http://127.0.0.1:3900` |
| `OPENBUCKET_DEMO_REGION` | `garage` or your provider's region |
| `OPENBUCKET_DEMO_BUCKET` | An existing bucket you can write to |
| `OPENBUCKET_DEMO_ACCESS_KEY` | Access key ID |
| `OPENBUCKET_DEMO_SECRET_KEY` | Secret access key |
| `OPENBUCKET_DEMO_PREFIX` | Optional destination prefix |

After setting them in your shell, run `scripts/seed-demo.sh` and open the printed `s3://` location in OpenBucket. The script replaces any objects with the same six names under that prefix, so use a disposable location. Credentials and local profile files are never part of the repository. The README screenshots use `showcase/gallery/` in an isolated local Garage fixture.

## Build and test

Building from source requires **macOS 26 or later** and **Xcode 27**. Open `OpenBucket.xcodeproj`, select the `OpenBucket` scheme, and run it on your Mac. The Xcode project is committed; [XcodeGen](https://github.com/yonaskolb/XcodeGen) is needed only after changing `project.yml`:

```sh
xcodegen generate --spec project.yml
```

```sh
swift format lint --strict --recursive App AppTests Packages/OpenBucket/Sources Packages/OpenBucket/Tests
xcodebuild test -project OpenBucket.xcodeproj -scheme OpenBucket -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
swift test --package-path Packages/OpenBucket
```

Unit tests need no AWS account. The optional live S3 test uses an isolated bucket and environment variables documented in [compatibility testing](docs/compatibility.md#live-compatibility-test). GitHub Actions runs format checks and app tests on an Xcode 27 runner.

## How the code is organized

```mermaid
flowchart LR
    UI[SwiftUI app] --> Core[OpenBucketCore]
    UI --> Local[Profiles + Keychain]
    Core --> Port[S3Repository protocol]
    Port --> Adapter[OpenBucketS3 adapter]
    Adapter --> Soto[Soto]
    Soto --> Store[(S3 endpoint)]
```

`OpenBucketCore` owns S3 values and browsing state. `OpenBucketS3` adapts Soto and keeps SDK types outside the UI. `App` contains SwiftUI and macOS storage; `OpenBucketApp` wires them together. The adapter boundary allows the SDK implementation to change without reshaping the browser.

Contributions are welcome; read [CONTRIBUTING.md](CONTRIBUTING.md). OpenBucket is licensed under [MIT](LICENSE).

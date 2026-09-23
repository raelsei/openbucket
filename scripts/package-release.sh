#!/bin/bash
set -euo pipefail

version=${1:-}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: scripts/package-release.sh MAJOR.MINOR.PATCH" >&2
  exit 2
fi

: "${OPENBUCKET_SIGNING_IDENTITY:?Set OPENBUCKET_SIGNING_IDENTITY to your Developer ID Application identity}"
: "${OPENBUCKET_TEAM_ID:?Set OPENBUCKET_TEAM_ID to your Apple Developer team ID}"
: "${OPENBUCKET_NOTARY_PROFILE:?Set OPENBUCKET_NOTARY_PROFILE to a notarytool Keychain profile}"

if [[ $OPENBUCKET_SIGNING_IDENTITY != 'Developer ID Application:'* ]]; then
  echo "Release signing requires a Developer ID Application identity." >&2
  exit 1
fi

root=$(cd "$(dirname "$0")/.." && pwd)
if [[ -n $(git -C "$root" status --porcelain) ]]; then
  echo "Commit or discard local changes before packaging a release." >&2
  exit 1
fi

distribution="$root/dist"
filename="OpenBucket-v${version}-macOS.dmg"
destination="$distribution/$filename"

mkdir -p "$distribution"
if [[ -e $destination ]]; then
  echo "Release asset already exists: $destination" >&2
  exit 1
fi

work=$(mktemp -d "$distribution/.release.XXXXXX")
trap 'rm -rf "$work"' EXIT

xcodebuild archive \
  -project "$root/OpenBucket.xcodeproj" \
  -scheme OpenBucket \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$root/DerivedData/Release" \
  -archivePath "$work/OpenBucket.xcarchive" \
  MARKETING_VERSION="$version" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$OPENBUCKET_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$OPENBUCKET_TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS='--options=runtime --timestamp'

app="$work/OpenBucket.xcarchive/Products/Applications/OpenBucket.app"
if [[ ! -d $app ]]; then
  echo "Xcode did not produce OpenBucket.app in the archive." >&2
  exit 1
fi

actual_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
if [[ $actual_version != "$version" ]]; then
  echo "Archive version $actual_version does not match requested version $version." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"

mkdir "$work/volume"
/usr/bin/ditto "$app" "$work/volume/OpenBucket.app"
ln -s /Applications "$work/volume/Applications"

image="$work/$filename"
/usr/sbin/diskutil image create from \
  --volumeName "OpenBucket $version" \
  --format UDZO \
  "$work/volume" \
  "$image"

/usr/bin/hdiutil verify "$image"
xcrun notarytool submit "$image" \
  --keychain-profile "$OPENBUCKET_NOTARY_PROFILE" \
  --wait \
  --output-format json > "$work/notarization.json"

status=$(/usr/bin/plutil -extract status raw -o - "$work/notarization.json")
if [[ $status != Accepted ]]; then
  cat "$work/notarization.json" >&2
  echo "Notarization was not accepted; no release asset was produced." >&2
  exit 1
fi

xcrun stapler staple "$image"
xcrun stapler validate "$image"
/usr/bin/hdiutil verify "$image"

mv "$image" "$destination"
(
  cd "$distribution"
  /usr/bin/shasum -a 256 "$filename" > "$filename.sha256"
)

echo "Ready to review:"
echo "$destination"
echo "$destination.sha256"

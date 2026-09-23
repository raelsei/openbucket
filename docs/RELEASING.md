# Releasing OpenBucket for macOS

Users download the app from [GitHub Releases](https://github.com/raelsei/openbucket/releases). Each published release has a tag such as `v0.1.0`, release notes, a versioned `OpenBucket-v0.1.0-macOS.dmg`, and a matching `.sha256` file. The DMG contains a universal Apple silicon and Intel `OpenBucket.app` and an Applications shortcut. GitHub's source archives are for developers; they are not the app installer.

There is no binary release yet. Publish one only after the DMG is signed with Developer ID, accepted by Apple's notary service, stapled, and tested from the downloaded file. [Apple's direct-distribution guidance](https://developer.apple.com/documentation/technologyoverviews/distribution) explains why this matters for Gatekeeper.

## One-time setup

1. Install a **Developer ID Application** certificate in this Mac's Keychain. Check that `security find-identity -v -p codesigning` lists it as valid.
2. Create a local notarytool Keychain profile. The following command securely prompts for an app-specific Apple ID password; do not put that password in the repository or shell history:

   ```sh
   xcrun notarytool store-credentials openbucket-release \
     --apple-id YOUR_APPLE_ID \
     --team-id YOUR_TEAM_ID
   ```

3. Set the identity name and team ID in your shell. Keep the notary profile in Keychain:

   ```sh
   export OPENBUCKET_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
   export OPENBUCKET_TEAM_ID='TEAMID'
   export OPENBUCKET_NOTARY_PROFILE='openbucket-release'
   ```

The project disables signing for ordinary local and CI builds. The release script enables Developer ID signing and Hardened Runtime for its archive. No certificate, private key, or notarization password belongs in GitHub Actions secrets for this local workflow.

## Prepare a release

1. Update the version in `project.yml`, regenerate `OpenBucket.xcodeproj` with `xcodegen generate --spec project.yml`, and update the release notes. Start with [v0.1.0 notes](releases/v0.1.0.md) for the first release.
2. Run the format check and macOS tests shown in the main README. Commit and push a clean `main` branch.
3. Build and notarize the DMG:

   ```sh
   scripts/package-release.sh 0.1.0
   ```

   The script refuses to put an unnotarized image in `dist/`. It verifies the app signature, waits for notarization to be accepted, staples the ticket to the DMG, verifies the DMG, and writes its SHA-256 checksum. `dist/` is ignored by Git.

4. Mount the DMG and test the app after copying it to Applications. Check a fresh connection, a known bucket and prefix, a media thumbnail, a download, and first launch from a downloaded copy. Test on another Mac when possible.
5. Tag the exact tested commit and create a **draft** GitHub release:

   ```sh
   git tag -a v0.1.0 -m 'OpenBucket v0.1.0'
   git push origin v0.1.0
   gh release create v0.1.0 \
     dist/OpenBucket-v0.1.0-macOS.dmg \
     dist/OpenBucket-v0.1.0-macOS.dmg.sha256 \
     --draft --verify-tag \
     --title 'OpenBucket v0.1.0' \
     --notes-file docs/releases/v0.1.0.md
   ```

6. Review the draft's assets, notes, and download on GitHub, then publish it. After the first release, update the README's current no-release message. The stable link for users is `https://github.com/raelsei/openbucket/releases/latest`.

Do not reuse a version tag for different app bits. Fixes after publishing get a new version and a new tag.

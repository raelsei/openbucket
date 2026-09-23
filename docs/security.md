# Local data and credential handling

OpenBucket has no app database. Non-secret connection settings live in `~/Library/Application Support/OpenBucket/profiles.json`, within a user-only directory and with user-only file permissions. The JSON contains a random credential reference, not the access key, secret key, or session token.

Credentials are stored as macOS Keychain generic password items. The store prefers the data-protection Keychain with `WhenUnlockedThisDeviceOnly` and reads older login-Keychain items for migration. The current debug build is unsigned, so macOS denies data-protection Keychain access and the app falls back to the login Keychain. A signed release needs the appropriate entitlement and a verification run before it can claim the stronger storage mode.

Image and video thumbnails are downloaded only for objects up to 8 MB. Quick Look preview is an explicit action and has a 64 MB limit. Their local copies use private temporary directories and are removed after use. A crash can leave a temporary preview until the operating system clears its temporary directory.

Downloads stream through a private temporary file next to the destination, then move into place only after the transfer completes. A failed or cancelled download leaves an existing destination intact. A batch download creates a new `OpenBucket Export-*` folder inside the chosen directory; completed files stay there if a later file fails or the batch is cancelled. Name collisions receive unique filenames rather than overwriting another selected object.

The included demo seeder is separate from the app. It reads credentials from environment variables and uploads only the six named demo objects to the bucket and prefix you choose. It does not modify the app's Keychain or profile file.

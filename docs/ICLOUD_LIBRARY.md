# Automatic library and family sharing

On first launch, the welcome screen explains storage and asks the person to tap **Continue**. There is no library folder chooser or folder creation workflow. After consent, an actor resolves `iCloud.com.matteozajac.bedtimestories` and creates **Documents/Books** inside the app’s public **Always Near Stories** iCloud Drive container using file coordination. Apple grants sandbox access to this container through the signed iCloud entitlement; iOS does not show a document-picker permission prompt for that access. [Apple container API](https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)).

When iCloud is unavailable, the app creates **Books** in its local Documents directory and clearly labels storage as on this device. Activation/relaunch checks iCloud again. Existing local books are copied when iCloud becomes available. Published books sync through iCloud Drive for devices signed into the **same Apple Account**; reading/listening progress and unpublished drafts remain device-local. Root/account changes reset active playback and select account-scoped cache/progress storage.

The public-container Info.plist metadata names **Always Near Stories**. iCloud Drive/Files appearance depends on the user’s system settings, a signed build with updated version, and actual container content. `NSMetadataQuery` discovers remote `book.json` files even when they are not downloaded; scans and reads coordinate file access and initiate placeholder downloads. [Apple’s document synchronization guide](https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment).

## Existing libraries

A previous security-scoped folder bookmark is used once to copy valid books into the default library. Original folders/books are never deleted. Matching content is skipped; a changed book with the same identity becomes a separate **Recovered copy** rather than overwriting either version. Hidden migration receipts prevent duplicate copies or resurrecting a deliberately deleted unchanged copy on relaunch. Unavailable files leave migration pending with **Retry Library Setup** in Settings. The source stays safe; other available books can still appear.

## Family sharing through Files

Use the existing **Share Book** action to export `.bedtimestory`, send/share it through Files or AirDrop, and open/import it in a relative’s app. Each recipient keeps their own default library.

People can also manage folder invitations in Files. Sharing a folder does **not** automatically redirect a relative’s Always Near Stories library to that folder. This version has no shared-account synchronization or in-app family invitation UI, and no library picker. A recipient imports a shared portable book instead. [Apple’s Files sharing guide](https://support.apple.com/guide/iphone/share-files-and-folders-in-icloud-drive-iph17f9f92a6/ios).

## Provisioning and checks — 2 October 2026

The personal App ID `com.matteozajac.bedtimestories` has iCloud enabled. Automatic signing produced a profile granting the exact iCloud/ubiquity container, and the signed Release build passed. Both normal and optional PCC entitlements include the same container; enabling PCC later must retain iCloud access.

Five native tests cover consent before creation, fixed local/cloud destination, local-to-cloud copy and progress/relaunch preservation, old bookmark migration, changed-ID conflict recovery/idempotence, unavailable sources, and remote-discovered folder containment. The full 20-test suite passed on each iPhone/iPad simulator. The Polish iPad UI confirmed the automatic destination, local fallback, migration of its previous books, and no folder chooser: [Settings screenshot](qa/default-library-settings-ipad-pl.png).

Real-device iCloud upload/download, evicted files, account changes, offline recovery, Files folder visibility, and same-account synchronization still require signed-device testing. Mock containers and simulator storage do not prove these production behaviors.

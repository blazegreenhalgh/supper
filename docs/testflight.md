# TestFlight and Xcode Cloud

## App

- App Store Connect name: **Supper - Shared Cookbook**
- Home-screen name: **Supper**
- Bundle identifier: `com.blazegreenhalgh.Supper`
- Apple development team: `H8STHXYFGD`
- App Store Connect ID: `6811593112`
- [TestFlight](https://appstoreconnect.apple.com/apps/6811593112/testflight)
- [Xcode Cloud](https://appstoreconnect.apple.com/apps/6811593112/ci)

## Setup status — 13 September 2026

The app record exists. The release configuration, app icon, tester notes, and
cloud test script are committed to `main`. A signed Release archive and a signed
iOS simulator build succeeded. Both domain tests passed, and a grocery item
survived quitting and reopening the simulator app.

Xcode's first-workflow setup is paused at **Grant Access to Your Source Code**.
The existing Apple Xcode Cloud GitHub installation has `envelope` access. Adding
only `supper` is prepared in GitHub and awaits the user's permission to save.
No TestFlight build has been uploaded yet; automatic delivery is not active.

## Workflow prepared in Xcode

- Name: **Main → TestFlight**
- Repository: `https://github.com/blazegreenhalgh/supper`
- Project: `Supper.xcodeproj`; scheme: `Supper`
- Trigger: changes to any file on `main`; auto-cancel older builds
- Environment: latest released Xcode and macOS
- Action: archive iOS, with App Store distribution preparation
- Pre-build verification: `ci_scripts/ci_post_clone.sh` runs `swift test`
- Tester instructions: `TestFlight/WhatToTest.en-US.txt`

Apple requires the repository setup to finish before the workflow editor enables
TestFlight post-actions. After access is saved, finish setup, configure an internal
TestFlight group containing the owner, add that group to the workflow, and start
the first build from the current `main` commit. Verify the archive, processing,
group assignment, and tester availability separately.

The archive preparation setting makes a build eligible for TestFlight. A public
App Store release requires a separate review submission. No public release was
requested or submitted.

## CloudKit

The signing profile includes `iCloud.com.blazegreenhalgh.Supper`. Background remote
notifications are configured. Production schema deployment and multi-account
sync have not been verified. Household invitations are not implemented in the
starter app; the initial tester notes state this limitation.

## Daily use after setup completes

Commit changes and push `main` to start a cloud build. Update the tester notes
when a change needs specific testing. Local edits alone do not trigger a build.
Check the Xcode Cloud result and the build's TestFlight status before saying an
update is available to testers.

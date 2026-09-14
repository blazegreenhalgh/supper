# TestFlight and Xcode Cloud

## App

- App Store Connect name: **Supper - Shared Cookbook**
- Home-screen name: **Supper**
- Bundle identifier: `com.blazegreenhalgh.Supper`
- Apple development team: `H8STHXYFGD`
- App Store Connect ID: `6811593112`
- [TestFlight](https://appstoreconnect.apple.com/apps/6811593112/testflight)
- [Xcode Cloud](https://appstoreconnect.apple.com/apps/6811593112/ci)

## Setup — 13 September 2026

The app record exists. The release configuration, app icon, tester notes, and
cloud test script are committed to `main`. A signed Release archive and a signed
iOS simulator build succeeded. Both domain tests passed, and a grocery item
survived quitting and reopening the simulator app.

Apple's Xcode Cloud GitHub integration is connected to `supper`. The workflow is
active and delivers successful iOS archives to the internal **Testing** group.
The group contains Blaze and Valeria. Apple controls build processing and
TestFlight availability; check the live build status before installing an update.

## Workflow

- Name: [Main → TestFlight](https://appstoreconnect.apple.com/teams/cc725002-f445-4b31-8f8d-dbcf971f1f07/apps/6811593112/ci/workflows/BBE431BB-27A4-4A6C-A174-D1CED03874B3)
- Repository: `https://github.com/blazegreenhalgh/supper`
- Project: `Supper.xcodeproj`; scheme: `Supper`
- Trigger: changes to any file on `main`; auto-cancel older builds
- Environment: latest released Xcode and macOS
- Action: archive iOS, with App Store distribution preparation
- Post-action: internal TestFlight distribution to **Testing**
- Pre-build verification: `ci_scripts/ci_post_clone.sh` runs `swift test`
- Tester instructions: `TestFlight/WhatToTest.en-US.txt`

The workflow is stored in Apple's service and can be edited in Xcode or App Store
Connect. Xcode Cloud manages signing and build numbers. Verify the archive,
processing, group assignment, and tester availability separately.

The archive preparation setting makes a build eligible for TestFlight. A public
App Store release requires a separate review submission. No public release was
requested or submitted.

## CloudKit

The signing profile includes `iCloud.com.blazegreenhalgh.Supper`. Background remote
notifications are configured. The household update implements invitations, member identity and private/shared library selection. Production schema deployment and live multi-account acceptance/sync require signed-device verification; see [household update](household-update.md) for the additive schema and release checks.

## Daily use

Commit changes and push `main` to start a cloud build. Update the tester notes
when a change needs specific testing. Local edits alone do not trigger a build.
Check the Xcode Cloud result and the build's TestFlight status before saying an
update is available to testers.

Install Apple's TestFlight app, accept the Supper invitation, and enable automatic
updates for Supper in TestFlight. A fresh build is required before an installed
TestFlight build expires.

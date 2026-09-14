# Library deletion and iCloud sharing — 14 September 2026

## App changes

Household settings offers a menu and trailing swipe action on every library. Owned libraries use **Delete library**; incoming libraries use **Leave library**. Both require a confirmation explaining the effect. Full-swipe deletion is disabled.

- Unshared owned libraries delete only their root and cascade through recipes, ingredients, steps, reactions, collections, members and groceries. Other roots in the same private store remain intact.
- Shared libraries use `NSPersistentCloudKitContainer.purgeObjectsAndRecordsInZone`. For an owner this deletes the shared library; for a participant this ends their participation and removes their local graph. An incoming library with missing share metadata never falls back to managed-object deletion, which could delete the owner's content.
- A zone purge is refused if another library root uses that share. Confirmation applies to one library, never an unrelated graph.
- Library changes and local edits are blocked during removal. A confirmed purge waits for Core Data's completion, since cancelling a local wait would not cancel a destructive server operation.
- Selection moves to a remaining library. Only removing the last library creates a new empty private library. No library is removed without an explicit user action.

**Check iCloud** shows progress and a visible account result. Its successful result is separate from sync and sharing errors: an authenticated account does not prove that invitations work. Errors remain visible with a Copy iCloud diagnostics action. A nested missing-production-schema error now has actionable wording instead of a long record dump. Sharing callbacks are explicitly Sendable so CloudKit can invoke them off the main actor.

## Required server configuration

The reported TestFlight error is `Cannot create new type cloudkit.share in production schema`. This is a server configuration failure. An app update, reinstall, account check, or new recipe library cannot deploy the missing schema.

For team **H8STHXYFGD**, container **iCloud.com.blazegreenhalgh.Supper**:

1. In CloudKit Console, select **CloudKit Database**, the Supper container and its development environment.
2. Confirm `cloudkit.share` exists under Record Types. If it is absent, run the current Supper Debug build from Xcode on a device signed into iCloud, then create an invitation using a disposable development library. This exercises the actual Core Data sharing flow and creates Apple's sharing record type. Do not attempt to create the reserved type as a custom record.
3. Check the development schema also includes the current Core Data model's entities and fields (see `household-update.md`). Use a dedicated development schema initialization workflow when needed; never call `initializeCloudKitSchema` in production or as a normal app launch operation.
4. Select **Deploy Schema Changes**, review the additive changes, then **Deploy**. This copies schema, not development recipes. Do not reset an environment or delete production records.
5. Retry Invite or manage sharing in TestFlight. Verify opening an existing invitation, sending a new one, recipient acceptance and updates between two different Apple accounts.

The CloudKit Console requires Apple sign-in in this workspace. No server schema deployment has been performed by this code change.

## Verification

Added persistence coverage for graph cascade/isolation, keeping a non-active selection, selecting a remaining incoming library, removal of the last library, missing sharing metadata, stale IDs/concurrent actions, visible offline account feedback and nested production-schema errors. Added a UI regression for Check iCloud feedback, cancelling removal and confirming removal.

The editing workspace has no Swift or Xcode toolchain. Apple's frameworks and the new tests must run in the repository's macOS CI. Signed-device owner deletion, participant leaving, offline/retry behavior and two-account sharing still require live verification. Production schema deployment is a separate gate from an app build.

## Apple references

- [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users) — schema initialization, TestFlight's production environment, and purge behavior for owners/participants.
- [Deploying an iCloud Container’s Schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema) — reviewing and deploying additive development schema changes.

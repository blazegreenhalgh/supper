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

- Both development and production initially listed only `Users`. There were no pending schema changes to deploy.
- Created `cloudkit.share` using CloudKit Console's native New Record Type action. Apple generated its nine standard metadata fields automatically.
- Prepared `Config/CloudKitSchema.ckdb` from the current managed object model, using Apple's documented Core Data mappings and the generated sharing/move-receipt metadata already used by the Envelopes app. It includes all eight entities, string/binary asset companions, to-one relationship keys and sharing metadata. It contains no user records.
- CloudKit Console reported **Validation Passed**, then **The schema was successfully imported** in development. Existing `Users` and `cloudkit.share` definitions were retained.
- The approved production deployment contained only nine new record types and their required indexes/default schema role grants. No existing types, fields, or user records are removed. The app continues to store recipes in private/shared databases; schema grants do not publish those private records to the public database.
- **Production deployment completed after explicit user approval.** CloudKit Console confirmed **Changes Deployed — The schema is deployed to Production** on 14 September 2026. The production record-type list was checked for all eight Core Data entities and `cloudkit.share`.

Retry Invite or manage sharing in TestFlight. Verify opening an existing invitation, sending a new one, recipient acceptance and two-account recipe/grocery sync. Do not reset an environment or delete production records.

For future model changes, update the checked schema and its regression test or initialize it using a dedicated iCloud-enabled development build. Never call `initializeCloudKitSchema` in production or on every normal app launch.

## Verification

Added persistence coverage for graph cascade/isolation, keeping a non-active selection, selecting a remaining incoming library, removal of the last library, missing sharing metadata, stale IDs/concurrent actions, visible offline account feedback and nested production-schema errors. Added a UI regression for Check iCloud feedback, cancelling removal and confirming removal.

The repository's macOS CI passed the domain and persistence tests, including the schema/model comparison, and built the iOS simulator app. UI regression execution is tracked in PR #3. The editing workspace has no Apple toolchain. Signed-device owner deletion, participant leaving, offline/retry behavior and two-account sharing still require live verification. Production schema deployment is a separate gate from an app build.

## Apple references

- [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users) — schema initialization, TestFlight's production environment, and purge behavior for owners/participants.
- [Deploying an iCloud Container’s Schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema) — reviewing and deploying additive development schema changes.

- [Reading CloudKit Records for Core Data](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data) — record names, attribute types, asset companions and relationship fields.

#if SWIFT_PACKAGE
import SupperCore
#endif
@preconcurrency import CoreData
import CloudKit

extension RecipeStore {
    func checkCloudAccount() async {
        guard !checkingCloudAccount, shareProgress == nil, removingHouseholdID == nil else { return }
        do { try await verifyCloudAccount() }
        catch {
            if !(error is CancellationError) {
                cloudAccountMessage = CloudProblem.message(error)
                recordCloudError(error, operation: "Checking iCloud account")
            }
        }
    }

    private func verifyCloudAccount() async throws {
        guard persistence.cloudEnabled else {
            throw SupperError.invalid("iCloud is disabled in this build. Libraries are saved on this device.")
        }
        guard isReady else { throw SupperError.invalid("Your libraries are still opening. Try again in a moment.") }
        checkingCloudAccount = true
        defer { checkingCloudAccount = false }
        let cloud = CKContainer(identifier: persistence.containerIdentifier)
        let status: CKAccountStatus = try await CloudRequest.run(timeout: 15) { completion in
            cloud.accountStatus { @Sendable status, error in
                if let error { completion(.failure(error)) } else { completion(.success(status)) }
            }
        }
        if let message = CloudProblem.accountMessage(status) { throw SupperError.invalid(message) }
        let recordID: CKRecord.ID = try await CloudRequest.run(timeout: 15) { completion in
            cloud.fetchUserRecordID { @Sendable record, error in
                if let error { completion(.failure(error)) }
                else if let record { completion(.success(record)) }
                else { completion(.failure(SupperError.invalid("iCloud couldn't identify your account. Try again."))) }
            }
        }
        try Task.checkCancellation()
        identity.resolve(accountID: recordID.recordName)
        try ensureMember(); try refresh()
        // Account availability says nothing about production schema or a previous sync failure.
        cloudAccountMessage = "Your iCloud account is connected."
    }

    func reportSharingError(_ error: Error) {
        sharingMessage = CloudProblem.message(error)
        recordCloudError(error, operation: shareProgress ?? "Household sharing")
    }

    func prepareShare() async throws -> CKShare {
        guard !checkingCloudAccount, removingHouseholdID == nil, shareProgress == nil else {
            throw SupperError.invalid("Wait for the current iCloud action to finish.")
        }
        defer { shareProgress = nil }
        do {
            let share = try await createOrFetchShare()
            sharingMessage = nil
            return share
        } catch {
            if !(error is CancellationError) { reportSharingError(error) }
            throw error
        }
    }

    private func createOrFetchShare() async throws -> CKShare {
        guard shareProgress == nil else { throw SupperError.invalid("An invitation is already being prepared.") }
        guard persistence.cloudEnabled, let root = library, let persistentStore = root.objectID.persistentStore else {
            throw SupperError.invalid("Open your household in an iCloud-enabled build to invite someone.")
        }
        let rootID = root.objectID; let householdID = root.id
        let incoming = persistentStore == persistence.sharedStore
        shareProgress = "Checking iCloud…"
        try await verifyCloudAccount(); try Task.checkCancellation()
        let container = persistence.container
        let context = container.newBackgroundContext()
        let cloud = CKContainer(identifier: persistence.containerIdentifier)
        let database = incoming ? cloud.sharedCloudDatabase : cloud.privateCloudDatabase
        shareProgress = "Reading invitation…"
        let existing = try await resolveShare(for: rootID, in: persistentStore, database: database)
        var invitation: CKShare
        if let existing {
            do {
                invitation = try await CloudRequest.run { completion in
                    database.fetch(withRecordID: existing.recordID) { @Sendable record, error in completion(CloudProblem.shareResult(record, error: error)) }
                }
            } catch {
                guard !incoming, existing.url == nil, (error as? CKError)?.code == .unknownItem else { throw error }
                invitation = existing
            }
        } else {
            guard !incoming else { throw SupperError.invalid("Sharing access has changed. Ask the household owner for a new invitation.") }
            shareProgress = "Preparing household…"
            // Cancelling the UI task cannot cancel Core Data's move to a shared zone.
            // Keep the action locked until the callback, so retries cannot overlap it.
            invitation = try await CloudRequest.untilFinished { completion in
                context.perform { @Sendable in
                    do {
                        let root = try context.existingObject(with: rootID)
                        container.share([root], to: nil) { @Sendable [context] _, share, _, error in
                            withExtendedLifetime(context) { completion(CloudProblem.shareResult(share, error: error)) }
                        }
                    } catch { completion(.failure(error)) }
                }
            }
            invitation.publicPermission = .none
        }
        try Task.checkCancellation()
        if !incoming {
            invitation[CKShare.SystemFieldKey.title] = (root.name ?? "Our Supper") as CKRecordValue
            shareProgress = "Saving invitation…"
            do { invitation = try await saveShareOnServer(invitation, database: database) }
            catch {
                guard let latest = CloudProblem.serverShare(from: error) else { throw error }
                latest[CKShare.SystemFieldKey.title] = (root.name ?? "Our Supper") as CKRecordValue
                invitation = try await saveShareOnServer(latest, database: database)
            }
        }
        try CloudProblem.requireShareURL(invitation.url)
        shareProgress = "Finishing invitation…"
        try await persistShare(invitation, in: persistentStore)
        try Task.checkCancellation()
        guard activeHouseholdID == householdID else { throw SupperError.invalid("The selected household changed. Open its invitation again.") }
        return invitation
    }

    /// Resolve only shares tied to this object's exact zone, never an arbitrary
    /// invitation from the store. A partial/old invitation cache is not proof that
    /// the library is unshared.
    func cachedShare(for objectID: NSManagedObjectID, in store: NSPersistentStore) throws -> CKShare? {
        let container = persistence.container
        return try HouseholdCloudLookup.cachedShare(
            matching: { try container.fetchShares(matching: [objectID])[objectID] },
            recordID: { container.recordID(for: objectID) },
            shares: { try container.fetchShares(in: store) })
    }

    private func resolveShare(for objectID: NSManagedObjectID, in store: NSPersistentStore,
                              database: CKDatabase) async throws -> CKShare? {
        var lookupError: Error?
        do {
            if let share = try cachedShare(for: objectID, in: store) { return share }
        } catch { lookupError = error }
        guard let recordID = persistence.container.recordID(for: objectID) else {
            if let lookupError { throw lookupError }
            return nil
        }
        let zone: CKRecordZone = try await CloudRequest.run { completion in
            database.fetch(withRecordZoneID: recordID.zoneID) { @Sendable zone, error in
                if let error { completion(.failure(error)) }
                else if let zone { completion(.success(zone)) }
                else { completion(.failure(SupperError.invalid("iCloud didn't return this library's sharing information."))) }
            }
        }
        guard let shareID = zone.share?.recordID else {
            if let lookupError { throw lookupError }
            return nil
        }
        return try await CloudRequest.run { completion in
            database.fetch(withRecordID: shareID) { @Sendable record, error in
                completion(CloudProblem.shareResult(record, error: error))
            }
        }
    }
    private func saveShareOnServer(_ share: CKShare, database: CKDatabase) async throws -> CKShare {
        try await CloudRequest.run { completion in
            let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.configuration.timeoutIntervalForRequest = 15; operation.configuration.timeoutIntervalForResource = 25
            operation.perRecordSaveBlock = { @Sendable _, result in completion(result.flatMap { CloudProblem.shareResult($0, error: nil) }) }
            operation.modifyRecordsResultBlock = { @Sendable result in if case .failure(let error) = result { completion(.failure(error)) } }
            database.add(operation)
        }
    }
    func persistShare(_ share: CKShare, in store: NSPersistentStore) async throws {
        let container = persistence.container
        let context = container.newBackgroundContext()
        let _: CKShare = try await CloudRequest.untilFinished { completion in
            context.perform { @Sendable in container.persistUpdatedShare(share, in: store) { @Sendable saved, error in completion(CloudProblem.shareResult(saved, error: error)) } }
        }
        try refresh()
    }

    /// Owned libraries are deleted; incoming libraries are left without deleting the owner's recipes.
    func removeHousehold(_ id: UUID) async throws {
        guard isReady, removingHouseholdID == nil, shareProgress == nil,
              !checkingCloudAccount, !joiningHousehold else {
            throw SupperError.invalid("Wait for the current household action to finish.")
        }
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let root = try context.fetch(request).first,
              let persistentStore = root.objectID.persistentStore else {
            throw SupperError.invalid("This library is no longer available.")
        }
        let incoming = persistentStore == persistence.sharedStore
        let container = persistence.container
        // An incoming zone can be purged even if its cached CKShare is missing.
        // Never replace that with managed-object deletion, which syncs to the owner.
        let recordZone = persistence.cloudEnabled ? container.recordID(for: root.objectID)?.zoneID : nil
        let share: CKShare?
        do { share = persistence.cloudEnabled ? try cachedShare(for: root.objectID, in: persistentStore) : nil }
        catch {
            guard incoming, recordZone != nil else {
                recordCloudError(error, operation: "Reading library for removal")
                throw error
            }
            share = nil
        }
        let zoneToPurge = incoming ? (share?.recordID.zoneID ?? recordZone) : share?.recordID.zoneID
        var otherZones: [CKRecordZone.ID?] = []
        if zoneToPurge != nil {
            let rootsRequest = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
            rootsRequest.affectedStores = [persistentStore]
            let otherIDs = try context.fetch(rootsRequest).filter { $0.objectID != root.objectID }.map(\.objectID)
            for otherID in otherIDs {
                let zone = try container.recordID(for: otherID)?.zoneID
                    ?? cachedShare(for: otherID, in: persistentStore)?.recordID.zoneID
                otherZones.append(zone)
            }
        }
        let removal = try HouseholdRemovalPlan(incoming: incoming, zoneID: zoneToPurge, otherZones: otherZones)
        // Finish any pending local saves before a purge invalidates managed objects.
        if context.hasChanges { try context.save() }
        let selectedID = activeHouseholdID
        removingHouseholdID = id
        defer { removingHouseholdID = nil }
        do {
            if case .purge(let zoneID) = removal {
                // Core Data removes the zone and its local graph. In the shared store this
                // ends only this participant's access. Do not report a timeout as cancellation:
                // a destructive operation may still be running on Apple's server.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    container.purgeObjectsAndRecordsInZone(with: zoneID, in: persistentStore) { @Sendable _, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                context.refreshAllObjects()
            } else {
                // Unshared libraries can share a private zone; delete only this root's graph.
                context.delete(root)
                do { try context.save() } catch { context.rollback(); throw error }
            }
            if selectedID == id { library = nil }
            if preferences.string(forKey: "activeHousehold") == id.uuidString {
                preferences.removeObject(forKey: "activeHousehold")
            }
            try ensureLibrary()
            preferences.set(activeHouseholdID?.uuidString, forKey: "activeHousehold")
            try ensureMember()
            removingHouseholdID = nil
            try refresh()
        } catch {
            recordCloudError(error, operation: incoming ? "Leaving library" : "Deleting library")
            removingHouseholdID = nil
            // Reconcile even if the server reports an error after changing the local store.
            try? ensureLibrary()
            try? refresh()
            throw error
        }
    }

    func receiveInvitation(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == persistence.containerIdentifier else { errorMessage = "This invitation belongs to another app."; return }
        if !isReady { queuedInvitations = [metadata] } else { pendingInvitation = metadata }
    }
    func acceptInvitation() async {
        guard !joiningHousehold, removingHouseholdID == nil else { return }
        guard let metadata = pendingInvitation else { return }
        guard persistence.cloudEnabled, let shared = persistence.sharedStore else { errorMessage = "Enable iCloud for Supper to join this household."; return }
        joiningHousehold = true
        do {
            let _: Void = try await CloudRequest.run(timeout: 45) { completion in
                persistence.container.acceptShareInvitations(from: [metadata], into: shared) { @Sendable _, error in
                    if let error { completion(.failure(error)) } else { completion(.success(())) }
                }
            }
            // Store the exact invitation identity. Arrival of any unrelated shared root cannot switch us.
            let recordID = metadata.share.recordID
            preferences.set(recordID.recordName, forKey: "pendingShareRecord")
            preferences.set(recordID.zoneID.zoneName, forKey: "pendingShareZone")
            preferences.set(recordID.zoneID.ownerName, forKey: "pendingShareOwner")
            pendingInvitation = nil
            cloudMessage = "Invitation accepted. Your household is downloading; your existing library is kept."
            try refresh()
        } catch { joiningHousehold = false; errorMessage = CloudProblem.message(error) }
    }
    func sharingStopped() {
        cloudMessage = "Sharing has stopped. Existing private libraries are kept. Choose your private library in Household settings if this household is no longer available."
        do { try refresh() } catch { errorMessage = error.localizedDescription }
    }
}

enum HouseholdCloudLookup {
    static func cachedShare(matching: () throws -> CKShare?, recordID: () -> CKRecord.ID?,
                            shares: () throws -> [CKShare]) throws -> CKShare? {
        var lookupError: Error?
        do { if let share = try matching() { return share } }
        catch { lookupError = error }
        if let zoneID = recordID()?.zoneID,
           let share = try shares().first(where: { $0.recordID.zoneID == zoneID }) { return share }
        if let lookupError { throw lookupError }
        return nil
    }
}

enum HouseholdRemovalPlan {
    case deleteObjects
    case purge(CKRecordZone.ID)

    init(incoming: Bool, zoneID: CKRecordZone.ID?, otherZones: [CKRecordZone.ID?]) throws {
        if let zoneID {
            guard otherZones.allSatisfy({ $0 != nil && $0 != zoneID }) else {
                throw SupperError.invalid("Supper couldn't confirm that this invitation contains only this library. No libraries were removed.")
            }
            self = .purge(zoneID)
        } else {
            guard !incoming else {
                throw SupperError.invalid("This library's iCloud identity isn't available. You can hide it on this iPhone using its library menu. The owner's recipes will be kept.")
            }
            self = .deleteObjects
        }
    }
}

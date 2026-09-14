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
                cloudDiagnostics = CloudProblem.diagnostics(error)
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
        cloudDiagnostics = CloudProblem.diagnostics(error)
    }

    func prepareShare() async throws -> CKShare {
        guard !checkingCloudAccount, removingHouseholdID == nil, shareProgress == nil else {
            throw SupperError.invalid("Wait for the current iCloud action to finish.")
        }
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
        shareProgress = "Checking iCloud…"; defer { shareProgress = nil }
        try await verifyCloudAccount(); try Task.checkCancellation()
        let container = persistence.container
        let context = container.newBackgroundContext()
        let cloud = CKContainer(identifier: persistence.containerIdentifier)
        let database = incoming ? cloud.sharedCloudDatabase : cloud.privateCloudDatabase
        shareProgress = "Reading invitation…"
        let existing: CKShare? = try await CloudRequest.run { completion in
            context.perform { @Sendable in
                do { completion(.success(try container.fetchShares(matching: [rootID])[rootID])) }
                catch { completion(.failure(error)) }
            }
        }
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
            invitation = try await CloudRequest.run { completion in
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
        let _: CKShare = try await CloudRequest.run { completion in
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
        // Never fall back to deleting shared managed objects: that would delete the owner's data.
        let share = persistence.cloudEnabled ? try container.fetchShares(matching: [root.objectID])[root.objectID] : nil
        if incoming && share == nil {
            throw SupperError.invalid("The sharing information isn't available yet. Connect to iCloud and try leaving this library again.")
        }
        if let share {
            let rootsRequest = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
            rootsRequest.affectedStores = [persistentStore]
            let otherIDs = try context.fetch(rootsRequest).filter { $0.objectID != root.objectID }.map(\.objectID)
            let others = otherIDs.isEmpty ? [:] : try container.fetchShares(matching: otherIDs)
            guard !others.values.contains(where: { $0.recordID.zoneID == share.recordID.zoneID }) else {
                throw SupperError.invalid("This invitation contains more than one library. Manage its sharing before removing it.")
            }
        }
        // Finish any pending local saves before a purge invalidates managed objects.
        if context.hasChanges { try context.save() }
        let selectedID = activeHouseholdID
        removingHouseholdID = id
        defer { removingHouseholdID = nil }
        do {
            if let share {
                // Core Data removes the zone and its local graph. In the shared store this
                // ends only this participant's access. Do not report a timeout as cancellation:
                // a destructive operation may still be running on Apple's server.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: persistentStore) { @Sendable _, error in
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
            if UserDefaults.standard.string(forKey: "activeHousehold") == id.uuidString {
                UserDefaults.standard.removeObject(forKey: "activeHousehold")
            }
            try ensureLibrary()
            UserDefaults.standard.set(activeHouseholdID?.uuidString, forKey: "activeHousehold")
            try ensureMember()
            removingHouseholdID = nil
            try refresh()
        } catch {
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
            UserDefaults.standard.set(recordID.recordName, forKey: "pendingShareRecord")
            UserDefaults.standard.set(recordID.zoneID.zoneName, forKey: "pendingShareZone")
            UserDefaults.standard.set(recordID.zoneID.ownerName, forKey: "pendingShareOwner")
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

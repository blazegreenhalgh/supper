#if SWIFT_PACKAGE
import SupperCore
#endif
@preconcurrency import CoreData
import CloudKit

extension RecipeStore {
    func checkCloudAccount() async {
        guard persistence.cloudEnabled, isReady else { return }
        do {
            let cloud = CKContainer(identifier: persistence.containerIdentifier)
            let status: CKAccountStatus = try await CloudRequest.run { completion in
                cloud.accountStatus { status, error in
                    if let error { completion(.failure(error)) } else { completion(.success(status)) }
                }
            }
            if let message = CloudProblem.accountMessage(status) { cloudMessage = message; return }
            let recordID: CKRecord.ID = try await CloudRequest.run { completion in
                cloud.fetchUserRecordID { record, error in
                    if let error { completion(.failure(error)) }
                    else if let record { completion(.success(record)) }
                    else { completion(.failure(SupperError.invalid("iCloud couldn't identify your account. Try again."))) }
                }
            }
            identity.resolve(accountID: recordID.recordName)
            try ensureMember(); try refresh(); cloudMessage = nil
        } catch { if !(error is CancellationError) { cloudMessage = CloudProblem.message(error) } }
    }

    func prepareShare() async throws -> CKShare {
        guard shareProgress == nil else { throw SupperError.invalid("An invitation is already being prepared.") }
        guard persistence.cloudEnabled, let root = library, let persistentStore = root.objectID.persistentStore else {
            throw SupperError.invalid("Open your household in an iCloud-enabled build to invite someone.")
        }
        let rootID = root.objectID; let householdID = root.id
        let incoming = persistentStore == persistence.sharedStore
        shareProgress = "Checking iCloud…"; defer { shareProgress = nil }
        await checkCloudAccount(); try Task.checkCancellation()
        if let cloudMessage { throw SupperError.invalid(cloudMessage) }
        let container = persistence.container
        let context = container.newBackgroundContext()
        let cloud = CKContainer(identifier: persistence.containerIdentifier)
        let database = incoming ? cloud.sharedCloudDatabase : cloud.privateCloudDatabase
        shareProgress = "Reading invitation…"
        let existing: CKShare? = try await CloudRequest.run { completion in
            context.perform {
                do { completion(.success(try container.fetchShares(matching: [rootID])[rootID])) }
                catch { completion(.failure(error)) }
            }
        }
        var invitation: CKShare
        if let existing {
            do {
                invitation = try await CloudRequest.run { completion in
                    database.fetch(withRecordID: existing.recordID) { record, error in completion(CloudProblem.shareResult(record, error: error)) }
                }
            } catch {
                guard !incoming, existing.url == nil, (error as? CKError)?.code == .unknownItem else { throw error }
                invitation = existing
            }
        } else {
            guard !incoming else { throw SupperError.invalid("Sharing access has changed. Ask the household owner for a new invitation.") }
            shareProgress = "Preparing household…"
            invitation = try await CloudRequest.run { completion in
                context.perform {
                    do {
                        let root = try context.existingObject(with: rootID)
                        container.share([root], to: nil) { [context] _, share, _, error in
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
            operation.perRecordSaveBlock = { _, result in completion(result.flatMap { CloudProblem.shareResult($0, error: nil) }) }
            operation.modifyRecordsResultBlock = { result in if case .failure(let error) = result { completion(.failure(error)) } }
            database.add(operation)
        }
    }
    func persistShare(_ share: CKShare, in store: NSPersistentStore) async throws {
        let container = persistence.container
        let context = container.newBackgroundContext()
        let _: CKShare = try await CloudRequest.run { completion in
            context.perform { container.persistUpdatedShare(share, in: store) { saved, error in completion(CloudProblem.shareResult(saved, error: error)) } }
        }
        try refresh()
    }
    func receiveInvitation(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == persistence.containerIdentifier else { errorMessage = "This invitation belongs to another app."; return }
        if !isReady { queuedInvitations = [metadata] } else { pendingInvitation = metadata }
    }
    func acceptInvitation() async {
        guard let metadata = pendingInvitation else { return }
        guard persistence.cloudEnabled, let shared = persistence.sharedStore else { errorMessage = "Enable iCloud for Supper to join this household."; return }
        joiningHousehold = true
        do {
            let _: Void = try await CloudRequest.run(timeout: 45) { completion in
                persistence.container.acceptShareInvitations(from: [metadata], into: shared) { _, error in
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

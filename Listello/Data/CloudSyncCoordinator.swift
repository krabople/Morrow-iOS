import CloudKit
import Foundation

enum CloudSyncStatus: Equatable {
    case starting
    case syncing
    case upToDate
    case offline
    case notSignedIn
    case unavailable

    var title: String {
        switch self {
        case .starting: L10n.text("Starting iCloud sync")
        case .syncing: L10n.text("Syncing")
        case .upToDate: L10n.text("Up to date")
        case .offline: L10n.text("Offline - changes will sync later")
        case .notSignedIn: L10n.text("Sign in to iCloud to sync")
        case .unavailable: L10n.text("iCloud sync unavailable")
        }
    }

    var systemImage: String {
        switch self {
        case .starting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .offline: "icloud.slash"
        case .notSignedIn, .unavailable: "exclamationmark.icloud"
        }
    }
}

private enum CloudEntityKind: String, Codable {
    case task
    case project
    case scheduleBreak
    case preferences
    case notificationDays
}

private struct CloudTrackedRecord: Codable {
    var kind: CloudEntityKind
    var payload: Data
    var userModificationDate: Date
    var lastKnownRecordData: Data?

    var lastKnownRecord: CKRecord? {
        get {
            guard let lastKnownRecordData else { return nil }
            do {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: lastKnownRecordData)
                unarchiver.requiresSecureCoding = true
                return CKRecord(coder: unarchiver)
            } catch {
                return nil
            }
        }
        set {
            guard let newValue else {
                lastKnownRecordData = nil
                return
            }
            let archiver = NSKeyedArchiver(requiringSecureCoding: true)
            newValue.encodeSystemFields(with: archiver)
            lastKnownRecordData = archiver.encodedData
        }
    }

    mutating func remember(_ record: CKRecord) {
        if let localDate = lastKnownRecord?.modificationDate,
           let remoteDate = record.modificationDate,
           localDate >= remoteDate {
            return
        }
        lastKnownRecord = record
    }

    func populate(_ record: CKRecord) {
        record.encryptedValues["kind"] = kind.rawValue
        record.encryptedValues["payload"] = payload
        record.encryptedValues["userModificationDate"] = userModificationDate
    }
}

private struct CloudSyncMetadata: Codable {
    var records: [String: CloudTrackedRecord] = [:]
    var stateSerialization: CKSyncEngine.State.Serialization?
}

private struct CloudPayload {
    let kind: CloudEntityKind
    let data: Data
}

actor CloudSyncCoordinator {
    static let containerIdentifier = "iCloud.com.krabople.morrow"
    static let zoneName = "Listello"
    static let recordType = "ListelloEntity"

    private static let container = CKContainer(identifier: containerIdentifier)

    private let metadataURL: URL
    private let onStateChange: @MainActor (ListelloState) -> Void
    private let onStatusChange: @MainActor (CloudSyncStatus) -> Void
    private let initialUserModificationDate: Date
    private var metadata: CloudSyncMetadata
    private var baseState: ListelloState
    private var syncEngine: CKSyncEngine?
    private var didCaptureInitialState = false
    private var hasFetchedChangesToApply = false

    init(
        metadataURL: URL,
        initialState: ListelloState,
        initialUserModificationDate: Date,
        onStateChange: @escaping @MainActor (ListelloState) -> Void,
        onStatusChange: @escaping @MainActor (CloudSyncStatus) -> Void
    ) {
        self.metadataURL = metadataURL
        self.baseState = initialState
        self.initialUserModificationDate = initialUserModificationDate
        self.onStateChange = onStateChange
        self.onStatusChange = onStatusChange
        if let data = try? Data(contentsOf: metadataURL),
           let saved = try? JSONDecoder().decode(CloudSyncMetadata.self, from: data) {
            self.metadata = saved
        } else {
            self.metadata = CloudSyncMetadata()
        }

        Task { await start() }
    }

    func capture(_ state: ListelloState) async {
        baseState = state
        guard let syncEngine else { return }

        let payloads = makePayloads(from: state)
        let isFirstCapture = !didCaptureInitialState
        didCaptureInitialState = true

        // A brand-new installation should download an existing iCloud library before
        // uploading default settings that could overwrite the person's real choices.
        if isFirstCapture, metadata.records.isEmpty, !hasUserContent(state) {
            return
        }

        var pendingChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        let now = isFirstCapture ? initialUserModificationDate : Date()

        for (recordName, payload) in payloads {
            if let existing = metadata.records[recordName], existing.payload == payload.data {
                continue
            }

            var tracked = metadata.records[recordName] ?? CloudTrackedRecord(
                kind: payload.kind,
                payload: payload.data,
                userModificationDate: now,
                lastKnownRecordData: nil
            )
            tracked.kind = payload.kind
            tracked.payload = payload.data
            tracked.userModificationDate = now
            metadata.records[recordName] = tracked
            pendingChanges.append(.saveRecord(recordID(for: recordName)))
        }

        let removedNames = Set(metadata.records.keys).subtracting(Set(payloads.keys))
        for recordName in removedNames {
            metadata.records[recordName] = nil
            pendingChanges.append(.deleteRecord(recordID(for: recordName)))
        }

        guard !pendingChanges.isEmpty else { return }
        persistMetadata()
        syncEngine.state.add(pendingRecordZoneChanges: pendingChanges)
        await publishStatus(.syncing)
    }

    func syncNow() async {
        guard let syncEngine else { return }
        await publishStatus(.syncing)
        do {
            try await syncEngine.fetchChanges()
            try await syncEngine.sendChanges()
            await publishStatus(.upToDate)
        } catch let error as CKError where Self.isTemporary(error.code) {
            await publishStatus(.offline)
        } catch {
            await publishStatus(.unavailable)
        }
    }

    private func start() async {
        await publishStatus(.starting)
        var configuration = CKSyncEngine.Configuration(
            database: Self.container.privateCloudDatabase,
            stateSerialization: metadata.stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        syncEngine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        await capture(baseState)

        do {
            let status = try await Self.container.accountStatus()
            guard status == .available else {
                await publishStatus(.notSignedIn)
                return
            }
            try await engine.fetchChanges()
            await publishStatus(.upToDate)
        } catch let error as CKError where Self.isTemporary(error.code) {
            await publishStatus(.offline)
        } catch {
            await publishStatus(.unavailable)
        }
    }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private func recordID(for recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    private func makePayloads(from state: ListelloState) -> [String: CloudPayload] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var payloads: [String: CloudPayload] = [:]

        for var task in state.tasks {
            // EventKit identifiers are device-local. The task itself syncs; each device
            // keeps its own link to any calendar event it exported.
            task.calendarEventIdentifier = nil
            if let data = try? encoder.encode(task) {
                payloads["task-\(task.id.uuidString)"] = CloudPayload(kind: .task, data: data)
            }
        }
        for project in state.projects {
            if let data = try? encoder.encode(project) {
                payloads["project-\(project.id.uuidString)"] = CloudPayload(kind: .project, data: data)
            }
        }
        for scheduleBreak in state.scheduleBreaks {
            if let data = try? encoder.encode(scheduleBreak) {
                payloads["break-\(scheduleBreak.id.uuidString)"] = CloudPayload(kind: .scheduleBreak, data: data)
            }
        }
        if let data = try? encoder.encode(state.preferences) {
            payloads["preferences"] = CloudPayload(kind: .preferences, data: data)
        }
        if let data = try? encoder.encode(state.notificationDayKeys.sorted()) {
            payloads["notification-days"] = CloudPayload(kind: .notificationDays, data: data)
        }
        return payloads
    }

    private func hasUserContent(_ state: ListelloState) -> Bool {
        !state.tasks.isEmpty || !state.projects.isEmpty || !state.scheduleBreaks.isEmpty || !state.notificationDayKeys.isEmpty
    }

    private func mergedState() -> ListelloState {
        let decoder = JSONDecoder()
        var tasks: [TaskItem] = []
        var projects: [ProjectItem] = []
        var scheduleBreaks: [ScheduleBreakItem] = []
        var preferences = baseState.preferences
        var notificationDayKeys = baseState.notificationDayKeys

        for tracked in metadata.records.values {
            switch tracked.kind {
            case .task:
                if let value = try? decoder.decode(TaskItem.self, from: tracked.payload) { tasks.append(value) }
            case .project:
                if let value = try? decoder.decode(ProjectItem.self, from: tracked.payload) { projects.append(value) }
            case .scheduleBreak:
                if let value = try? decoder.decode(ScheduleBreakItem.self, from: tracked.payload) { scheduleBreaks.append(value) }
            case .preferences:
                if let value = try? decoder.decode(ListelloPreferences.self, from: tracked.payload) { preferences = value }
            case .notificationDays:
                if let value = try? decoder.decode([String].self, from: tracked.payload) { notificationDayKeys = Set(value) }
            }
        }

        return ListelloState(
            tasks: tasks,
            projects: projects,
            scheduleBreaks: scheduleBreaks,
            notificationDayKeys: notificationDayKeys,
            preferences: preferences
        )
    }

    private func applyFetchedRecord(_ record: CKRecord) {
        guard
            let kindRaw = record.encryptedValues["kind"] as? String,
            let kind = CloudEntityKind(rawValue: kindRaw),
            let payload = record.encryptedValues["payload"] as? Data
        else { return }

        let remoteDate = record.encryptedValues["userModificationDate"] as? Date ?? .distantPast
        let name = record.recordID.recordName

        if var local = metadata.records[name] {
            if remoteDate > local.userModificationDate {
                local.kind = kind
                local.payload = payload
                local.userModificationDate = remoteDate
            } else if remoteDate < local.userModificationDate {
                syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }
            local.remember(record)
            metadata.records[name] = local
        } else {
            var tracked = CloudTrackedRecord(
                kind: kind,
                payload: payload,
                userModificationDate: remoteDate,
                lastKnownRecordData: nil
            )
            tracked.remember(record)
            metadata.records[name] = tracked
        }
    }

    private func applyFetchedDeletion(_ recordID: CKRecord.ID) {
        metadata.records[recordID.recordName] = nil
        syncEngine?.state.remove(pendingRecordZoneChanges: [
            .saveRecord(recordID),
            .deleteRecord(recordID)
        ])
    }

    private func emitMergedState() async {
        let state = mergedState()
        baseState = state
        await onStateChange(state)
    }

    private func persistMetadata() {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func publishStatus(_ status: CloudSyncStatus) async {
        await onStatusChange(status)
    }

    private static func isTemporary(_ code: CKError.Code) -> Bool {
        switch code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .accountTemporarilyUnavailable, .notAuthenticated:
            true
        default:
            false
        }
    }
}

extension CloudSyncCoordinator: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            metadata.stateSerialization = event.stateSerialization
            persistMetadata()

        case .accountChange(let event):
            switch event.changeType {
            case .signIn, .switchAccounts:
                for key in metadata.records.keys {
                    metadata.records[key]?.lastKnownRecordData = nil
                }
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                syncEngine.state.add(pendingRecordZoneChanges: metadata.records.keys.map { .saveRecord(recordID(for: $0)) })
                await publishStatus(.syncing)
            case .signOut:
                await publishStatus(.notSignedIn)
            @unknown default:
                await publishStatus(.unavailable)
            }

        case .fetchedDatabaseChanges(let event):
            if event.deletions.contains(where: { $0.zoneID == zoneID }) {
                metadata.records.removeAll()
                hasFetchedChangesToApply = true
            }

        case .fetchedRecordZoneChanges(let event):
            for modification in event.modifications {
                applyFetchedRecord(modification.record)
            }
            for deletion in event.deletions {
                applyFetchedDeletion(deletion.recordID)
            }
            if !event.modifications.isEmpty || !event.deletions.isEmpty {
                persistMetadata()
                hasFetchedChangesToApply = true
            }

        case .sentRecordZoneChanges(let event):
            var retries: [CKSyncEngine.PendingRecordZoneChange] = []
            var databaseRetries: [CKSyncEngine.PendingDatabaseChange] = []

            for record in event.savedRecords {
                if var tracked = metadata.records[record.recordID.recordName] {
                    tracked.remember(record)
                    metadata.records[record.recordID.recordName] = tracked
                }
            }

            for failure in event.failedRecordSaves {
                let record = failure.record
                switch failure.error.code {
                case .serverRecordChanged:
                    if let serverRecord = failure.error.serverRecord {
                        applyFetchedRecord(serverRecord)
                        retries.append(.saveRecord(record.recordID))
                        hasFetchedChangesToApply = true
                    }
                case .zoneNotFound:
                    metadata.records[record.recordID.recordName]?.lastKnownRecordData = nil
                    databaseRetries.append(.saveZone(CKRecordZone(zoneID: record.recordID.zoneID)))
                    retries.append(.saveRecord(record.recordID))
                case .unknownItem:
                    metadata.records[record.recordID.recordName]?.lastKnownRecordData = nil
                    retries.append(.saveRecord(record.recordID))
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .operationCancelled, .requestRateLimited,
                     .accountTemporarilyUnavailable:
                    await publishStatus(.offline)
                default:
                    await publishStatus(.unavailable)
                }
            }

            syncEngine.state.add(pendingDatabaseChanges: databaseRetries)
            syncEngine.state.add(pendingRecordZoneChanges: retries)
            persistMetadata()

        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            await publishStatus(.syncing)

        case .didFetchChanges:
            if hasFetchedChangesToApply {
                hasFetchedChangesToApply = false
                await emitMergedState()
            }
            await publishStatus(.upToDate)

        case .didSendChanges:
            if hasFetchedChangesToApply {
                hasFetchedChangesToApply = false
                await emitMergedState()
            }
            await publishStatus(.upToDate)

        case .sentDatabaseChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let records = metadata.records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let tracked = records[recordID.recordName] else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            let record = tracked.lastKnownRecord
                ?? CKRecord(recordType: Self.recordType, recordID: recordID)
            tracked.populate(record)
            return record
        }
    }
}

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

private struct CloudTrackedRecord: Codable, Equatable {
    var kind: CloudEntityKind
    var payload: Data
    var userModificationDate: Date
    var isDeleted: Bool
}

private struct CloudSyncMetadata: Codable {
    var records: [String: CloudTrackedRecord] = [:]
    var lastSeenRevision: UUID?
}

private struct CloudEnvelope: Codable {
    let schemaVersion: Int
    let revision: UUID
    let records: [String: CloudTrackedRecord]
}

private struct CloudPayload {
    let kind: CloudEntityKind
    let data: Data
}

/// Foundation has not declared `NSUbiquitousKeyValueStore` Sendable even
/// though its public API is thread-safe. Keep the unchecked boundary narrow.
private struct SendableUbiquitousStore: @unchecked Sendable {
    let value: NSUbiquitousKeyValueStore
}

/// Synchronises Listello's portable state through the user's private iCloud
/// key-value store. Calendar event identifiers deliberately remain local to
/// each device. Record-level timestamps and tombstones keep independent edits
/// and deletions deterministic when devices reconnect after being offline.
actor CloudSyncCoordinator {
    static let cloudKey = "Listello.Sync.Envelope.v1"
    static let maximumPayloadBytes = 900_000

    private let metadataURL: URL
    private let store: NSUbiquitousKeyValueStore
    private let onStateChange: @MainActor (ListelloState) -> Void
    private let onStatusChange: @MainActor (CloudSyncStatus) -> Void
    private let initialUserModificationDate: Date
    private var metadata: CloudSyncMetadata
    private var baseState: ListelloState
    private var didCaptureInitialState = false
    private var notificationTask: Task<Void, Never>?

    init(
        metadataURL: URL,
        initialState: ListelloState,
        initialUserModificationDate: Date,
        store: NSUbiquitousKeyValueStore = .default,
        onStateChange: @escaping @MainActor (ListelloState) -> Void,
        onStatusChange: @escaping @MainActor (CloudSyncStatus) -> Void
    ) {
        self.metadataURL = metadataURL
        self.baseState = initialState
        self.initialUserModificationDate = initialUserModificationDate
        self.store = store
        self.onStateChange = onStateChange
        self.onStatusChange = onStatusChange
        if let data = try? Data(contentsOf: metadataURL),
           let saved = try? JSONDecoder().decode(CloudSyncMetadata.self, from: data) {
            metadata = saved
        } else {
            metadata = CloudSyncMetadata()
        }

        Task { await start() }
    }

    deinit {
        notificationTask?.cancel()
    }

    func capture(_ state: ListelloState) async {
        baseState = state
        let payloads = makePayloads(from: state)
        let isFirstCapture = !didCaptureInitialState
        didCaptureInitialState = true

        // A new installation first downloads any existing library instead of
        // uploading default preferences over the person's real settings.
        if isFirstCapture, metadata.records.isEmpty, !hasUserContent(state) {
            return
        }

        let now = isFirstCapture ? initialUserModificationDate : Date()
        var changed = false

        for (recordName, payload) in payloads {
            if let existing = metadata.records[recordName],
               !existing.isDeleted,
               existing.kind == payload.kind,
               existing.payload == payload.data {
                continue
            }
            metadata.records[recordName] = CloudTrackedRecord(
                kind: payload.kind,
                payload: payload.data,
                userModificationDate: now,
                isDeleted: false
            )
            changed = true
        }

        let liveNames = Set(payloads.keys)
        for (recordName, existing) in metadata.records where !existing.isDeleted && !liveNames.contains(recordName) {
            metadata.records[recordName] = CloudTrackedRecord(
                kind: existing.kind,
                payload: Data(),
                userModificationDate: now,
                isDeleted: true
            )
            changed = true
        }

        guard changed else { return }
        persistMetadata()
        await writeSnapshot()
    }

    func syncNow() async {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            await publishStatus(.notSignedIn)
            return
        }
        await publishStatus(.syncing)
        guard store.synchronize() else {
            await publishStatus(.offline)
            return
        }
        let localWon = await mergeRemoteSnapshot()
        if localWon {
            await writeSnapshot()
        } else {
            await publishStatus(.upToDate)
        }
    }

    private func start() async {
        await publishStatus(.starting)
        guard FileManager.default.ubiquityIdentityToken != nil else {
            await publishStatus(.notSignedIn)
            return
        }

        if metadata.records.isEmpty, hasUserContent(baseState) {
            seedMetadata(from: baseState, date: initialUserModificationDate)
        }

        _ = store.synchronize()
        let localWon = await mergeRemoteSnapshot()
        if localWon || store.data(forKey: Self.cloudKey) == nil {
            await writeSnapshot()
        } else {
            await publishStatus(.upToDate)
        }

        let notificationStore = SendableUbiquitousStore(value: store)
        notificationTask = Task { [weak self, notificationStore] in
            for await notification in NotificationCenter.default.notifications(
                named: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: notificationStore.value
            ) {
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                await self?.receivedExternalChange(reason: reason)
            }
        }
    }

    private func receivedExternalChange(reason: Int?) async {
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            await publishStatus(.unavailable)
            return
        }
        await publishStatus(.syncing)
        let localWon = await mergeRemoteSnapshot()
        if localWon {
            await writeSnapshot()
        } else {
            await publishStatus(.upToDate)
        }
    }

    /// Returns true when the local merged library contains records newer than
    /// the downloaded envelope and should be written back to iCloud.
    private func mergeRemoteSnapshot() async -> Bool {
        guard let data = store.data(forKey: Self.cloudKey),
              let remote = try? JSONDecoder().decode(CloudEnvelope.self, from: data),
              remote.schemaVersion == 1
        else { return !metadata.records.isEmpty }

        if metadata.lastSeenRevision == remote.revision {
            return false
        }

        var changedLocally = false
        var localWon = false
        let names = Set(metadata.records.keys).union(remote.records.keys)
        for name in names {
            switch (metadata.records[name], remote.records[name]) {
            case (.none, .some(let remoteRecord)):
                metadata.records[name] = remoteRecord
                changedLocally = true
            case (.some, .none):
                localWon = true
            case (.some(let localRecord), .some(let remoteRecord)):
                if remoteRecord.userModificationDate > localRecord.userModificationDate {
                    metadata.records[name] = remoteRecord
                    changedLocally = true
                } else if localRecord.userModificationDate > remoteRecord.userModificationDate {
                    localWon = true
                } else if localRecord != remoteRecord {
                    // A stable bytewise tie-break handles the extremely rare
                    // case where two devices save during the same clock tick.
                    if remoteRecord.payload.lexicographicallyPrecedes(localRecord.payload) {
                        localWon = true
                    } else {
                        metadata.records[name] = remoteRecord
                        changedLocally = true
                    }
                }
            case (.none, .none):
                break
            }
        }

        metadata.lastSeenRevision = remote.revision
        persistMetadata()
        if changedLocally {
            await emitMergedState()
        }
        return localWon
    }

    private func writeSnapshot() async {
        let revision = UUID()
        let envelope = CloudEnvelope(schemaVersion: 1, revision: revision, records: metadata.records)
        guard let data = try? JSONEncoder().encode(envelope), data.count <= Self.maximumPayloadBytes else {
            await publishStatus(.unavailable)
            return
        }
        metadata.lastSeenRevision = revision
        persistMetadata()
        store.set(data, forKey: Self.cloudKey)
        await publishStatus(store.synchronize() ? .upToDate : .offline)
    }

    private func seedMetadata(from state: ListelloState, date: Date) {
        for (name, payload) in makePayloads(from: state) {
            metadata.records[name] = CloudTrackedRecord(
                kind: payload.kind,
                payload: payload.data,
                userModificationDate: date,
                isDeleted: false
            )
        }
        persistMetadata()
    }

    private func makePayloads(from state: ListelloState) -> [String: CloudPayload] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var payloads: [String: CloudPayload] = [:]

        for var task in state.tasks {
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

        for tracked in metadata.records.values where !tracked.isDeleted {
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
}

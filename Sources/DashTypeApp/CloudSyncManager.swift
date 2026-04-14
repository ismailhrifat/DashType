import Combine
import FirebaseCore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
import Foundation
#if canImport(DashTypeCore)
import DashTypeCore
#endif

@MainActor
final class CloudSyncManager: ObservableObject {
    enum AuthFlowMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"

        var id: String { rawValue }

        var actionTitle: String {
            switch self {
            case .signIn:
                return "Sign In"
            case .signUp:
                return "Create Account"
            }
        }
    }

    @Published private(set) var isSyncEnabled: Bool
    @Published private(set) var signedInEmail: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isSyncing = false
    @Published var isPresentingAuthSheet = false
    @Published var authFlowMode: AuthFlowMode = .signIn
    @Published var authErrorMessage: String?
    @Published var syncErrorMessage: String?

    private let store: SnippetStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var auth: Auth?
    private var firestore: Firestore?
    private var authListenerHandle: AuthStateDidChangeListenerHandle?
    private var initialMergeListener: ListenerRegistration?
    private var storeChangeCancellable: AnyCancellable?
    private var isApplyingRemoteSnapshot = false
    private var hasActivated = false
    private var needsInitialMerge = false
    private var lastSyncedPayload: String?
    private var activeUserID: String?

    init(store: SnippetStore) {
        self.store = store
        self.isSyncEnabled = UserDefaults.standard.object(forKey: AppPreferences.syncWithCloudKey) as? Bool ?? false
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var isAuthenticated: Bool {
        signedInEmail != nil
    }

    var syncDescription: String {
        if let signedInEmail {
            if isSyncEnabled {
                return "Signed in as \(signedInEmail). Snippets sync automatically whenever they change."
            }

            return "Signed in as \(signedInEmail). Turn this on to keep your snippets synced with Firebase."
        }

        return "Sign in or create an account to back up and sync snippets across your devices."
    }

    func activateIfNeeded() {
        guard !hasActivated else {
            return
        }

        guard FirebaseApp.app() != nil else {
            return
        }

        hasActivated = true
        auth = Auth.auth()
        firestore = Firestore.firestore()
        signedInEmail = auth?.currentUser?.email

        observeStoreChanges()
        observeAuthState()

        if isSyncEnabled, let currentUser = auth?.currentUser {
            prepareUploadSession(for: currentUser)
        }
    }

    func setSyncEnabled(_ enabled: Bool) {
        if enabled {
            requestEnableSync()
        } else {
            persistSyncEnabled(false)
            syncErrorMessage = nil
            stopCloudSync()
            lastSyncedPayload = nil
        }
    }

    func dismissAuthSheet() {
        isPresentingAuthSheet = false
        authErrorMessage = nil
    }

    func clearAuthError() {
        authErrorMessage = nil
    }

    func signOut() {
        guard let auth else {
            return
        }

        do {
            persistSyncEnabled(false)
            stopCloudSync()
            lastSyncedPayload = nil
            signedInEmail = nil
            syncErrorMessage = nil
            authErrorMessage = nil
            try auth.signOut()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) {
        guard let auth else {
            authErrorMessage = "Cloud sync is not ready yet. Reopen Settings and try again."
            return
        }

        isAuthenticating = true
        authErrorMessage = nil

        auth.signIn(withEmail: email, password: password) { [weak self] result, error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isAuthenticating = false

                if let error {
                    self.authErrorMessage = error.localizedDescription
                    return
                }

                self.signedInEmail = result?.user.email
                self.isPresentingAuthSheet = false
                if let user = result?.user {
                    self.enableSyncWithInitialMerge(for: user)
                }
            }
        }
    }

    func signUp(email: String, password: String) {
        guard let auth else {
            authErrorMessage = "Cloud sync is not ready yet. Reopen Settings and try again."
            return
        }

        isAuthenticating = true
        authErrorMessage = nil

        auth.createUser(withEmail: email, password: password) { [weak self] result, error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isAuthenticating = false

                if let error {
                    self.authErrorMessage = error.localizedDescription
                    return
                }

                self.signedInEmail = result?.user.email
                self.isPresentingAuthSheet = false
                if let user = result?.user {
                    self.enableSyncWithInitialMerge(for: user)
                }
            }
        }
    }

    private func requestEnableSync() {
        activateIfNeeded()
        syncErrorMessage = nil

        guard let currentUser = auth?.currentUser else {
            authFlowMode = .signIn
            authErrorMessage = nil
            isPresentingAuthSheet = true
            return
        }

        enableSyncWithInitialMerge(for: currentUser)
    }

    private func observeStoreChanges() {
        storeChangeCancellable = store.$folders
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    if self.needsInitialMerge {
                        return
                    }

                    self.pushLocalChangesIfNeeded()
                }
            }
    }

    private func observeAuthState() {
        guard let auth else {
            return
        }

        authListenerHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.handleAuthStateChanged(user)
            }
        }
    }

    private func handleAuthStateChanged(_ user: User?) {
        signedInEmail = user?.email

        guard let user else {
            stopCloudSync()
            lastSyncedPayload = nil

            if isSyncEnabled {
                persistSyncEnabled(false)
                syncErrorMessage = "Sign in again to continue syncing with the cloud."
            }
            return
        }

        if isSyncEnabled {
            prepareUploadSession(for: user)
        }
    }

    private func enableSyncWithInitialMerge(for user: User) {
        persistSyncEnabled(true)
        prepareUploadSession(for: user)
        needsInitialMerge = true
        startInitialMerge(for: user)
    }

    private func prepareUploadSession(for user: User) {
        signedInEmail = user.email
        syncErrorMessage = nil

        if activeUserID != user.uid {
            activeUserID = user.uid
            lastSyncedPayload = nil
        }
    }

    private func startInitialMerge(for user: User) {
        guard isSyncEnabled, needsInitialMerge else {
            return
        }

        guard let documentReference = cloudDocumentReference(for: user.uid),
              initialMergeListener == nil else {
            return
        }

        isSyncing = true
        syncErrorMessage = nil

        initialMergeListener = documentReference.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                self?.handleInitialMergeSnapshot(snapshot, error: error, documentReference: documentReference, user: user)
            }
        }
    }

    private func stopCloudSync() {
        initialMergeListener?.remove()
        initialMergeListener = nil
        activeUserID = nil
        needsInitialMerge = false
        isSyncing = false
    }

    private func handleInitialMergeSnapshot(
        _ snapshot: DocumentSnapshot?,
        error: Error?,
        documentReference: DocumentReference,
        user: User
    ) {
        if let error {
            syncErrorMessage = error.localizedDescription
            return
        }

        guard let snapshot else {
            return
        }

        guard !snapshot.metadata.isFromCache else {
            syncErrorMessage = "Waiting to reach Firebase before merging your snippets."
            return
        }

        initialMergeListener?.remove()
        initialMergeListener = nil
        syncErrorMessage = nil

        let remoteFolders: [SnippetFolder]
        if snapshot.exists, let remotePayload = snapshot.get("foldersJSON") as? String, !remotePayload.isEmpty {
            do {
                remoteFolders = try decodeFolders(from: remotePayload)
            } catch {
                isSyncing = false
                syncErrorMessage = "Cloud data could not be read."
                return
            }
        } else {
            remoteFolders = []
        }

        let mergedFolders = mergeFolders(local: store.folders, remote: remoteFolders)

        do {
            let mergedPayload = try payload(for: mergedFolders)
            lastSyncedPayload = mergedPayload

            if mergedFolders != store.folders {
                isApplyingRemoteSnapshot = true
                store.replaceAll(with: mergedFolders)
                isApplyingRemoteSnapshot = false
            }

            needsInitialMerge = false
            uploadPayload(
                mergedPayload,
                to: documentReference,
                userEmail: user.email ?? ""
            )
        } catch {
            isApplyingRemoteSnapshot = false
            isSyncing = false
            syncErrorMessage = "Local data could not be prepared for cloud sync."
        }
    }

    private func pushLocalChangesIfNeeded(force: Bool = false) {
        guard isSyncEnabled,
              !needsInitialMerge,
              !isApplyingRemoteSnapshot,
              let currentUser = auth?.currentUser,
              let documentReference = cloudDocumentReference(for: currentUser.uid) else {
            return
        }

        do {
            let payload = try currentPayload()
            guard force || payload != lastSyncedPayload else {
                return
            }

            uploadPayload(
                payload,
                to: documentReference,
                userEmail: currentUser.email ?? ""
            )
        } catch {
            syncErrorMessage = "Local data could not be prepared for cloud sync."
        }
    }

    private func uploadPayload(_ payload: String, to documentReference: DocumentReference, userEmail: String) {
        isSyncing = true
        lastSyncedPayload = payload

        let data: [String: Any] = [
            "foldersJSON": payload,
            "schemaVersion": 1,
            "updatedAt": Timestamp(date: Date()),
            "userEmail": userEmail,
        ]

        documentReference.setData(data, merge: true) { [weak self] error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isSyncing = false

                if let error {
                    self.syncErrorMessage = error.localizedDescription
                    if self.lastSyncedPayload == payload {
                        self.lastSyncedPayload = nil
                    }
                } else {
                    self.syncErrorMessage = nil
                }
            }
        }
    }

    private func cloudDocumentReference(for uid: String) -> DocumentReference? {
        firestore?
            .collection("users")
            .document(uid)
            .collection("sync")
            .document("snippetStore")
    }

    private func persistSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppPreferences.syncWithCloudKey)
    }

    private func currentPayload() throws -> String {
        let data = try encoder.encode(store.folders)
        return String(decoding: data, as: UTF8.self)
    }

    private func payload(for folders: [SnippetFolder]) throws -> String {
        let data = try encoder.encode(folders)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeFolders(from payload: String) throws -> [SnippetFolder] {
        try decoder.decode([SnippetFolder].self, from: Data(payload.utf8))
    }

    private func mergeFolders(local: [SnippetFolder], remote: [SnippetFolder]) -> [SnippetFolder] {
        struct MergeSelection {
            var snippet: Snippet
            var folderKey: String
            var sourcePriority: Int
        }

        var buckets: [String: SnippetFolder] = [:]
        var bucketOrder: [String] = []
        var selections: [String: MergeSelection] = [:]

        func folderKey(for folder: SnippetFolder) -> String {
            let normalizedName = folder.normalizedName
            if normalizedName.isEmpty {
                return "id:\(folder.id.uuidString)"
            }

            return "name:\(normalizedName.lowercased())"
        }

        func snippetKey(for snippet: Snippet) -> String {
            let normalizedTrigger = snippet.normalizedTrigger
            if normalizedTrigger.isEmpty {
                return "id:\(snippet.id.uuidString)"
            }

            return "trigger:\(normalizedTrigger)"
        }

        func mergeFolderMetadata(_ existing: SnippetFolder, with incoming: SnippetFolder) -> SnippetFolder {
            var merged = existing

            if merged.normalizedName.isEmpty, !incoming.normalizedName.isEmpty {
                merged.name = incoming.name
            }

            merged.isEnabled = merged.isEnabled || incoming.isEnabled
            merged.createdAt = min(merged.createdAt, incoming.createdAt)
            merged.updatedAt = max(merged.updatedAt, incoming.updatedAt)
            return merged
        }

        func mergedSnippet(preferred: Snippet, fallback: Snippet) -> Snippet {
            var merged = preferred

            if merged.richTextData == nil,
               merged.content == fallback.content,
               let richTextData = fallback.richTextData {
                merged.richTextData = richTextData
            }

            if merged.normalizedTitle.isEmpty, !fallback.normalizedTitle.isEmpty {
                merged.title = fallback.title
            }

            if merged.content.isEmpty, !fallback.content.isEmpty {
                merged.content = fallback.content
            }

            merged.createdAt = min(merged.createdAt, fallback.createdAt)
            return merged
        }

        func shouldPrefer(_ candidate: MergeSelection, over existing: MergeSelection) -> Bool {
            if candidate.snippet.updatedAt != existing.snippet.updatedAt {
                return candidate.snippet.updatedAt > existing.snippet.updatedAt
            }

            return candidate.sourcePriority < existing.sourcePriority
        }

        func register(folder: SnippetFolder, sourcePriority: Int) {
            let bucketKey = folderKey(for: folder)

            if let existingBucket = buckets[bucketKey] {
                buckets[bucketKey] = mergeFolderMetadata(existingBucket, with: folder)
            } else {
                var bucket = folder
                bucket.snippets = []
                buckets[bucketKey] = bucket
                bucketOrder.append(bucketKey)
            }

            for snippet in folder.snippets {
                let selectionKey = snippetKey(for: snippet)
                let candidate = MergeSelection(
                    snippet: snippet,
                    folderKey: bucketKey,
                    sourcePriority: sourcePriority
                )

                if let existing = selections[selectionKey] {
                    if shouldPrefer(candidate, over: existing) {
                        selections[selectionKey] = MergeSelection(
                            snippet: mergedSnippet(preferred: candidate.snippet, fallback: existing.snippet),
                            folderKey: candidate.folderKey,
                            sourcePriority: candidate.sourcePriority
                        )
                    } else {
                        selections[selectionKey] = MergeSelection(
                            snippet: mergedSnippet(preferred: existing.snippet, fallback: candidate.snippet),
                            folderKey: existing.folderKey,
                            sourcePriority: existing.sourcePriority
                        )
                    }
                } else {
                    selections[selectionKey] = candidate
                }
            }
        }

        local.forEach { register(folder: $0, sourcePriority: 0) }
        remote.forEach { register(folder: $0, sourcePriority: 1) }

        for selection in selections.values {
            guard var bucket = buckets[selection.folderKey] else {
                continue
            }

            bucket.snippets.append(selection.snippet)
            bucket.updatedAt = max(bucket.updatedAt, selection.snippet.updatedAt)
            buckets[selection.folderKey] = bucket
        }

        return bucketOrder.compactMap { key in
            guard var folder = buckets[key] else {
                return nil
            }

            folder.snippets.sort { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
            return folder
        }
    }
}

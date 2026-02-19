import Contacts
import Foundation

final class ContactsManager: @unchecked Sendable {
    static let shared = ContactsManager()

    private let accessQueue = DispatchQueue(label: "com.conductor.contacts")
    private let store = CNContactStore()

    private init() {}

    enum AuthorizationStatus {
        case notDetermined, restricted, denied, authorized
    }

    struct ContactMatch: Codable {
        let fullName: String
        let email: String
    }

    func contactsAuthorizationStatus() -> AuthorizationStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized, .limited: return .authorized
        @unknown default: return .denied
        }
    }

    func requestContactsAccess() async -> Bool {
        guard RuntimeEnvironment.supportsTCCPrompts else {
            Log.app.info("Contacts access request skipped (not in .app bundle)")
            return false
        }

        return await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func findContact(named query: String) async throws -> ContactMatch {
        let matches = try await findContacts(named: query, limit: 1)
        guard let first = matches.first else {
            throw ContactLookupError.notFound
        }
        return first
    }

    func findContacts(named query: String, limit: Int = 5) async throws -> [ContactMatch] {
        guard contactsAuthorizationStatus() == .authorized else {
            throw ContactLookupError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            accessQueue.async {
                do {
                    let keys: [CNKeyDescriptor] = [
                        CNContactGivenNameKey as CNKeyDescriptor,
                        CNContactFamilyNameKey as CNKeyDescriptor,
                        CNContactEmailAddressesKey as CNKeyDescriptor
                    ]
                    let predicate = CNContact.predicateForContacts(matchingName: query)
                    let contacts = try self.store.unifiedContacts(matching: predicate, keysToFetch: keys)

                    let normalizedQuery = query
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()

                    var matches: [ContactMatch] = []
                    for contact in contacts {
                        let name = CNContactFormatter.string(from: contact, style: .fullName)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !name.isEmpty else { continue }

                        for address in contact.emailAddresses {
                            let email = String(address.value)
                            guard !email.isEmpty else { continue }
                            matches.append(ContactMatch(fullName: name, email: email))
                        }
                    }

                    let ranked = matches
                        .sorted { lhs, rhs in
                            self.rank(lhs, normalizedQuery: normalizedQuery) > self.rank(rhs, normalizedQuery: normalizedQuery)
                        }
                    continuation.resume(returning: Array(ranked.prefix(max(limit, 1))))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func rank(_ match: ContactMatch, normalizedQuery: String) -> Int {
        let normalizedName = match.fullName.lowercased()
        if normalizedName == normalizedQuery { return 3 }
        if normalizedName.hasPrefix(normalizedQuery) { return 2 }
        if normalizedName.contains(normalizedQuery) { return 1 }
        return 0
    }
}

enum ContactLookupError: LocalizedError {
    case notAuthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Contacts access is not authorized"
        case .notFound:
            return "No contact with an email was found"
        }
    }
}

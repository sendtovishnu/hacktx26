import Contacts

// Reads names, phone numbers and emails from the phone's contacts, after the person allows it.
// Only the numbers and emails are sent, to find who is on Twin; the server doesn't keep them.

enum ContactsReader {
    struct Contact {
        let name: String
        let phones: [String]
        let emails: [String]
    }

    static func read() async throws -> [Contact] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            throw APIError.notConfigured("CloseMates can't see your contacts. Allow it in Settings > CloseMates > Contacts.")
        }
        // Enumerating is synchronous and can take a moment on big address books.
        return try await Task.detached(priority: .userInitiated) {
            let keys = [
                CNContactGivenNameKey, CNContactFamilyNameKey,
                CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            ] as [CNKeyDescriptor]
            var contacts: [Contact] = []
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                let phones = contact.phoneNumbers.map(\.value.stringValue)
                let emails = contact.emailAddresses.map { String($0.value) }
                guard !phones.isEmpty || !emails.isEmpty else { return }
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                contacts.append(Contact(name: name, phones: phones, emails: emails))
            }
            return contacts
        }.value
    }

    /// Same rule as the server: the last 10 digits, so formatting and country codes don't matter.
    static func phoneKey(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.count >= 7 ? String(digits.suffix(10)) : nil
    }
}

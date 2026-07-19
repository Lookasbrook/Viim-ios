import Foundation

/// Normalisation E.164 des numeros de telephone. Historiquement centre sur
/// le Burkina Faso (un numero local de 8 chiffres devient +226XXXXXXXX),
/// le format accepte desormais tout numero international explicite
/// (prefixe + ou 00) pour les utilisateurs et contacts hors Burkina.
enum BurkinaPhoneNumber {
    private static let internationalDigitRange = 8...15

    static func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.compactMap(\.wholeNumberValue).map(String.init).joined()

        // Formats historiques burkinabe : 8 chiffres locaux, 226XXXXXXXX,
        // ou 00226XXXXXXXX.
        if digits.count == 8, !trimmed.hasPrefix("+") {
            return "+226\(digits)"
        }
        if digits.count == 11, digits.hasPrefix("226") {
            return "+\(digits)"
        }
        if digits.count == 13, digits.hasPrefix("00226") {
            return "+\(digits.dropFirst(2))"
        }

        // Numero international explicite : +<indicatif><numero> ou 00...
        if trimmed.hasPrefix("+"),
           isPlausibleInternationalNumber(digits) {
            return "+\(digits)"
        }
        if digits.hasPrefix("00") {
            let remainder = String(digits.dropFirst(2))
            if isPlausibleInternationalNumber(remainder) {
                return "+\(remainder)"
            }
        }

        return nil
    }

    private static func isPlausibleInternationalNumber(_ digits: String) -> Bool {
        guard internationalDigitRange.contains(digits.count), digits.first != "0" else {
            return false
        }
        // Un numero commencant par l'indicatif burkinabe doit porter ses
        // 8 chiffres locaux exacts : cela intercepte les fautes de frappe.
        if digits.hasPrefix("226") {
            return digits.count == 11
        }
        return true
    }

    static func normalizedContact(_ contact: EmergencyContact) -> EmergencyContact? {
        guard let phoneNumber = normalize(contact.phoneNumber) else {
            return nil
        }

        let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }

        return EmergencyContact(name: name, phoneNumber: phoneNumber)
    }
}

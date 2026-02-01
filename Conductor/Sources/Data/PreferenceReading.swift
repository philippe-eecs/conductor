import Foundation

protocol PreferenceReading {
    func preferenceValue(for key: String) -> String?
}

extension Database: PreferenceReading {
    func preferenceValue(for key: String) -> String? {
        (try? getPreference(key: key)) ?? nil
    }
}


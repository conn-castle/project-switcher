import Foundation
import TOMLDecoder

extension ConfigParser {
    // MARK: - Validation Helpers

    static func isValidColorHex(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else {
            return false
        }
        let hexDigits = value.dropFirst()
        return hexDigits.allSatisfy { char in
            switch char {
            case "0"..."9", "a"..."f", "A"..."F":
                return true
            default:
                return false
            }
        }
    }

    /// Reads a required non-empty string value or records a failure.
    static func readNonEmptyString(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> String? {
        if !table.contains(key: key) {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) is missing",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        guard let value = try? table.string(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be a string",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) is empty",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        return trimmed
    }

    /// Reads an optional non-empty string value. Returns nil when key is absent.
    /// Records a failure if the value is present but not a string or empty.
    static func readOptionalNonEmptyString(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> String? {
        guard table.contains(key: key) else {
            return nil
        }

        guard let value = try? table.string(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be a string",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) is empty",
                fix: "Set \(label) to a non-empty string."
            ))
            return nil
        }

        return trimmed
    }

    /// Reads an optional string array value. Returns empty array when key is absent.
    /// Records a failure if any element is not a string.
    static func readOptionalStringArray(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> [String] {
        guard table.contains(key: key) else {
            return []
        }

        guard let array = try? table.array(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be an array of strings",
                fix: "Set \(label) to an array of strings, e.g. [\"https://example.com\"]."
            ))
            return []
        }

        var result: [String] = []
        for i in 0..<array.count {
            guard let value = try? array.string(atIndex: i) else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "\(label)[\(i)] must be a string",
                    fix: "Ensure all elements in \(label) are strings."
                ))
                continue
            }
            result.append(value)
        }
        return result
    }

    /// Reads an optional boolean value. Returns default when key is absent.
    static func readOptionalBool(
        from table: TOMLTable,
        key: String,
        defaultValue: Bool,
        label: String,
        findings: inout [ConfigFinding]
    ) -> Bool {
        guard table.contains(key: key) else {
            return defaultValue
        }

        guard let value = try? table.bool(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be a boolean",
                fix: "Set \(label) to true or false."
            ))
            return defaultValue
        }

        return value
    }

    /// Reads an optional numeric value as Double. Accepts both TOML integers and floats.
    /// Returns nil when the key is absent. Records a failure if the value is not a number.
    static func readOptionalNumber(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> Double? {
        guard table.contains(key: key) else {
            return nil
        }

        // Try integer first (TOML 24 is integer, 24.0 is float)
        if let intValue = try? table.integer(forKey: key) {
            return Double(intValue)
        }

        if let floatValue = try? table.float(forKey: key) {
            return floatValue
        }

        findings.append(ConfigFinding(
            severity: .fail,
            title: "\(label) must be a number",
            fix: "Set \(label) to a numeric value."
        ))
        return nil
    }

    /// Reads an optional integer value as Int64. Accepts only TOML integers (not floats).
    /// Returns nil when the key is absent. Records a failure if the value is not an integer.
    static func readOptionalInteger(
        from table: TOMLTable,
        key: String,
        label: String,
        findings: inout [ConfigFinding]
    ) -> Int64? {
        guard table.contains(key: key) else {
            return nil
        }

        guard let value = try? table.integer(forKey: key) else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "\(label) must be an integer",
                fix: "Set \(label) to a whole number."
            ))
            return nil
        }

        return value
    }

    /// Validates that all URLs in the array start with http:// or https://.
    /// Returns true if all valid, false if any invalid (adds findings for invalids).
    @discardableResult
    static func validateURLs(
        _ urls: [String],
        label: String,
        findings: inout [ConfigFinding]
    ) -> Bool {
        var allValid = true
        for (index, url) in urls.enumerated() {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "\(label)[\(index)] is not a valid URL",
                    detail: "Got \"\(trimmed)\". URLs must start with http:// or https://.",
                    fix: "Use a full URL starting with http:// or https://."
                ))
                allValid = false
            }
        }
        return allValid
    }
}

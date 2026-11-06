import Foundation
import Security
import CryptoKit

/// Use macOS's actual designated requirement, never just a bundle ID or version.
enum CodeIdentity {
    static func requirement(for app: URL) throws -> Data {
        let code = try staticCode(app)
        var requirement: SecRequirement?
        try check(SecCodeCopyDesignatedRequirement(code, [], &requirement))
        guard let requirement else { throw IdentityError() }
        var data: CFData?
        try check(SecRequirementCopyData(requirement, [], &data))
        guard let data else { throw IdentityError() }
        return data as Data
    }

    static func satisfies(_ requirementData: Data, app: URL) -> Bool {
        guard let code = try? staticCode(app) else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithData(requirementData as CFData, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
    }

    static func validateRelease(_ app: URL, certificate: URL, identifier: String) throws {
        let digest = Insecure.SHA1.hash(data: try Data(contentsOf: certificate)).map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        let expression = "identifier \"\(identifier)\" and certificate root = H\"\(digest)\""
        try check(SecRequirementCreateWithString(expression as CFString, [], &requirement))
        guard let requirement else { throw IdentityError() }
        try check(SecStaticCodeCheckValidity(try staticCode(app), SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), requirement))
    }

    static func validate(_ app: URL) throws {
        try check(SecStaticCodeCheckValidity(try staticCode(app), SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil))
    }

    private static func staticCode(_ app: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        try check(SecStaticCodeCreateWithPath(app as CFURL, [], &code))
        guard let code else { throw IdentityError() }
        return code
    }
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw IdentityError() }
    }
    private struct IdentityError: LocalizedError {
        var errorDescription: String? { "OpenLocker's signature could not be verified. Download a fresh installer." }
    }
}

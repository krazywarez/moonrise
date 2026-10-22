import CryptoKit
import DeviceCheck
import Foundation

/// App Attest for device registration: a key attested once with the backend, then an assertion over each
/// registration body. Nil where App Attest is unsupported (the Simulator) or fails; the backend accepts unsigned
/// registrations unless it is set to require them.
@MainActor
enum AppAttest {
    private static let keyIDKey = "appAttestKeyID"

    /// Adds a fresh challenge to `body`, then returns the serialized body and the assertion headers for it.
    static func sign(_ body: [String: Any], base: URL) async -> (Data, [String: String])? {
        let service = DCAppAttestService.shared
        guard service.isSupported, let keyID = await attestedKey(base: base), let challenge = await challenge(base: base) else { return nil }
        var body = body
        body["challenge"] = challenge
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        do {
            let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: data)))
            return (data, ["x-app-attest-key": keyID, "x-app-attest-assertion": assertion.base64EncodedString()])
        } catch let error as DCError where error.code == .invalidKey {
            UserDefaults.standard.removeObject(forKey: keyIDKey)
            return nil
        } catch {
            return nil
        }
    }

    /// The stored key, or a new one attested with the backend.
    private static func attestedKey(base: URL) async -> String? {
        if let id = UserDefaults.standard.string(forKey: keyIDKey) { return id }
        let service = DCAppAttestService.shared
        guard let id = try? await service.generateKey(), let challenge = await challenge(base: base), let bytes = Data(base64Encoded: challenge),
              let attestation = try? await service.attestKey(id, clientDataHash: Data(SHA256.hash(data: bytes))) else { return nil }
        var req = URLRequest(url: base.appending(path: "v1/attest"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["keyId": id, "attestation": attestation.base64EncodedString(), "challenge": challenge])
        guard let (_, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        UserDefaults.standard.set(id, forKey: keyIDKey)
        return id
    }

    private static func challenge(base: URL) async -> String? {
        var req = URLRequest(url: base.appending(path: "v1/challenge"))
        req.httpMethod = "POST"
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["challenge"] as? String
    }
}

import Foundation

public struct UserDefaultsClient: DependencyClient {
    var string: @Sendable (String) -> String?
    var setString: @Sendable (String?, String) -> Void
    var data: @Sendable (String) -> Data?
    var setData: @Sendable (Data?, String) -> Void
    var double: @Sendable (String) -> Double?
    var setDouble: @Sendable (Double?, String) -> Void
    var removePersistentDomain: @Sendable (String) -> Void
    var persistentDomain: @Sendable (String) -> [String : Any]?

    public static let liveValue = Self(
        string: { UserDefaults.standard.string(forKey: $0) },
        setString: { UserDefaults.standard.set($0, forKey: $1) },
        data: { UserDefaults.standard.data(forKey: $0) },
        setData: { UserDefaults.standard.set($0, forKey: $1) },
        double: { key in
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.double(forKey: key)
        },
        setDouble: { value, key in
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        },
        removePersistentDomain: { UserDefaults.standard.removePersistentDomain(forName: $0) },
        persistentDomain: { UserDefaults.standard.persistentDomain(forName: $0) }
    )

    public static let testValue = Self(
        string: { _ in nil },
        setString: { _, _ in },
        data: { _ in nil },
        setData: { _, _ in },
        double: { _ in nil },
        setDouble: { _, _ in },
        removePersistentDomain: { _ in },
        persistentDomain: { _ in nil }
    )
}

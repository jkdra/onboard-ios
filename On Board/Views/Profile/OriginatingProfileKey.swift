import SwiftUI

struct OriginatingProfileKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var originatingProfileID: UUID? {
        get { self[OriginatingProfileKey.self] }
        set { self[OriginatingProfileKey.self] = newValue }
    }
}

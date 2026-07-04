import Foundation
let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase
struct Params: Encodable {
    let pDisplayName: String
    let pHandle: String
    let pBio: String?
    let pAvatarUrl: String?
}
let data = try! encoder.encode(Params(pDisplayName: "Jawad K.", pHandle: "jawadalkhadra", pBio: "bio", pAvatarUrl: nil))
print(String(data: data, encoding: .utf8)!)

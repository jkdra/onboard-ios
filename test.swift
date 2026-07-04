import Foundation
struct Test: Decodable {
    let authorId: String
    enum CodingKeys: String, CodingKey {
        case authorId = "author_id"
    }
}
let json = """
{"author_id": "123"}
""".data(using: .utf8)!
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
do {
    let t = try decoder.decode(Test.self, from: json)
    print("Success: \(t.authorId)")
} catch {
    print("Error: \(error)")
}

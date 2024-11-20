import Foundation
import SwiftJWT

struct VideoGrant: Codable {
    let room: String
    let roomJoin: Bool
    let canPublish: Bool
    let canPublishData: Bool
    let canSubscribe: Bool
    
    init(room: String) {
        self.room = room
        self.roomJoin = true
        self.canPublish = true
        self.canPublishData = true
        self.canSubscribe = true
    }
}

struct TokenClaims: Claims {
    let exp: Date
    let iss: String
    let sub: String
    let jti: String
    let video: VideoGrant
}

class JWTHelper {
    static func createToken(apiKey: String, apiSecret: String, identity: String, roomName: String) throws -> String {
        let header = Header(typ: "JWT")
        
        let claims = TokenClaims(
            exp: Date().addingTimeInterval(15 * 60), // 15 minutes
            iss: apiKey,
            sub: identity,
            jti: UUID().uuidString,
            video: VideoGrant(room: roomName)
        )
        
        var jwt = JWT(header: header, claims: claims)
        let key = Data(apiSecret.utf8)
        
        return try jwt.sign(using: .hs256(key: key))
    }
} 
import Foundation
import SwiftUI

struct ConnectionDetails {
    let serverUrl: String
    let roomName: String
    let participantName: String
    let participantToken: String
}

class RoomConnectionManager: ObservableObject {
    @Published var connectionDetails: ConnectionDetails?
    @Published var isConnected = false
    
    private let apiKey: String
    private let apiSecret: String
    private let liveKitUrl: String
    
    init() {
        // Load from environment or configuration
        self.apiKey = ProcessInfo.processInfo.environment["LIVEKIT_API_KEY"] ?? "APIDp5EWoHomgk9"
        self.apiSecret = ProcessInfo.processInfo.environment["LIVEKIT_API_SECRET"] ?? "X2NasM6TLUJVi3l65jQKsGKhDa4z1zicQlfM8wgHZRU"
        self.liveKitUrl = ProcessInfo.processInfo.environment["LIVEKIT_URL"] ?? "wss://demoday-palh38uv.livekit.cloud"
    }
    
    func generateConnectionDetails() async throws -> ConnectionDetails {
        let participantIdentity = "voice_assistant_user_\(Int.random(in: 0...10000))"
        let roomName = "voice_assistant_room_\(Int.random(in: 0...10000))"
        
        let token = try JWTHelper.createToken(
            apiKey: apiKey,
            apiSecret: apiSecret,
            identity: participantIdentity,
            roomName: roomName
        )
        
        return ConnectionDetails(
            serverUrl: liveKitUrl,
            roomName: roomName,
            participantName: participantIdentity,
            participantToken: token
        )
    }
}
import SwiftUI
import LiveKit
import LiveKitComponents

struct VoiceAssistantView: View {
    @ObservedObject var connectionManager: RoomConnectionManager
    @State private var agentState: String = "disconnected"
    
    var body: some View {
        VStack {
            if !connectionManager.isConnected {
                Button(action: {
                    Task {
                        if let details = try? await connectionManager.generateConnectionDetails() {
                            connectionManager.connectionDetails = details
                            connectionManager.isConnected = true
                        }
                    }
                }) {
                    Text("Start a conversation")
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
            }
            
            if let details = connectionManager.connectionDetails {
                RoomScope(url: details.serverUrl,
                         token: details.participantToken,
                         connect: connectionManager.isConnected,
                         enableCamera: false,
                         enableMicrophone: true) {
                    VideoConferenceView()
                }
            }
        }
    }
} 

import Foundation
import AVFoundation

class SoundManager {
    static let shared = SoundManager()
    
    private var players: [String: AVAudioPlayer] = [:]
    
    private init() {
        loadSound(name: "stone")
        loadSound(name: "dead-stone")
        loadSound(name: "dead-stones")
    }
    
    private func loadSound(name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Resources/Sound") ??
                        Bundle.main.url(forResource: name, withExtension: "wav") else {
            print("Sound file not found: \(name)")
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[name] = player
        } catch {
            print("Error loading sound \(name): \(error)")
        }
    }
    
    func play(name: String) {
        guard UserDefaults.standard.bool(forKey: "playSound") else { return }
        
        if let player = players[name] {
            if player.isPlaying {
                player.stop()
                player.currentTime = 0
            }
            player.play()
        }
    }
}

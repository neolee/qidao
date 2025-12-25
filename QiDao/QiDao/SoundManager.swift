import Foundation
import AudioToolbox

class SoundManager {
    static let shared = SoundManager()

    private var soundIDs: [String: SystemSoundID] = [:]

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

        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        if status == kAudioServicesNoError {
            soundIDs[name] = soundID
        } else {
            print("Error loading sound \(name): \(status)")
        }
    }

    func play(name: String) {
        guard UserDefaults.standard.bool(forKey: "playSound") else { return }

        if let soundID = soundIDs[name] {
            AudioServicesPlaySystemSound(soundID)
        }
    }

    deinit {
        for soundID in soundIDs.values {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }
}

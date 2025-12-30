import Foundation
import qidao_coreFFI

extension AIManager {
    func addEventLog(_ message: String, type: LogType) {
        let entry = EngineLog(message: message, type: type)
        logEntries.append(entry)
        if logEntries.count > 1000 {
            logEntries.removeFirst(200)
        }
    }

    func addLog(_ message: String, isError: Bool = false) {
        var displayMessage = message
        if message.hasPrefix("[STDERR] ") {
            displayMessage = String(message.dropFirst(9))
        } else if message.hasPrefix("[STDERR]") {
            displayMessage = String(message.dropFirst(8))
        }

        let trimmed = displayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        let isComm = trimmed.hasPrefix(">>>") || trimmed.hasPrefix("<<<")
        if isComm && !showAllLogs { return }

        let lowerTrimmed = trimmed.lowercased()
        let containsErrorMarker = lowerTrimmed.contains("[error]") ||
                                 lowerTrimmed.contains("fatal error") ||
                                 lowerTrimmed.hasPrefix("error:") ||
                                 lowerTrimmed.contains(" error: ")

        let finalIsError = isError || containsErrorMarker
        let type: LogType = finalIsError ? .error : (isComm ? .raw : .info)
        let entry = EngineLog(message: trimmed, type: type)

        self.logEntries.append(entry)
        if self.logEntries.count > 2000 {
            self.logEntries.removeFirst(500)
        }

        if trimmed.contains("Started, ready to begin handling requests") {
            if !self.isEngineReady {
                self.isEngineReady = true
                // Only set to .ready if we are not already analyzing or thinking
                if self.aiStatus == .starting {
                    self.aiStatus = .ready
                    self.engineMessage = "AI Engine Ready".localized
                }
                self.addEventLog("AI Engine Ready".localized, type: .info)
            }
        } else if trimmed.contains("info: visits") {
            self.isEngineReady = true
            self.engineMessage = trimmed
        } else if finalIsError {
            self.engineMessage = String(format: "AI Error: %@".localized, trimmed)
        }
    }

    func startLogPolling() {
        logTask?.cancel()
        logTask = Task {
            while !Task.isCancelled {
                if let engine = analysisEngine {
                    let logs = await engine.getLogs()
                    for log in logs {
                        self.addLog(log)
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

import Foundation
import SwiftUI

class ProfileViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var isCloning: Bool = false
    @Published var cloningError: String?
    @Published var cloneDirectory: URL
    @Published var progressMessage: String? = nil
    @Published var cloneLog: [String] = []
    
    private let userDefaults = UserDefaults.standard
    private let profilesKey = "savedProfiles"
    private let cloneDirectoryKey = "cloneDirectory"
    
    init() {
        // Load clone directory or use Documents by default
        if let dirPath = userDefaults.string(forKey: cloneDirectoryKey),
           let url = URL(string: dirPath) {
            self.cloneDirectory = url
        } else {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.cloneDirectory = documentsURL.appendingPathComponent("Database", isDirectory: true)
        }
        loadProfiles()
    }
    
    func addProfile(_ profile: Profile) {
        profiles.append(profile)
        saveProfiles()
    }
    
    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }
    
    func deleteProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }
    
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encoded, forKey: profilesKey)
        }
    }
    
    private func loadProfiles() {
        if let data = userDefaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = decoded
        }
    }
    
    func cloneRepositories(for profile: Profile) async {
        await MainActor.run {
            self.isCloning = true
            self.cloningError = nil
            self.progressMessage = nil
            self.cloneLog.removeAll()
        }
        do {
            try await RepositoryService.cloneRepositories(for: profile, to: cloneDirectory)
            await MainActor.run {
                self.cloneLog.append("✅ Репозиторий успешно склонирован: \(profile.url)")
            }
        } catch let RepositoryError.cloningFailedWithMessage(message) {
            await MainActor.run {
                self.cloningError = message
                self.cloneLog.append("❌ Ошибка клонирования: \(message)")
            }
        } catch {
            await MainActor.run {
                self.cloningError = error.localizedDescription
                self.cloneLog.append("❌ Ошибка клонирования: \(error.localizedDescription)")
            }
        }
        await MainActor.run {
            self.isCloning = false
        }
    }
    
    func cloneOrUpdateAllRepositories(for profile: Profile) async {
        await MainActor.run {
            self.isCloning = true
            self.cloningError = nil
            self.progressMessage = nil
            self.cloneLog.removeAll()
        }
        do {
            var clonedCount = 0
            try await RepositoryService.cloneOrUpdateAllRepositories(for: profile, to: cloneDirectory) { msg in
                Task { @MainActor in
                    self.progressMessage = msg
                    self.cloneLog.append(msg)
                    if msg.contains("Cloning") || msg.contains("Fetching") {
                        clonedCount += 1
                    }
                }
            }
            await MainActor.run {
                if let idx = self.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self.profiles[idx].lastScanDate = Date()
                    self.saveProfiles()
                }
                if clonedCount == 0 {
                    let warnMsg = "⚠️ Не было склонировано ни одного репозитория. Проверьте токен и права доступа."
                    self.progressMessage = warnMsg
                    self.cloneLog.append(warnMsg)
                } else {
                    let successMsg = "✅ Все репозитории успешно склонированы/обновлены."
                    self.progressMessage = successMsg
                    self.cloneLog.append(successMsg)
                }
                self.isCloning = false
            }
        } catch let RepositoryError.cloningFailedWithMessage(message) {
            await MainActor.run {
                self.cloningError = message
                self.cloneLog.append("❌ Ошибка: \(message)")
                self.isCloning = false
            }
        } catch {
            await MainActor.run {
                self.cloningError = error.localizedDescription
                self.cloneLog.append("❌ Ошибка: \(error.localizedDescription)")
                self.isCloning = false
            }
        }
    }
    
    func pickCloneDirectory() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.title = "Select Directory for Cloning Repositories"
        if panel.runModal() == .OK, let url = panel.url {
            self.cloneDirectory = url
            userDefaults.set(url.absoluteString, forKey: cloneDirectoryKey)
        }
#endif
    }
} 
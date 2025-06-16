import Foundation

enum GitLabFetchMode: String, Codable, CaseIterable, Identifiable {
    case recursive = "Рекурсивный (include_subgroups)"
    case bashStyle = "Bash-style (по всем группам)"
    var id: String { self.rawValue }
}

struct Profile: Identifiable, Codable {
    var id: UUID
    var name: String
    var token: String
    var url: String
    var type: RepositoryType
    var lastScanDate: Date?
    var username: String?
    var gitlabFetchMode: GitLabFetchMode?
    
    init(id: UUID = UUID(), name: String, token: String, url: String, type: RepositoryType, lastScanDate: Date? = nil, username: String? = nil, gitlabFetchMode: GitLabFetchMode? = nil) {
        self.id = id
        self.name = name
        self.token = token
        self.url = url
        self.type = type
        self.lastScanDate = lastScanDate
        self.username = username
        self.gitlabFetchMode = gitlabFetchMode
    }
}

enum RepositoryType: String, Codable {
    case github = "GitHub"
    case gitlab = "GitLab"
} 
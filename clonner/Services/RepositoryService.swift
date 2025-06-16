import Foundation

struct RepoInfo {
    let owner: String
    let name: String
    let cloneURL: String
}

enum RepositoryError: Error {
    case invalidURL
    case cloningFailed
    case authenticationFailed
    case cloningFailedWithMessage(String)
    case apiError(String)
}

class RepositoryService {
    static func cloneRepositories(for profile: Profile, to directory: URL) async throws {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Формируем URL с токеном для приватных репозиториев
        var repoURL = profile.url
        if profile.token != "" {
            if repoURL.hasPrefix("https://") {
                let urlWithoutScheme = repoURL.dropFirst("https://".count)
                repoURL = "https://\(profile.token)@\(urlWithoutScheme)"
            }
        }

        // Создаём директорию, если её нет
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        process.currentDirectoryURL = directory

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--mirror", repoURL]

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw RepositoryError.cloningFailedWithMessage(output)
        }
    }
    
    static func getRepositories(for profile: Profile, progress: ((String) -> Void)? = nil) async throws -> [RepoInfo] {
        var repos: [RepoInfo] = []
        var totalCount = 0
        
        switch profile.type {
        case .github:
            repos = try await fetchGitHubRepos(token: profile.token, progress: progress, totalCount: &totalCount)
        case .gitlab:
            let mode = profile.gitlabFetchMode ?? .recursive
            switch mode {
            case .recursive:
                repos = try await fetchGitLabRepos_recursive(token: profile.token, progress: progress, baseURL: profile.url, totalCount: &totalCount)
            case .bashStyle:
                repos = try await fetchGitLabRepos_bashStyle(token: profile.token, progress: progress, baseURL: profile.url, totalCount: &totalCount)
            }
        }
        
        progress?("\n🔵 Итоговая статистика:")
        progress?("  • Всего найдено уникальных проектов: \(repos.count)")
        progress?("  • Всего репозиториев в ответах API: \(totalCount)")
        
        return repos
    }

    // MARK: - GitHub
    private static func fetchGitHubRepos(token: String, progress: ((String) -> Void)? = nil, totalCount: inout Int) async throws -> [RepoInfo] {
        var repos: [RepoInfo] = []
        let session = URLSession.shared
        var url = URL(string: "https://api.github.com/user/repos?per_page=100")!
        var page = 1
        
        progress?("🔵 Запрос к GitHub API: user/repos...")
        
        while true {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                progress?("❌ Ошибка GitHub API: \(httpResponse.statusCode) \(msg)")
                throw RepositoryError.apiError("GitHub API error: \(httpResponse.statusCode) \(msg)")
            }
            
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            totalCount += arr.count
            
            for repo in arr {
                guard let name = repo["name"] as? String,
                      let owner = repo["owner"] as? [String: Any],
                      let ownerLogin = owner["login"] as? String,
                      let cloneURLs = repo["clone_url"] as? String else { continue }
                progress?("  • Найден проект: \(ownerLogin)/\(name)")
                repos.append(RepoInfo(owner: ownerLogin, name: name, cloneURL: cloneURLs))
            }
            
            if arr.count < 100 { break }
            page += 1
            url = URL(string: "https://api.github.com/user/repos?per_page=100&page=\(page)")!
        }
        
        progress?("🔵 Найдено личных проектов: \(repos.count)")
        
        // Fetch org repos
        progress?("\n🔵 Запрос к GitHub API: user/orgs...")
        let orgsURL = URL(string: "https://api.github.com/user/orgs?per_page=100")!
        var orgsRequest = URLRequest(url: orgsURL)
        orgsRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (orgsData, orgsResponse) = try await session.data(for: orgsRequest)
        
        if let httpResponse = orgsResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let msg = String(data: orgsData, encoding: .utf8) ?? ""
            progress?("❌ Ошибка GitHub API (orgs): \(httpResponse.statusCode) \(msg)")
            throw RepositoryError.apiError("GitHub API error (orgs): \(httpResponse.statusCode) \(msg)")
        }
        
        guard let orgs = try? JSONSerialization.jsonObject(with: orgsData) as? [[String: Any]] else {
            progress?("🔵 Всего найдено проектов: \(repos.count)")
            return repos
        }
        
        var orgReposCount = 0
        for org in orgs {
            guard let orgLogin = org["login"] as? String else { continue }
            progress?("🔵 Организация: \(orgLogin)")
            var orgReposURL = URL(string: "https://api.github.com/orgs/\(orgLogin)/repos?per_page=100")!
            var orgPage = 1
            
            while true {
                var orgReposRequest = URLRequest(url: orgReposURL)
                orgReposRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (orgReposData, orgReposResponse) = try await session.data(for: orgReposRequest)
                
                if let httpResponse = orgReposResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let msg = String(data: orgReposData, encoding: .utf8) ?? ""
                    progress?("❌ Ошибка GitHub API (org repos): \(httpResponse.statusCode) \(msg)")
                    throw RepositoryError.apiError("GitHub API error (org repos): \(httpResponse.statusCode) \(msg)")
                }
                
                guard let orgReposArr = try? JSONSerialization.jsonObject(with: orgReposData) as? [[String: Any]] else { break }
                orgReposCount += orgReposArr.count
                totalCount += orgReposArr.count
                
                for repo in orgReposArr {
                    guard let name = repo["name"] as? String,
                          let cloneURLs = repo["clone_url"] as? String else { continue }
                    progress?("  • Найден проект: \(orgLogin)/\(name)")
                    repos.append(RepoInfo(owner: orgLogin, name: name, cloneURL: cloneURLs))
                }
                
                if orgReposArr.count < 100 { break }
                orgPage += 1
                orgReposURL = URL(string: "https://api.github.com/orgs/\(orgLogin)/repos?per_page=100&page=\(orgPage)")!
            }
        }
        
        progress?("🔵 Найдено проектов в организациях: \(orgReposCount)")
        return repos
    }

    // MARK: - GitLab
    // Рекурсивный способ (include_subgroups)
    private static func fetchGitLabRepos_recursive(token: String, progress: ((String) -> Void)? = nil, baseURL: String, totalCount: inout Int) async throws -> [RepoInfo] {
        var repos: [RepoInfo] = []
        let session = URLSession.shared
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let apiURL = trimmedBase + "/api/v4"
        
        progress?("🔵 Рекурсивный метод: получаем все проекты...")
        
        // Получаем все проекты с include_subgroups=true
        var projectsURL = URL(string: "\(apiURL)/projects?per_page=100&include_subgroups=true")!
        var page = 1
        
        while true {
            var request = URLRequest(url: projectsURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                progress?("❌ Ошибка GitLab API (projects, recursive): \(httpResponse.statusCode) \(msg)")
                throw RepositoryError.apiError("GitLab API error (projects, recursive): \(httpResponse.statusCode) \(msg)")
            }
            
            guard let projects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            totalCount += projects.count
            
            for project in projects {
                guard let name = project["name"] as? String,
                      let namespace = project["namespace"] as? [String: Any],
                      let owner = namespace["full_path"] as? String,
                      let cloneURLs = project["http_url_to_repo"] as? String else { continue }
                
                progress?("  • [Рекурсивный] Найден проект: \(owner)/\(name)")
                repos.append(RepoInfo(owner: owner, name: name, cloneURL: cloneURLs))
            }
            
            if projects.count < 100 { break }
            page += 1
            projectsURL = URL(string: "\(apiURL)/projects?per_page=100&include_subgroups=true&page=\(page)")!
        }
        
        progress?("🔵 Всего найдено проектов (рекурсивный): \(repos.count)")
        if !repos.isEmpty {
            progress?("\nСписок всех найденных проектов (рекурсивный):")
            for r in repos {
                progress?("  • \(r.owner)/\(r.name)")
            }
        }
        
        return repos
    }

    // Bash-style способ (по всем группам)
    private static func fetchGitLabRepos_bashStyle(token: String, progress: ((String) -> Void)? = nil, baseURL: String, totalCount: inout Int) async throws -> [RepoInfo] {
        var repos: [RepoInfo] = []
        let session = URLSession.shared
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let apiURL = trimmedBase + "/api/v4"
        
        // Получаем все группы
        let allGroups = try await fetchAllGitLabGroups(token: token, apiURL: apiURL, progress: progress)
        progress?("🔵 Bash-style: получаем проекты для каждой группы...")
        for group in allGroups {
            guard let groupId = group["id"] as? Int else { continue }
            if let groupName = group["full_path"] as? String {
                progress?("🔵 [Bash-style] Группа: \(groupName) (id: \(groupId))")
            }
            var groupReposURL = URL(string: "\(apiURL)/groups/\(groupId)/projects?per_page=100")!
            var groupPage = 1
            while true {
                var groupReposRequest = URLRequest(url: groupReposURL)
                groupReposRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (groupReposData, groupReposResponse) = try await session.data(for: groupReposRequest)
                if let httpResponse = groupReposResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let msg = String(data: groupReposData, encoding: .utf8) ?? ""
                    progress?("❌ Ошибка GitLab API (group projects, bash-style): \(httpResponse.statusCode) \(msg)")
                    throw RepositoryError.apiError("GitLab API error (group projects, bash-style): \(httpResponse.statusCode) \(msg)")
                }
                guard let groupReposArr = try? JSONSerialization.jsonObject(with: groupReposData) as? [[String: Any]] else { break }
                totalCount += groupReposArr.count
                
                for repo in groupReposArr {
                    guard let name = repo["name"] as? String,
                          let namespace = repo["namespace"] as? [String: Any],
                          let owner = namespace["full_path"] as? String,
                          let cloneURLs = repo["http_url_to_repo"] as? String else { continue }
                    progress?("  • [Bash-style] Найден проект: \(owner)/\(name)")
                    repos.append(RepoInfo(owner: owner, name: name, cloneURL: cloneURLs))
                }
                if groupReposArr.count < 100 { break }
                groupPage += 1
                groupReposURL = URL(string: "\(apiURL)/groups/\(groupId)/projects?per_page=100&page=\(groupPage)")!
            }
        }
        progress?("🔵 Всего найдено проектов (bash-style): \(repos.count)")
        if !repos.isEmpty {
            progress?("\nСписок всех найденных проектов (bash-style):")
            for r in repos {
                progress?("  • \(r.owner)/\(r.name)")
            }
        }
        return repos
    }

    // Recursively fetch all groups and subgroups
    private static func fetchAllGitLabGroups(token: String, apiURL: String, progress: ((String) -> Void)? = nil) async throws -> [[String: Any]] {
        var allGroups: [[String: Any]] = []
        let session = URLSession.shared
        
        // Сначала получаем все группы верхнего уровня
        var groupsURL = URL(string: "\(apiURL)/groups?per_page=100")!
        var page = 1
        
        progress?("🔵 Получаем все группы GitLab...")
        
        while true {
            var request = URLRequest(url: groupsURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                progress?("❌ Ошибка GitLab API (groups): \(httpResponse.statusCode) \(msg)")
                throw RepositoryError.apiError("GitLab API error (groups): \(httpResponse.statusCode) \(msg)")
            }
            
            guard let groups = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            
            for group in groups {
                if let groupName = group["full_path"] as? String {
                    progress?("🔵 Найдена группа: \(groupName)")
                }
                allGroups.append(group)
            }
            
            if groups.count < 100 { break }
            page += 1
            groupsURL = URL(string: "\(apiURL)/groups?per_page=100&page=\(page)")!
        }
        
        // Теперь получаем все подгруппы для каждой группы
        progress?("\n🔵 Получаем все подгруппы...")
        for group in allGroups {
            guard let groupId = group["id"] as? Int,
                  let groupName = group["full_path"] as? String else { continue }
            
            var subgroupsURL = URL(string: "\(apiURL)/groups/\(groupId)/subgroups?per_page=100")!
            var subgroupPage = 1
            
            while true {
                var request = URLRequest(url: subgroupsURL)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    progress?("❌ Ошибка GitLab API (subgroups for \(groupName)): \(httpResponse.statusCode) \(msg)")
                    throw RepositoryError.apiError("GitLab API error (subgroups): \(httpResponse.statusCode) \(msg)")
                }
                
                guard let subgroups = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
                
                for subgroup in subgroups {
                    if let subgroupName = subgroup["full_path"] as? String {
                        progress?("🔵 Найдена подгруппа: \(subgroupName)")
                    }
                    allGroups.append(subgroup)
                }
                
                if subgroups.count < 100 { break }
                subgroupPage += 1
                subgroupsURL = URL(string: "\(apiURL)/groups/\(groupId)/subgroups?per_page=100&page=\(subgroupPage)")!
            }
        }
        
        progress?("\n🔵 Всего найдено групп и подгрупп: \(allGroups.count)")
        progress?("Список всех найденных групп:")
        for group in allGroups {
            if let name = group["full_path"] as? String {
                progress?("  • \(name)")
            }
        }
        
        return allGroups
    }

    static func cloneOrUpdateAllRepositories(for profile: Profile, to baseDirectory: URL, progress: ((String) -> Void)? = nil) async throws {
        let repos = try await getRepositories(for: profile, progress: progress)
        let fileManager = FileManager.default
        let isGitLab = profile.type == .gitlab
        // For GitLab, extract domain for top-level folder
        var domainFolder: String? = nil
        if isGitLab {
            if let url = URL(string: profile.url), let host = url.host {
                domainFolder = host
            } else if let range = profile.url.range(of: "://") {
                // fallback: remove scheme manually
                let noScheme = profile.url[range.upperBound...]
                domainFolder = noScheme.split(separator: "/").first.map { String($0) }
            }
        }
        for repo in repos {
            let ownerDir: URL
            if let domain = domainFolder {
                ownerDir = baseDirectory.appendingPathComponent(domain, isDirectory: true)
                    .appendingPathComponent(repo.owner, isDirectory: true)
            } else {
                ownerDir = baseDirectory.appendingPathComponent(repo.owner, isDirectory: true)
            }
            let repoDir = ownerDir.appendingPathComponent(repo.name.hasSuffix(".git") ? repo.name : repo.name + ".git", isDirectory: true)
            try? fileManager.createDirectory(at: ownerDir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: repoDir.path) {
                // Update existing mirror repo
                progress?("Fetching updates for \(repo.owner)/\(repo.name)...")
                let process = Process()
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.currentDirectoryURL = repoDir
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["fetch", "--all"]
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    progress?("❌ Fetch failed for \(repo.owner)/\(repo.name):\n" + output)
                    throw RepositoryError.cloningFailedWithMessage("Fetch failed for \(repo.owner)/\(repo.name):\n" + output)
                } else {
                    progress?("✅ Обновлено: \(repo.owner)/\(repo.name)")
                }
            } else {
                // Clone new mirror repo
                progress?("Cloning \(repo.owner)/\(repo.name)...")
                let process = Process()
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.currentDirectoryURL = ownerDir
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                var cloneURL = repo.cloneURL
                // Вставляем токен для приватных репозиториев
                if profile.token != "" && cloneURL.hasPrefix("https://") {
                    let urlWithoutScheme = cloneURL.dropFirst("https://".count)
                    if profile.type == .gitlab, let username = profile.username, !username.isEmpty {
                        cloneURL = "https://\(username):\(profile.token)@\(urlWithoutScheme)"
                    } else {
                        cloneURL = "https://\(profile.token)@\(urlWithoutScheme)"
                    }
                }
                let repoFolderName = repo.name.hasSuffix(".git") ? repo.name : repo.name + ".git"
                process.arguments = ["clone", "--mirror", cloneURL, repoFolderName]
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    progress?("❌ Clone failed for \(repo.owner)/\(repo.name):\n" + output)
                    throw RepositoryError.cloningFailedWithMessage("Clone failed for \(repo.owner)/\(repo.name):\n" + output)
                } else {
                    progress?("✅ Склонировано: \(repo.owner)/\(repo.name)")
                }
            }
        }
    }
} 
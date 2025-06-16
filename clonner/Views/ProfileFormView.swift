import SwiftUI

struct ProfileFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    
    @State private var name: String = ""
    @State private var token: String = ""
    @State private var url: String = ""
    @State private var type: RepositoryType = .github
    @State private var username: String = ""
    @State private var gitlabFetchMode: GitLabFetchMode = .recursive
    
    private var editingProfile: Profile?
    
    init(viewModel: ProfileViewModel, editingProfile: Profile? = nil) {
        self.viewModel = viewModel
        self.editingProfile = editingProfile
        
        if let profile = editingProfile {
            _name = State(initialValue: profile.name)
            _token = State(initialValue: profile.token)
            _url = State(initialValue: profile.url)
            _type = State(initialValue: profile.type)
            _username = State(initialValue: profile.username ?? "")
            _gitlabFetchMode = State(initialValue: profile.gitlabFetchMode ?? .recursive)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Profile Information")
                .font(.title2.bold())
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 14) {
                HStack {
                    Text("Name").frame(width: 70, alignment: .leading)
                    TextField("", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("Token").frame(width: 70, alignment: .leading)
                    TextField("", text: $token)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("URL").frame(width: 70, alignment: .leading)
                    TextField("", text: $url)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                if type == .gitlab {
                    HStack {
                        Text("User Name").frame(width: 70, alignment: .leading)
                        TextField("", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    HStack {
                        Text("Метод поиска").frame(width: 70, alignment: .leading)
                        Picker("", selection: $gitlabFetchMode) {
                            ForEach(GitLabFetchMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Text("Type").frame(width: 70, alignment: .leading)
                    Picker("", selection: $type) {
                        Text("GitHub").tag(RepositoryType.github)
                        Text("GitLab").tag(RepositoryType.gitlab)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveProfile()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(minWidth: 380, minHeight: 270)
    }
    
    private func saveProfile() {
        let profile = Profile(
            id: editingProfile?.id ?? UUID(),
            name: name,
            token: token,
            url: url,
            type: type,
            lastScanDate: editingProfile?.lastScanDate,
            username: username.isEmpty ? nil : username,
            gitlabFetchMode: type == .gitlab ? gitlabFetchMode : nil
        )
        
        if editingProfile != nil {
            viewModel.updateProfile(profile)
        } else {
            viewModel.addProfile(profile)
        }
    }
} 
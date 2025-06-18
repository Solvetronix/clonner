import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingAddProfile = false
    @State private var selectedProfile: Profile?
    
    var body: some View {
        ZStack {
            NavigationView {
                ListPanel(viewModel: viewModel, showingAddProfile: $showingAddProfile, selectedProfile: $selectedProfile)
                    .disabled(viewModel.isCloning)
                MainLogPanel(viewModel: viewModel)
            }
        }
    }
}

struct ListPanel: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var showingAddProfile: Bool
    @Binding var selectedProfile: Profile?
    @State private var profileToDelete: Profile? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folder:")
                Text(viewModel.cloneDirectory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: { viewModel.pickCloneDirectory() }) {
                    Image(systemName: "folder")
                }
                .disabled(viewModel.isCloning)
            }
            .padding(.top, 0)
            .padding(.horizontal)
            .padding(.bottom, 8)
            Table(viewModel.profiles) {
                TableColumn("Type") { profile in
                    HStack {
                        Image(systemName: profile.type == .github ? "chevron.left.slash.chevron.right" : "cube.box")
                            .foregroundColor(profile.type == .github ? .blue : .orange)
                        Text(profile.type.rawValue)
                    }
                }
                TableColumn("Name") { profile in
                    Text(profile.name)
                        .font(.headline)
                }
                TableColumn("Last Scan") { profile in
                    if let date = profile.lastScanDate {
                        Text(date, style: .date)
                            + Text(" ") + Text(date, style: .time)
                    } else {
                        Text("—")
                    }
                }
                TableColumn("") { profile in
                    HStack(spacing: 12) {
                        Button(action: { selectedProfile = profile }) {
                            HoverableIcon(systemName: "pencil", help: "Edit")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(viewModel.isCloning)
                        Button(action: { profileToDelete = profile }) {
                            HoverableIcon(systemName: "trash", help: "Delete")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(viewModel.isCloning)
                        Button(action: {
                            Task { await viewModel.cloneOrUpdateAllRepositories(for: profile) }
                        }) {
                            HoverableIcon(systemName: "arrow.triangle.2.circlepath", help: "Clone/Update All Repositories")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(viewModel.isCloning)
                    }
                }
            }
            .frame(minHeight: 200)
        }
        .navigationTitle("Clonner 1.0")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddProfile = true }) {
                    Image(systemName: "plus")
                }.disabled(viewModel.isCloning)
            }
        }
        .sheet(isPresented: $showingAddProfile) {
            ProfileFormView(viewModel: viewModel)
        }
        .sheet(item: $selectedProfile) { profile in
            ProfileFormView(viewModel: viewModel, editingProfile: profile)
        }
        .alert("Are you sure you want to delete this profile?", isPresented: Binding<Bool>(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        ), actions: {
            Button("Cancel", role: .cancel) { profileToDelete = nil }
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    viewModel.deleteProfile(profile)
                    profileToDelete = nil
                }
            }
        }, message: {
            Text("This action cannot be undone.")
        })
    }
}

struct MainLogPanel: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var showCopyAlert = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: {
                    let logText = viewModel.cloneLog.joined(separator: "\n")
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                    #else
                    UIPasteboard.general.string = logText
                    #endif
                    showCopyAlert = true
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy all log to clipboard")
                .alert("Log copied", isPresented: $showCopyAlert) {
                    Button("OK", role: .cancel) {}
                }
                Button(action: {
                    viewModel.cloneLog.removeAll()
                }) {
                    Image(systemName: "trash")
                }
                .help("Clear operation log")
                .disabled(viewModel.isCloning)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.cloneLog.indices, id: \.self) { idx in
                            let msg = viewModel.cloneLog[idx]
                            let color: Color =
                                msg.hasPrefix("[green]") ? .green :
                                msg.hasPrefix("[yellow]") ? .yellow :
                                msg.hasPrefix("[blue]") ? .blue :
                                msg.contains("✅") ? .green :
                                msg.contains("❌") ? .red : .primary
                            let cleanMsg = msg
                                .replacingOccurrences(of: "[green]", with: "")
                                .replacingOccurrences(of: "[yellow]", with: "")
                                .replacingOccurrences(of: "[blue]", with: "")
                            Text(cleanMsg)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(color)
                                .id(idx)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: viewModel.cloneLog.count) { _ in
                    if let last = viewModel.cloneLog.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: .infinity)
            .padding(.bottom)
            Spacer()
        }
        .alert("Cloning Error", isPresented: .constant(viewModel.cloningError != nil)) {
            Button("OK") {
                viewModel.cloningError = nil
            }
        } message: {
            if let error = viewModel.cloningError {
                ScrollView { Text(error).textSelection(.enabled) }
            }
        }
    }
}

struct ProfileRow: View {
    let profile: Profile
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(profile.name)
                .font(.headline)
            Text(profile.type.rawValue)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct HoverableIcon: View {
    let systemName: String
    let help: String
    @State private var isHovered = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.gray.opacity(0.18) : Color.clear)
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .help(help)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ContentView()
} 

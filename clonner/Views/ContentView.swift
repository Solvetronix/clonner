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
                    Menu {
                        Button("Edit") { selectedProfile = profile }.disabled(viewModel.isCloning)
                        Button("Delete", role: .destructive) { viewModel.deleteProfile(profile) }.disabled(viewModel.isCloning)
                        Button("Clone/Update All Repositories") {
                            Task { await viewModel.cloneOrUpdateAllRepositories(for: profile) }
                        }.disabled(viewModel.isCloning)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .frame(minHeight: 200)
        }
        .navigationTitle("clonner 1.0")
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
            .padding(.bottom, 16)
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
                        }
                    }
                    .padding([.horizontal, .bottom])
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

#Preview {
    ContentView()
} 

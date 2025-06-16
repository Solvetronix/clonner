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
                    .disabled(viewModel.isCloning)
            }
            if viewModel.isCloning {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                VStack(spacing: 18) {
                    ProgressView()
                        .scaleEffect(1.4)
                        .padding(.bottom, 2)
                    Text("Cloning in progress...")
                        .font(.title3.bold())
                        .padding(.bottom, 2)
                    if let msg = viewModel.progressMessage {
                        Text(msg)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }
                }
                .padding(32)
                .background(.regularMaterial)
                .cornerRadius(18)
                .shadow(radius: 18)
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
                Button("Choose Folder") {
                    viewModel.pickCloneDirectory()
                }
            }
            .padding([.top, .horizontal])
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
                        Button("Edit") { selectedProfile = profile }
                        Button("Delete", role: .destructive) { viewModel.deleteProfile(profile) }
                        Button("Clone/Update All Repositories") {
                            Task { await viewModel.cloneOrUpdateAllRepositories(for: profile) }
                        }
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
                }
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
                Text("Operation Log:")
                    .font(.headline)
                Spacer()
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
            }
            .padding(.horizontal)
            .padding(.top, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.cloneLog.indices, id: \.self) { idx in
                            let msg = viewModel.cloneLog[idx]
                            Text(msg)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(msg.contains("✅") ? .green : (msg.contains("❌") ? .red : .primary))
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
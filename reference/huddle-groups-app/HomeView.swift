import SwiftUI

struct HomeView: View {
    @AppStorage("groups") private var stored = Data()
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case create, join
        var id: String { rawValue }
    }

    private var groups: [GroupRef] {
        (try? JSONDecoder().decode([GroupRef].self, from: stored)) ?? []
    }

    private func save(_ groups: [GroupRef]) {
        stored = (try? JSONEncoder().encode(groups)) ?? Data()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { g in
                    NavigationLink(value: g) {
                        HStack(spacing: 12) {
                            Image(systemName: "car.side.fill")
                                .font(.title3).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.red.gradient, in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.title).font(.headline)
                                Text("You're \(g.myName) · code \(g.sessionId)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    var all = groups
                    all.remove(atOffsets: idx)
                    save(all)
                }
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("Decide together", systemImage: "person.3.fill")
                    } description: {
                        Text("Everyone tells Muse their real budget in private. Muse finds options that work for the whole group, and nobody has to say their number out loud.")
                    } actions: {
                        Button("Start a decision") { sheet = .create }.buttonStyle(.borderedProminent)
                        Button("Join with a code") { sheet = .join }
                    }
                }
            }
            .navigationTitle("Huddle")
            .navigationDestination(for: GroupRef.self) { GroupView(group: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Join", systemImage: "person.badge.plus") { sheet = .join }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", systemImage: "plus") { sheet = .create }
                }
            }
            .sheet(item: $sheet) { kind in
                NewGroupSheet(kind: kind) { save(groups + [$0]) }
            }
        }
    }
}

private struct NewGroupSheet: View {
    let kind: HomeView.Sheet
    let onDone: (GroupRef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    @State private var template = "car"
    @State private var location = "Austin, TX"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $name).textContentType(.givenName)
                }
                if kind == .join {
                    Section("Invite code") {
                        TextField("e.g. 3f9a1c2b", text: $code)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } else {
                    Section("Decision") {
                        Picker("Type", selection: $template) {
                            Text("Family Toyota").tag("car")
                        }
                        TextField("City or ZIP", text: $location)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(kind == .join ? "Join a group" : "New decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kind == .join ? "Join" : "Create") { Task { await submit() } }
                        .disabled(busy || name.isEmpty || (kind == .join && code.isEmpty))
                }
            }
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        do {
            let sid = kind == .join
                ? code.trimmingCharacters(in: .whitespaces).lowercased()
                : try await API.create(template: template, location: location).id
            let j = try await API.join(sid, name: name)
            onDone(GroupRef(sessionId: j.id, memberId: j.memberId, title: j.title, myName: name))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    HomeView()
}

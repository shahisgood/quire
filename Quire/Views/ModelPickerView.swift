import SwiftUI

struct ModelPickerView: View {
    let selected: String
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filters: Set<Filter> = []

    enum Filter: String, CaseIterable, Identifiable {
        case free = "Free", vision = "Vision", reasoning = "Reasoning", files = "Files"
        var id: String { rawValue }
        func passes(_ m: ORModel) -> Bool {
            switch self {
            case .free: m.isFree
            case .vision: m.acceptsImages
            case .reasoning: m.supportsReasoning
            case .files: m.acceptsFiles
            }
        }
    }

    private var filtered: [ORModel] {
        let base = app.models.filter { m in filters.allSatisfy { $0.passes(m) } }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base
            .map { m in (m, max(TextUtil.fuzzyScore(q, m.id) * 1.2, TextUtil.fuzzyScore(q, m.name) * 1.1, TextUtil.fuzzyScore(q, String(m.description.prefix(200))) * 0.5)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var isBrowsing: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && filters.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases) { f in
                                let on = filters.contains(f)
                                Button {
                                    if on { filters.remove(f) } else { filters.insert(f) }
                                } label: {
                                    Text(f.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(on ? Color.qOnAccent : Color.qInk)
                                        .background(on ? Color.qAccent : Color.qRaised, in: .capsule)
                                        .overlay(Capsule().strokeBorder(on ? Color.clear : Color.qRule))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if app.models.isEmpty {
                    Section {
                        if app.loadingModels {
                            HStack { ProgressView(); Text("Loading models…").foregroundStyle(Color.qInk2) }
                        } else {
                            Text(app.modelsError ?? "No models loaded yet.")
                                .foregroundStyle(Color.qInk2)
                            Button("Try again") { Task { await app.refreshModels(force: true) } }
                        }
                    }
                } else if isBrowsing {
                    let recents = app.settings.recentModelIds.compactMap { app.model($0) }
                    if !recents.isEmpty {
                        Section("Recent") { ForEach(recents) { row($0) } }
                    }
                    let favs = app.settings.favouriteModelIds.compactMap { app.model($0) }.filter { !app.settings.recentModelIds.contains($0.id) }
                    if !favs.isEmpty {
                        Section("Favourites") { ForEach(favs) { row($0) } }
                    }
                    Section("All models · \(app.models.count)") { ForEach(app.models) { row($0) } }
                } else {
                    Section("\(filtered.count) models") { ForEach(filtered) { row($0) } }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search models")
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await app.refreshModels(force: true) } } label: {
                        if app.loadingModels { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("Refresh models")
                }
            }
            .task { await app.refreshModels() }
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ m: ORModel) -> some View {
        Button {
            onPick(m.id)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(m.shortName)
                            .font(.body.weight(m.id == selected ? .semibold : .regular))
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        if m.acceptsImages { Image(systemName: "eye").font(.caption2).foregroundStyle(Color.qInk2) }
                        if m.supportsReasoning { Image(systemName: "brain").font(.caption2).foregroundStyle(Color.qInk2) }
                    }
                    Text("\(m.provider) · \(Fmt.context(m.contextLength)) · \(Pricing.perMillion(m.pricing.prompt)) / \(Pricing.perMillion(m.pricing.completion))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if m.id == selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.qAccent).font(.body.weight(.semibold))
                }
                Button { app.toggleFavourite(m.id) } label: {
                    Image(systemName: app.settings.favouriteModelIds.contains(m.id) ? "star.fill" : "star")
                        .foregroundStyle(app.settings.favouriteModelIds.contains(m.id) ? Color.qAccent : Color.qInk2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(app.settings.favouriteModelIds.contains(m.id) ? "Unfavourite" : "Favourite")
            }
        }
        .listRowBackground(Color.qRaised)
    }
}

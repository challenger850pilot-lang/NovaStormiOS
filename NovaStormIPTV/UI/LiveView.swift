import SwiftUI

struct LiveView: View {
    let catalog: Catalog
    @State private var categories: [Category] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let e = error {
                    ErrorRetry(message: e) { Task { await load() } }
                } else if categories.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(categories) { c in
                        NavigationLink(c.name) { LiveCategoryView(catalog: catalog, category: c) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Live TV")
            .screenBackground()
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            try await catalog.loadCategories()
            categories = catalog.categories
        } catch {
            self.error = "Couldn't load channels: \(error.localizedDescription)"
        }
    }
}

struct LiveCategoryView: View {
    let catalog: Catalog
    let category: Category
    @State private var sections: [LiveSection] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let e = error {
                ErrorRetry(message: e) { Task { await load() } }
            } else if sections.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.label) {
                            ForEach(section.channels) { ch in
                                NavigationLink {
                                    PlayerView(title: ch.name, url: catalog.playUrl(ch), resume: nil)
                                } label: {
                                    ChannelRow(channel: ch)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            sections = try await catalog.sections(category.id)
        } catch {
            self.error = "Couldn't load \(category.name): \(error.localizedDescription)"
        }
    }
}

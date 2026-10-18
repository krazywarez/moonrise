import Library
import SwiftUI

private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
private let pageBackground = Color.black

struct LibraryScreen: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ForEach(LibrarySection.allCases) { section in
                        let pages = Library.pages(in: section)
                        if !pages.isEmpty {
                            NavigationLink(value: section) {
                                HStack {
                                    Text(section.title).font(.system(size: 17))
                                    Spacer()
                                    Text("\(pages.count)").font(.system(size: 13).monospacedDigit()).opacity(0.5)
                                }
                            }
                            .listRowBackground(pageBackground)
                        }
                    }
                } else {
                    ForEach(Library.search(query)) { page in
                        NavigationLink(value: page) { PageRow(page: page) }
                            .listRowBackground(pageBackground)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Saturn, Orion, M42, Voyager")
            .navigationDestination(for: LibrarySection.self) { SectionList(section: $0) }
            .navigationDestination(for: LibraryPage.self) { LibraryPageView(page: $0) }
        }
        .foregroundStyle(ink)
        .tint(ink)
    }
}

struct SectionList: View {
    var section: LibrarySection

    var body: some View {
        List(Library.pages(in: section)) { page in
            NavigationLink(value: page) { PageRow(page: page) }
                .listRowBackground(pageBackground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(section.title)
    }
}

struct PageRow: View {
    var page: LibraryPage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(page.title).font(.body)
            Text(page.subtitle).font(.system(size: 12)).opacity(0.6).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct LibraryPageView: View {
    var page: LibraryPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(page.section.title).font(.system(size: 11, weight: .medium)).textCase(.uppercase).tracking(0.8).opacity(0.6)
                Text(page.title).font(.largeTitle.weight(.medium)).padding(.top, 4)
                Text(page.subtitle).font(.subheadline).opacity(0.75).padding(.top, 2)
                Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 10).padding(.bottom, 16)

                PageDrawing(page: page, ink: ink, accent: accent)

                facts.padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.paragraphs, id: \.self) { Text($0).font(.body).lineSpacing(3) }
                }
                .padding(.top, 20)

                if let image = page.image { photo(image).padding(.top, 24) }

                sources.padding(.top, 24).padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ink)
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(page.facts, id: \.self) { f in
                GridRow(alignment: .firstTextBaseline) {
                    Text(f.label).font(.footnote).opacity(0.6)
                    Text(f.value).font(.subheadline.monospacedDigit())
                }
                Divider().overlay(ink.opacity(0.15))
            }
        }
    }

    private func photo(_ image: LibraryPage.Image) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: image.url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                case .failure: Color.black.frame(height: 120).overlay(Text("Image unavailable").font(.system(size: 12)).opacity(0.6))
                default: Color.black.frame(height: 200).overlay(ProgressView().tint(ink))
                }
            }
            Text(image.caption).font(.footnote).opacity(0.75)
            Link(destination: image.page) {
                Text("\(image.credit) · \(image.licence)").font(.system(size: 10)).opacity(0.55)
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources").font(.system(size: 11, weight: .medium)).textCase(.uppercase).tracking(0.8).opacity(0.6)
            ForEach(Array(page.sources.enumerated()), id: \.offset) { i, s in
                Link(destination: s.url) {
                    Text("\(i + 1). \(s.title)").font(.system(size: 12)).underline().opacity(0.8)
                }
            }
        }
    }
}

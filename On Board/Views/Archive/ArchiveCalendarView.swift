//
//  ArchiveCalendarView.swift
//  On Board
//

import SwiftUI

struct ArchiveCalendarView: View {
    let weeks: [BoardWeek]

    @Environment(BoardStore.self) private var store
    @State private var searchText = ""

    private var archivedWeeks: [BoardWeek] {
        weeks.filter { $0.status == .archived }.sorted { $0.startsAt > $1.startsAt }
    }

    private var filteredWeeks: [BoardWeek] {
        guard !searchText.isEmpty else { return archivedWeeks }
        let query = searchText.lowercased()
        return archivedWeeks.filter { rowLabel(for: $0).lowercased().contains(query) }
    }

    private var sections: [(id: String, title: String, weeks: [BoardWeek])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredWeeks) { week -> String in
            let comps = cal.dateComponents([.month, .year], from: week.startsAt)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { key, ws in
                let title = ws[0].startsAt.formatted(.dateTime.month(.wide).year())
                return (id: key, title: title, weeks: ws.sorted { $0.startsAt > $1.startsAt })
            }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.id) { section in
                Section {
                    ForEach(section.weeks) { week in
                        NavigationLink(value: BoardRoute.archivedWeek(week)) {
                            HStack {
                                Text(rowLabel(for: week))
                                    .fontStyle(.body)
                                Spacer()
                                Label("\(week.postCount)", systemImage: "doc.text")
                                    .fontStyle(.footnote)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                            .allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                        // Start the fetch the instant the row is tapped rather than
                        // waiting for ArchivedWeekView's .task (which only fires after
                        // the push/zoom transition has already begun) — by the time the
                        // transition finishes, posts are often already in flight or done.
                        .simultaneousGesture(TapGesture().onEnded {
                            Task { await store.loadArchivedWeek(week, for: store.currentUserID) }
                        })
                    }
                } header: {
                    Text(section.title)
                        .fontStyle(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search weeks")
    }

    private func rowLabel(for week: BoardWeek) -> String {
        let cal = Calendar.current
        let sunday = cal.date(byAdding: .day, value: -1, to: week.endsAt) ?? week.endsAt
        let leftFmt = Date.FormatStyle().weekday(.abbreviated).day()
        let left = week.startsAt.formatted(leftFmt)

        let startMonth = cal.component(.month, from: week.startsAt)
        let endMonth = cal.component(.month, from: sunday)
        let rightFmt = startMonth == endMonth
            ? Date.FormatStyle().weekday(.abbreviated).day()
            : Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()

        return "\(left) – \(sunday.formatted(rightFmt))"
    }
}

#Preview {
    NavigationStack {
        ArchiveCalendarView(weeks: BoardStore.previewBoard().boardWeeks)
            .navigationDestination(for: BoardRoute.self) { route in
                if case .archivedWeek(let week) = route {
                    ArchivedWeekView(week: week)
                }
            }
    }
    .environment(BoardStore.previewBoard())
}

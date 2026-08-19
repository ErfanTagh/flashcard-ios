import SwiftUI

/// The numbers from `/api/progress` for the selected collection, plus the cards
/// that are currently flagged. Pushed from the Cards tab rather than owning a
/// tab of its own, so it inherits that screen's navigation stack.
struct ProgressDashboardView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        List {
            Section {
                accuracyHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("This collection") {
                StatRow(label: "Cards", value: "\(store.progress.total)", systemImage: "square.stack")
                StatRow(label: "Studied", value: "\(store.progress.studied)", systemImage: "book")
                StatRow(label: "Not studied", value: "\(store.progress.unseen)", systemImage: "sparkles")
                StatRow(label: "Known", value: "\(store.progress.known)", systemImage: "checkmark.seal", tint: Theme.success)
                StatRow(label: "Needs review", value: "\(store.progress.needsReview)", systemImage: "flag", tint: Theme.accent)
                StatRow(label: "Total answers", value: "\(store.progress.attempts)", systemImage: "hand.tap")
                if let last = formattedLastReviewed {
                    StatRow(label: "Last studied", value: last, systemImage: "clock")
                }
            }

            if !flagged.isEmpty {
                Section("Flagged for review") {
                    ForEach(flagged) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.term).font(.subheadline.weight(.medium))
                            Text(card.definition)
                                .font(.caption)
                                .foregroundStyle(Theme.mutedForeground)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshAll() }
    }

    private var accuracyHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Theme.muted, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(store.progress.accuracy) / 100)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: store.progress.accuracy)
                VStack(spacing: 2) {
                    Text("\(store.progress.accuracy)%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("accuracy")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .frame(width: 160, height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Accuracy")
            .accessibilityValue("\(store.progress.accuracy) percent")

            if store.progress.attempts == 0 {
                Text("Answer a few cards to see your accuracy.")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var flagged: [Card] {
        store.cards.filter(\.needsReview)
    }

    /// The backend stores `last_reviewed` as a naive UTC ISO-8601 string with
    /// no zone suffix, so it is parsed as UTC explicitly rather than by
    /// `ISO8601DateFormatter`, which would reject it.
    private var formattedLastReviewed: String? {
        guard let raw = store.progress.lastReviewed else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            parser.dateFormat = format
            if let date = parser.date(from: raw) {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
        }
        return raw
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
                .foregroundStyle(.primary)
                .labelStyle(TintedLabelStyle(tint: tint))
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}

private struct TintedLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(tint).frame(width: 22)
            configuration.title
        }
    }
}

import SwiftUI

/// Shared copy for a poll's status line: "4/6 VOTED · CLOSES FRI 20:00".
private func pollStatusLine(_ poll: Poll, electorate: Int) -> String {
    let voted = Set(poll.votes.map(\.userId)).count
    var parts = ["\(voted)/\(max(electorate, voted)) VOTED"]
    if poll.isClosed {
        parts.append(String(localized: "CLOSED"))
    } else if let closes = poll.closesAt {
        parts.append("CLOSES " + closes.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased())
    }
    return parts.joined(separator: " · ")
}

// MARK: Compact card (crew screen)

struct PollSummaryCard: View {
    let poll: Poll
    let electorate: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(poll.kind.title, systemImage: poll.kind.icon)
                    .font(NTFont.mono(10.5, .semibold)).foregroundStyle(NTColor.milk(0.6))
                Spacer()
                if poll.isClosed { StatusChip(text: String(localized: "Decided"), color: NTColor.sage) }
                else { StatusChip(text: String(localized: "Open"), color: NTColor.gold) }
            }
            Text(poll.question).font(NTFont.heading(19, .bold)).tracking(-0.3).multilineTextAlignment(.leading).lineLimit(2)
            Text(poll.isClosed ? (poll.winner?.label ?? String(localized: "No winner yet")) : pollStatusLine(poll, electorate: electorate))
                .font(NTFont.mono(10.5, .medium))
                .foregroundStyle(poll.isClosed ? NTColor.sage : NTColor.milk(0.55)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .crewCard()
    }
}

// MARK: Detail

struct PollDetailView: View {
    let pollId: UUID
    let crewId: UUID
    let expeditionId: UUID?
    let crewName: String
    let people: [UUID: CrewPerson]
    let myId: UUID?
    let canManage: Bool
    var onPlanWinner: ((PollOption) -> Void)?
    var onChanged: () -> Void
    var onClose: () -> Void

    @State private var poll: Poll?
    @State private var showSuggest = false
    @State private var suggestText = ""
    @State private var showRoutePicker = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NTColor.pine.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let poll {
                        header(poll)
                        ForEach(poll.options) { option in optionCard(option, in: poll) }
                        if !poll.isClosed && (poll.allowMemberOptions || poll.createdBy == myId) && poll.options.count < 6 {
                            Button { poll.kind == .route ? (showRoutePicker = true) : (showSuggest = true) } label: {
                                Label(poll.kind == .route ? "Suggest a route" : (poll.kind == .where ? "Suggest another place" : "Suggest another option"),
                                      systemImage: "plus")
                                    .font(NTFont.body(15, .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(NTColor.pineLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                            }
                            .buttonStyle(.plain)
                        }
                        if let errorMessage {
                            Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                        }
                    } else {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 120)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 64).padding(.bottom, 130)
            }
            if let poll { bottomBar(poll) }
            VStack {
                HStack {
                    CircleIconButton(icon: "chevron.left", label: "Back", action: onClose)
                    Spacer()
                    Text("\(crewName.uppercased()) · POLL").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.6)).lineLimit(1)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
            }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .alert("Suggest an option", isPresented: $showSuggest) {
            TextField("Option", text: $suggestText)
            Button("Add") { addOption(label: suggestText, payload: PollPayload()) }
            Button("Cancel", role: .cancel) { suggestText = "" }
        }
        .sheet(isPresented: $showRoutePicker) {
            RoutePickSheet { route in
                if let id = UUID(uuidString: route.id) {
                    addOption(label: route.title.replacingOccurrences(of: "\n", with: " "),
                              payload: PollPayload(routeId: id.uuidString))
                }
            }
        }
    }

    private var electorate: Int { max(people.count, Set(poll?.votes.map(\.userId) ?? []).count) }

    private func header(_ poll: Poll) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(poll.question).font(NTFont.heading(34, .extraBold)).tracking(-0.9)
            HStack(spacing: 8) {
                if let author = poll.createdBy.flatMap({ people[$0] }) {
                    PersonAvatar(person: author, size: 22)
                    Text("\(author.displayName.split(separator: " ").first.map(String.init) ?? author.displayName) asked")
                        .font(NTFont.body(13.5)).foregroundStyle(NTColor.milk(0.7))
                }
                Text(pollStatusLine(poll, electorate: electorate)).font(NTFont.mono(10.5, .medium))
                    .foregroundStyle(poll.isClosed ? NTColor.sage : NTColor.gold).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func optionCard(_ option: PollOption, in poll: Poll) -> some View {
        let count = poll.count(for: option)
        let total = max(poll.votes.count, 1)
        let mine = poll.myVote(myId) == option.id
        let leads = poll.leaderIds.contains(option.id)
        let won = poll.winnerOptionId == option.id
        let voters = poll.votes.filter { $0.optionId == option.id }.compactMap { people[$0.userId] }
        return Button { vote(option, in: poll) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CrewCover(id: option.id)
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.label).font(NTFont.heading(19, .bold)).tracking(-0.3).multilineTextAlignment(.leading).lineLimit(2)
                        if won { Text("WINNER").font(NTFont.mono(10, .semibold)).foregroundStyle(NTColor.sage) }
                    }
                    Spacer(minLength: 4)
                    ZStack {
                        Circle().stroke(mine ? NTColor.accent : NTColor.milk(0.25), lineWidth: 2).frame(width: 28, height: 28)
                        if mine { Circle().fill(NTColor.accent).frame(width: 28, height: 28)
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x231007)) }
                    }
                }
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NTColor.pine)
                            Capsule().fill(leads || won ? NTColor.milk : NTColor.milk(0.3))
                                .frame(width: geo.size.width * CGFloat(count) / CGFloat(total))
                        }
                    }
                    .frame(height: 6)
                    Text("\(count)").font(NTFont.mono(12, .semibold))
                }
                if !voters.isEmpty {
                    HStack(spacing: 8) {
                        AvatarStack(people: voters, size: 24, maxShown: 5)
                        Text(voters.map { $0.displayName.split(separator: " ").first.map(String.init) ?? $0.displayName }.joined(separator: ", "))
                            .font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.6)).lineLimit(1)
                    }
                } else {
                    Text(option.addedBy.flatMap { people[$0] }.map { String(localized: "Added by \($0.displayName)") + " · " + String(localized: "no votes yet") }
                         ?? String(localized: "No votes yet"))
                        .font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55))
                }
            }
            .padding(16)
            .crewCard()
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(mine ? NTColor.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(poll.isClosed || isWorking)
    }

    @ViewBuilder
    private func bottomBar(_ poll: Poll) -> some View {
        let pending = people.values.filter { p in !poll.votes.contains { $0.userId == p.id } }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if poll.isClosed {
                    Text(poll.winner?.label ?? String(localized: "Tied — pick a winner")).font(NTFont.body(14, .semibold)).lineLimit(2)
                } else if pending.isEmpty {
                    Text("Everyone voted").font(NTFont.body(14, .semibold))
                } else {
                    Text(pending.prefix(2).map { $0.displayName.split(separator: " ").first.map(String.init) ?? $0.displayName }
                        .joined(separator: " & ") + (pending.count > 2 ? " +\(pending.count - 2)" : "") + " " + String(localized: "haven't voted"))
                        .font(NTFont.body(13.5, .semibold)).lineLimit(2)
                }
                if canManage && !poll.isClosed {
                    Text("ORGANIZER CAN CLOSE EARLY").font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.5))
                }
            }
            Spacer(minLength: 4)
            if poll.isClosed, poll.winner == nil, canManage, poll.isTied {
                // a tie the organizer has to break
                Menu {
                    ForEach(poll.options.filter { poll.leaderIds.contains($0.id) }) { o in
                        Button(o.label) { close(winner: o.id) }
                    }
                } label: { pill("Pick winner", filled: true) }
            } else if poll.isClosed, let winner = poll.winner, poll.kind == .where, canManage, let onPlanWinner {
                Button { onPlanWinner(winner) } label: { pill("Plan winner", filled: true) }.buttonStyle(.plain)
            } else if !poll.isClosed && canManage {
                Button { close(winner: nil) } label: { pill("Close poll", filled: false) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .background(NTColor.pine.opacity(0.96).overlay(alignment: .top) { Rectangle().fill(NTColor.pineLine).frame(height: 1) }.ignoresSafeArea())
    }

    private func pill(_ title: LocalizedStringKey, filled: Bool) -> some View {
        Text(title).font(NTFont.body(15, .semibold))
            .foregroundStyle(filled ? Color(hex: 0x231007) : NTColor.pine)
            .padding(.horizontal, 20).frame(height: 48)
            .background(filled ? NTColor.accent : NTColor.milk, in: Capsule())
    }

    // MARK: Actions

    private func load() async {
        let all = try? await CrewLiveRepository.shared.fetchPolls(crewId: crewId, expeditionId: expeditionId)
        poll = all?.first { $0.id == pollId } ?? poll
    }

    private func vote(_ option: PollOption, in poll: Poll) {
        guard poll.myVote(myId) != option.id else { return }
        isWorking = true; errorMessage = nil
        Task {
            do {
                try await CrewLiveRepository.shared.vote(pollId: poll.id, optionId: option.id)
                UISelectionFeedbackGenerator().selectionChanged()
            } catch { errorMessage = error.localizedDescription }
            await load(); onChanged(); isWorking = false
        }
    }

    private func close(winner: UUID?) {
        Task {
            do { try await CrewLiveRepository.shared.closePoll(pollId: pollId, winner: winner) }
            catch { errorMessage = error.localizedDescription }
            await load(); onChanged()
        }
    }

    private func addOption(label: String, payload: PollPayload) {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestText = ""
        guard !l.isEmpty else { return }
        Task {
            do { try await CrewLiveRepository.shared.addOption(pollId: pollId, label: l, payload: payload) }
            catch { errorMessage = error.localizedDescription }
            await load(); onChanged()
        }
    }
}

// MARK: Embedded in an itinerary day

struct EmbeddedPollCard: View {
    let poll: Poll
    let myId: UUID?
    let people: [UUID: CrewPerson]
    var onVote: (PollOption) -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("CREW POLL", systemImage: "chart.bar.fill").font(NTFont.mono(10.5, .semibold))
                Spacer()
                if let closes = poll.closesAt, !poll.isClosed {
                    Text("CLOSES " + closes.formatted(.dateTime.hour().minute()).uppercased())
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.gold)
                }
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(poll.question).font(NTFont.heading(20, .bold)).tracking(-0.3).multilineTextAlignment(.leading)
                    let voted = Set(poll.votes.map(\.userId)).count
                    Text("\(voted) voted" + (poll.votes.contains { $0.userId == myId } ? "" : " · " + String(localized: "you haven't yet")))
                        .font(NTFont.body(13)).foregroundStyle(NTColor.milk(0.6))
                }
            }
            .buttonStyle(.plain)
            ForEach(poll.options) { option in
                let n = poll.count(for: option)
                let mine = poll.myVote(myId) == option.id
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(option.label).font(NTFont.body(14.5, .semibold)).lineLimit(2)
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(NTColor.pine)
                                    Capsule().fill(poll.leaderIds.contains(option.id) ? NTColor.milk : NTColor.milk(0.3))
                                        .frame(width: geo.size.width * CGFloat(n) / CGFloat(max(poll.votes.count, 1)))
                                }
                            }.frame(height: 5)
                            Text("\(n)").font(NTFont.mono(11, .semibold))
                        }
                    }
                    Button { onVote(option) } label: {
                        Text(mine ? "Voted" : "Vote").font(NTFont.body(13.5, .semibold))
                            .foregroundStyle(mine ? NTColor.milk : NTColor.pine)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(mine ? NTColor.pineLine : NTColor.milk, in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(poll.isClosed)
                }
                .padding(12)
                .background(NTColor.pine, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(mine ? NTColor.accent : NTColor.pineLine, lineWidth: 1))
            }
        }
        .padding(16)
        .background(NTColor.pineElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.pineLine, lineWidth: 1))
    }
}

// MARK: Route picker

/// Pick one published Nomad route (for a "which way?" poll option).
struct RoutePickSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (Route) -> Void
    @State private var routes: [Route] = []
    @State private var query = ""
    @State private var isLoading = true

    private var filtered: [Route] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? routes : routes.filter { $0.title.lowercased().contains(q) || $0.place.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if isLoading { ProgressView().tint(NTColor.milk).padding(.top, 40) }
                    ForEach(filtered) { route in
                        Button { onPick(route); dismiss() } label: {
                            HStack(spacing: 12) {
                                RouteCoverImage(url: route.coverImageUrl, tint: NTColor.pineRaised)
                                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(15, .semibold)).lineLimit(1)
                                    Text("\(route.place) · \(String(format: "%.1f", route.distanceKM)) km")
                                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55)).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(10).crewCard(radius: 16)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Suggest a route")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search routes")
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task {
            routes = (try? await RouteRepository.shared.fetchRoutes()) ?? []
            isLoading = false
        }
    }
}

// MARK: Create

struct CreatePollView: View {
    @Environment(\.dismiss) private var dismiss
    let crewId: UUID
    let crewName: String
    var expeditionId: UUID?
    var day: Int?
    var onCreated: () -> Void

    @State private var kind: PollKind = .where
    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @State private var routeIds: [Int: String] = [:]
    @State private var hasDeadline = true
    @State private var closes = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var allowMembers = true
    @State private var closeWhenAll = true
    @State private var pickingRouteFor: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var cleaned: [(Int, String)] {
        options.enumerated().compactMap { i, t in
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : (i, s)
        }
    }
    private var canPost: Bool { !question.trimmingCharacters(in: .whitespaces).isEmpty && cleaned.count >= 2 && !isSaving }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(PollKind.allCases) { k in
                            Button { kind = k } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.icon).font(.system(size: 17))
                                    Text(k.title).font(NTFont.body(12.5, .semibold))
                                }
                                .frame(maxWidth: .infinity).frame(height: 62)
                                .foregroundStyle(kind == k ? NTColor.pine : NTColor.milk(0.85))
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(kind == k ? NTColor.milk : NTColor.pineRaised))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(kind == k ? .clear : NTColor.pineLine, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("Question")
                        TextField(kind == .where ? "Where do we go?" : "Ask the crew…", text: $question)
                            .font(NTFont.body(16, .medium)).padding(.horizontal, 16).frame(height: 54).crewCard(radius: 16)
                            .onChange(of: question) { _, n in if n.count > 200 { question = String(n.prefix(200)) } }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel("Options · 2–6")
                        VStack(spacing: 0) {
                            ForEach(options.indices, id: \.self) { i in
                                if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                                HStack(spacing: 10) {
                                    if kind == .route {
                                        Button { pickingRouteFor = i } label: {
                                            Text(options[i].isEmpty ? String(localized: "Pick a route") : options[i])
                                                .font(NTFont.body(15, .medium)).lineLimit(1)
                                                .foregroundStyle(options[i].isEmpty ? NTColor.milk(0.5) : NTColor.milk)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }.buttonStyle(.plain)
                                    } else {
                                        TextField("Option \(i + 1)", text: $options[i]).font(NTFont.body(15, .medium))
                                    }
                                    if options.count > 2 {
                                        Button { options.remove(at: i); routeIds = [:] } label: {
                                            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(NTColor.milk(0.6)).frame(width: 36, height: 36)
                                        }.buttonStyle(.plain).accessibilityLabel("Remove")
                                    }
                                }
                                .padding(.horizontal, 16).frame(height: 52)
                            }
                        }
                        .crewCard(radius: 16)
                        if options.count < 6 {
                            Button { options.append("") } label: {
                                Label("Add option", systemImage: "plus").font(NTFont.body(14.5, .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(NTColor.pineLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 0) {
                        Toggle(isOn: $hasDeadline) { Text("Deadline").font(NTFont.body(15, .semibold)) }
                            .tint(NTColor.sage).padding(14)
                        if hasDeadline {
                            Rectangle().fill(NTColor.pineLine).frame(height: 1)
                            DatePicker("Closes", selection: $closes, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .font(NTFont.body(15, .semibold)).padding(14)
                        }
                        Rectangle().fill(NTColor.pineLine).frame(height: 1)
                        toggleRow("Anyone can add options", sub: "Not just you", isOn: $allowMembers)
                        Rectangle().fill(NTColor.pineLine).frame(height: 1)
                        toggleRow("Close when everyone voted", sub: "Or at the deadline, whichever is first", isOn: $closeWhenAll)
                    }
                    .crewCard(radius: 16)
                    if let errorMessage { Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright) }
                    NTAccentButton(title: isSaving ? "Posting…" : "Post to \(crewName)") { post() }
                        .opacity(canPost ? 1 : 0.5).disabled(!canPost)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("New poll").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: kind) { _, _ in options = ["", ""]; routeIds = [:] }
            .sheet(item: Binding(get: { pickingRouteFor.map { Slot(i: $0) } }, set: { if $0 == nil { pickingRouteFor = nil } })) { slot in
                RoutePickSheet { route in
                    options[slot.i] = route.title.replacingOccurrences(of: "\n", with: " ")
                    routeIds[slot.i] = route.id
                }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }

    private struct Slot: Identifiable { let i: Int; var id: Int { i } }

    private func toggleRow(_ title: LocalizedStringKey, sub: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NTFont.body(15, .semibold))
                Text(sub).font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55))
            }
        }.tint(NTColor.sage).padding(14)
    }

    private func post() {
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await CrewLiveRepository.shared.createPoll(
                    crewId: crewId, expeditionId: expeditionId, day: day, kind: kind,
                    question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: cleaned.map { (i, label) in (label, PollPayload(routeId: routeIds[i], name: kind == .where ? label : nil)) },
                    closesAt: hasDeadline ? closes : nil, allowMemberOptions: allowMembers, closeWhenAllVoted: closeWhenAll)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss(); onCreated()
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}

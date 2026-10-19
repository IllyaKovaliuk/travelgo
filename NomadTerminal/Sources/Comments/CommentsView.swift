import SwiftUI

/// 19 · Route detail — Comments. Real thread, backed by `route_comments`.
struct CommentsView: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [RouteRepository.Comment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var reportingCommentID: String?
    @State private var reportedIDs: Set<String> = []
    @State private var myUserId: String?
    @State private var blockingComment: RouteRepository.Comment?
    @State private var blockFailed = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                if isLoading {
                    ProgressView().tint(NTColor.milk).padding(.top, 60)
                } else if comments.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 30))
                            .foregroundStyle(NTColor.milk(0.35))
                        Text("No comments yet")
                            .font(NTFont.body(14, .medium))
                            .foregroundStyle(NTColor.milk(0.55))
                        Text("Be the first to leave beta for this route.")
                            .font(NTFont.body(12.5, .light))
                            .foregroundStyle(NTColor.milk(0.4))
                    }
                    .padding(.top, 70)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(comments) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            composer
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .confirmationDialog("Why are you reporting this comment?", isPresented: Binding(
            get: { reportingCommentID != nil },
            set: { if !$0 { reportingCommentID = nil } }
        ), titleVisibility: .visible) {
            ForEach(["Spam", "Harassment", "Inappropriate content", "Other"], id: \.self) { reason in
                Button(reason) { report(reason: reason) }
            }
            Button("Cancel", role: .cancel) { reportingCommentID = nil }
        }
        .alert("Block this user?", isPresented: Binding(
            get: { blockingComment != nil },
            set: { if !$0 { blockingComment = nil } }
        )) {
            Button("Block", role: .destructive) { blockCommentAuthor() }
            Button("Cancel", role: .cancel) { blockingComment = nil }
        } message: {
            Text("Their routes, comments and photos will be hidden from you everywhere in Nomad. You can unblock them any time in Settings.")
        }
        .alert("Couldn't update the block list", isPresented: $blockFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    private func blockCommentAuthor() {
        guard let comment = blockingComment else { return }
        blockingComment = nil
        Task {
            do {
                try await RouteRepository.shared.blockUser(comment.authorId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(NTMotion.spring) { comments.removeAll { $0.authorId == comment.authorId } }
            } catch {
                blockFailed = true
            }
        }
    }

    private func report(reason: String) {
        guard let id = reportingCommentID else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        reportedIDs.insert(id)
        reportingCommentID = nil
        Task { try? await RouteRepository.shared.report(.comment, id: id, reason: reason) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.08)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(route.title.replacingOccurrences(of: "\n", with: " "))
                    .font(NTFont.heading(16, .bold))
                    .lineLimit(1)
                Text("\(comments.count) COMMENTS")
                    .font(NTFont.mono(10, .medium)).tracking(0.6)
                    .foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private func commentRow(_ comment: RouteRepository.Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(comment.authorInitials).font(NTFont.heading(12, .semibold)).foregroundStyle(NTColor.milk)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.authorName).font(NTFont.body(13.5, .semibold))
                    Text(comment.createdAgo).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.45))
                }
                Text(comment.body)
                    .font(NTFont.body(14, .light))
                    .foregroundStyle(NTColor.milk(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .contextMenu {
            if reportedIDs.contains(comment.id) {
                Label("Reported", systemImage: "checkmark").disabled(true)
            } else {
                Button(role: .destructive) { reportingCommentID = comment.id } label: {
                    Label("Report comment", systemImage: "flag")
                }
            }
            if comment.authorId != myUserId {
                Button(role: .destructive) { blockingComment = comment } label: {
                    Label("Block user", systemImage: "hand.raised")
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            ZStack {
                LinearGradient(colors: [NTColor.accent, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("ME").font(NTFont.mono(10, .semibold)).foregroundStyle(NTColor.milk)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            TextField("", text: $draft, prompt: Text("Add a comment…").foregroundStyle(NTColor.milk(0.4)))
                .font(NTFont.body(14, .regular))
                .foregroundStyle(NTColor.milk)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Capsule().fill(NTColor.milk(0.08)))
                .overlay(Capsule().stroke(NTColor.milk(0.18), lineWidth: 1))

            Button {
                send()
            } label: {
                if isSending {
                    ProgressView().tint(Color(hex: 0x231007)).frame(width: 46, height: 46)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x231007))
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty ? NTColor.accent.opacity(0.4) : NTColor.accent))
                }
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NTColor.pine)
    }

    private func load() async {
        myUserId = (try? await supabase.auth.session)?.user.id.uuidString
        do {
            comments = try await RouteRepository.shared.fetchComments(routeId: route.id)
        } catch {
            print("Comments fetch failed: \(error)")
        }
        withAnimation { isLoading = false }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        Task {
            do {
                try await RouteRepository.shared.postComment(routeId: route.id, body: body)
                RouteRepository.shared.logEvent("comment_posted")
                draft = ""
                comments = try await RouteRepository.shared.fetchComments(routeId: route.id)
            } catch {
                print("Post comment failed: \(error)")
            }
            isSending = false
        }
    }
}

import SwiftUI
import Combine
import Supabase

private struct SupportTicket: Codable, Identifiable, Hashable {
    let id: UUID
    let subject: String
    let status: String
    let created_at: Date
    let updated_at: Date
}

private struct SupportMessage: Codable, Identifiable, Hashable {
    let id: UUID
    let ticket_id: UUID
    let sender_id: UUID?
    let sender_type: String
    let body: String?
    let created_at: Date
}

private struct NewSupportTicket: Encodable { let user_id: UUID; let subject: String; let category: String }
private struct NewSupportMessage: Encodable { let ticket_id: UUID; let sender_id: UUID; let sender_type: String; let body: String }

@MainActor
private final class SupportChatStore: ObservableObject {
    @Published var ticket: SupportTicket?
    @Published var messages: [SupportMessage] = []
    @Published var draft = ""
    @Published var isLoading = true
    @Published var isSending = false
    @Published var errorMessage: String?
    private let client = SupabaseService.client
    private var userID: UUID?

    func start(restrictionContext: Bool) async {
        isLoading = true; errorMessage = nil
        do {
            let session = try await client.auth.session; userID = session.user.id
            let tickets: [SupportTicket] = try await client.from("support_tickets").select("id,subject,status,created_at,updated_at").order("updated_at", ascending: false).limit(20).execute().value
            if let existing = tickets.first(where: { $0.status != "closed" }) ?? tickets.first { ticket = existing; await loadMessages() }
            else if restrictionContext { try await createRestrictedAccountTicket() }
        } catch { errorMessage = "Impossible d’ouvrir le chat pour le moment." }
        isLoading = false
    }

    func refresh() async { guard ticket != nil else { return }; await loadMessages() }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        do {
            if ticket == nil { try await createTicket(subject: "Assistance Libérons", firstMessage: text); return }
            guard let ticket, ticket.status != "closed", let userID else { return }
            isSending = true
            try await client.from("support_messages").insert(NewSupportMessage(ticket_id: ticket.id, sender_id: userID, sender_type: "user", body: text)).execute()
            draft = ""; await loadMessages()
        } catch { errorMessage = "Le message n’a pas pu être envoyé." }
        isSending = false
    }

    private func createRestrictedAccountTicket() async throws { try await createTicket(subject: "Accès à mon compte Libérons", firstMessage: "Bonjour, je souhaite contacter le support au sujet de l’accès à mon compte Libérons.") }

    private func createTicket(subject: String, firstMessage: String) async throws {
        guard let userID else { return }; isSending = true
        let created: SupportTicket = try await client.from("support_tickets").insert(NewSupportTicket(user_id: userID, subject: subject, category: "account")).select("id,subject,status,created_at,updated_at").single().execute().value
        ticket = created
        try await client.from("support_messages").insert(NewSupportMessage(ticket_id: created.id, sender_id: userID, sender_type: "user", body: firstMessage)).execute()
        draft = ""; await loadMessages(); isSending = false
    }

    private func loadMessages() async {
        guard let ticket else { return }
        do { messages = try await client.from("support_messages").select("id,ticket_id,sender_id,sender_type,body,created_at").eq("ticket_id", value: ticket.id.uuidString).order("created_at", ascending: true).execute().value }
        catch { errorMessage = "Impossible d’actualiser la conversation." }
    }
}

struct SupportChatView: View {
    @ObservedObject var language: LanguageStore
    let restrictionContext: Bool
    @StateObject private var store = SupportChatStore()

    var body: some View {
        VStack(spacing: 0) {
            header; Divider().opacity(0.45); conversation
            if store.ticket?.status != "closed" { composer }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.start(restrictionContext: restrictionContext) }
        .alert(language.text("Support", "Support"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK", role: .cancel) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(Color.blue.opacity(0.12)).frame(width: 42, height: 42); Image(systemName: "message.fill").foregroundStyle(.blue) }
            VStack(alignment: .leading, spacing: 2) { Text("Libérons Support").font(.headline); Text(language.text("Private support conversation", "Conversation privée avec le support")).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.padding(.horizontal, 18).padding(.vertical, 12).background(.regularMaterial)
    }

    @ViewBuilder private var conversation: some View {
        if store.isLoading { Spacer(); ProgressView(); Spacer() }
        else if store.ticket == nil {
            VStack(spacing: 12) { Spacer(); Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 36)).foregroundStyle(.blue); Text(language.text("Talk to Libérons", "Parlez à Libérons")).font(.title3.bold()); Text(language.text("Write your message below. It will be sent directly to Libérons Support.", "Écrivez votre message ci-dessous. Il sera envoyé directement au support Libérons.")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 36); Spacer() }
        } else {
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(spacing: 10) { ForEach(store.messages) { message in bubble(message).id(message.id) }; if store.ticket?.status == "closed" { Text(language.text("This conversation is closed.", "Cette conversation est fermée.")).font(.caption).foregroundStyle(.secondary).padding(.vertical, 14) } }.padding(16) }
                    .refreshable { await store.refresh() }
                    .onChange(of: store.messages.count) { _ in if let id = store.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
        }
    }

    private func bubble(_ message: SupportMessage) -> some View {
        let mine = message.sender_type == "user"
        return HStack { if mine { Spacer(minLength: 54) }; VStack(alignment: mine ? .trailing : .leading, spacing: 4) { if !mine { Text(message.sender_type == "support" ? "Libérons Support" : "Libérons").font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }; if let body = message.body, !body.isEmpty { Text(body).font(.body).foregroundStyle(mine ? Color.white : Color.primary).padding(.horizontal, 14).padding(.vertical, 10).background(mine ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous)) } }; if !mine { Spacer(minLength: 54) } }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(language.text("Message…", "Message…"), text: $store.draft, axis: .vertical).lineLimit(1...5).padding(.horizontal, 14).padding(.vertical, 10).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            Button { Task { await store.send() } } label: { ZStack { Circle().fill(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.18) : Color.blue).frame(width: 40, height: 40); if store.isSending { ProgressView().tint(.white).scaleEffect(0.8) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white) } } }.disabled(store.isSending || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial)
    }
}

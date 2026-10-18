import SwiftUI

struct TranscriptView: View {
    let messages: [TranscriptMessage]
    let fileRequest: @MainActor (String) -> URLRequest?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message, fileRequest: fileRequest).id(message.id)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .onChange(of: messages.last?.id) { _, lastId in
                guard let lastId else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(lastId, anchor: .bottom) }
            }
        }
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MessageBubble: View {
    let message: TranscriptMessage
    let fileRequest: @MainActor (String) -> URLRequest?

    var body: some View {
        switch message.role {
        case .system:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        case .user, .assistant:
            bubble
        }
    }

    private var isUser: Bool { message.role == .user }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isUser ? "Du" : "Claude")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isUser ? Color.blue : Color.anthropicOrange)
                        .textCase(.uppercase)
                    if isUser && !message.delivered {
                        Image(systemName: "clock").font(.system(size: 8)).foregroundStyle(.secondary)
                            .accessibilityLabel("wird zugestellt")
                    }
                }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                ForEach(message.attachments) { attachment in
                    AttachmentView(attachment: attachment, request: fileRequest(attachment.path))
                }

                if !message.toolCalls.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver").font(.system(size: 8))
                        Text(message.toolCalls.prefix(2).joined(separator: ", ")).font(.system(size: 9))
                        if message.toolCalls.count > 2 {
                            Text("+\(message.toolCalls.count - 2)").font(.system(size: 9)).foregroundStyle(.gray)
                        }
                    }
                    .foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isUser ? Color.blue.opacity(0.25) : Color.white.opacity(0.1),
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: isUser ? 16 : 4,
                            bottomTrailingRadius: isUser ? 4 : 16,
                            topTrailingRadius: 16,
                            style: .continuous))
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
    }
}

/// Anhang von Claude: Bilder werden mit Token geladen und angezeigt, sonst nur der Name.
struct AttachmentView: View {
    let attachment: Attachment
    let request: URLRequest?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Label(attachment.name, systemImage: attachment.isImage ? "photo" : "paperclip")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .task(id: attachment.path) {
            guard attachment.isImage, let request,
                  let result = try? await URLSession.shared.data(for: request),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return }
            image = UIImage(data: result.0)
        }
    }
}

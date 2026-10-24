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
        .background(Color.hudBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: HUDMetrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HUDMetrics.radius, style: .continuous)
            .strokeBorder(Color.hudLine, lineWidth: HUDMetrics.hairline))
        .overlay(HUDCorners(length: 12).stroke(Color.hudCyan.opacity(0.75), lineWidth: 1.5))
    }
}

struct MessageBubble: View {
    let message: TranscriptMessage
    let fileRequest: @MainActor (String) -> URLRequest?

    var body: some View {
        switch message.role {
        case .system:
            Text(message.text)
                .font(.hudMono(11))
                .foregroundStyle(Color.hudMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        case .user, .assistant:
            bubble
        }
    }

    private var isUser: Bool { message.role == .user }

    /// Du in Gold, Claude in Cyan
    private var roleColor: Color { isUser ? .hudGold : .hudCyan }

    private var bubble: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.radius, style: .continuous)
        return HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isUser ? "Du" : "Claude")
                        .font(.hudMono(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(roleColor)
                        .textCase(.uppercase)
                    if isUser && !message.delivered {
                        Image(systemName: "clock").font(.system(size: 8)).foregroundStyle(Color.hudMuted)
                            .accessibilityLabel("wird zugestellt")
                    }
                }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.hudInk)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                ForEach(message.attachments) { attachment in
                    AttachmentView(attachment: attachment, request: fileRequest(attachment.path))
                }

                if !message.toolCalls.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver").font(.system(size: 8))
                        Text(message.toolCalls.prefix(2).joined(separator: ", ")).font(.hudMono(9))
                        if message.toolCalls.count > 2 {
                            Text("+\(message.toolCalls.count - 2)").font(.hudMono(9)).foregroundStyle(Color.hudMuted)
                        }
                    }
                    .foregroundStyle(Color.hudCyan.opacity(0.75))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(roleColor.opacity(isUser ? 0.1 : 0.07), in: shape)
            // Leuchtende Kante zur eigenen Seite: Claude links, du rechts
            .overlay(alignment: isUser ? .trailing : .leading) {
                Rectangle().fill(roleColor).frame(width: 2).shadow(color: roleColor, radius: 3)
            }
            .overlay(shape.strokeBorder(roleColor.opacity(isUser ? 0.35 : 0.25), lineWidth: HUDMetrics.hairline))
            .clipShape(shape)
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
                    .clipShape(RoundedRectangle(cornerRadius: HUDMetrics.radius))
                    .overlay(RoundedRectangle(cornerRadius: HUDMetrics.radius).strokeBorder(Color.hudLineStrong, lineWidth: HUDMetrics.hairline))
            } else {
                Label(attachment.name, systemImage: attachment.isImage ? "photo" : "paperclip")
                    .font(.hudMono(11))
                    .foregroundStyle(Color.hudInk.opacity(0.85))
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

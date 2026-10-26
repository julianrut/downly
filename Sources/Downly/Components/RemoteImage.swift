import AppKit
import SwiftUI

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession

    init() {
        cache.countLimit = 400
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> NSImage? {
        if let image = cached(url) {
            return image
        }
        if url.isFileURL {
            let image = NSImage(contentsOf: url)
            if let image { cache.setObject(image, forKey: url as NSURL) }
            return image
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if let host = url.host, host.contains("tiktok") {
            request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        }
        guard let (data, _) = try? await session.data(for: request), let image = NSImage(data: data) else {
            if url.absoluteString.contains("maxresdefault") {
                let fallback = URL(string: url.absoluteString.replacingOccurrences(of: "maxresdefault", with: "hqdefault"))
                if let fallback {
                    return await load(fallback)
                }
            }
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State var image: NSImage?

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImageCache.shared.cached(url) {
                image = cached
                return
            }
            let loaded = await ImageCache.shared.load(url)
            withAnimation(.easeOut(duration: 0.25)) {
                image = loaded
            }
        }
    }
}

extension RemoteImage where Placeholder == ThumbnailPlaceholder {
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = { ThumbnailPlaceholder() }
    }
}

struct ThumbnailPlaceholder: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.subtleFill)
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }
}

struct Shimmer: ViewModifier {
    @State var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                        .blendMode(.plusLighter)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2.5, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .shimmering()
    }
}

import AppKit
import DownlyCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) var model
    @State var dropTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            BackdropGlow()
            Group {
                switch model.setup {
                case .ready:
                    HomeView()
                        .transition(.opacity)
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                case .installing, .failed:
                    SetupView()
                        .transition(.opacity)
                }
            }
            if dropTargeted {
                DropOverlay()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onDrop(of: [.url, .plainText], isTargeted: $dropTargeted) { providers in
            model.handleDrop(providers)
        }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkClipboard()
        }
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
                .padding(24)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(Theme.brand)
                Text("Drop to download")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct HomeView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ScrollView {
                VStack(spacing: 16) {
                    LinkBar()
                    if let suggestion = model.clipboardSuggestion, case .idle = model.analysis {
                        ClipboardPill(link: suggestion)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    AnalysisArea()
                    if !model.downloads.items.isEmpty {
                        DownloadsSection()
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
        }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) var model

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            if model.downloads.activeCount > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("\(model.downloads.activeCount) active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Button {
                NSWorkspace.shared.open(Preferences.downloadFolder)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help("Open download folder")
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle(size: 26))
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .animation(.easeOut(duration: 0.2), value: model.downloads.activeCount)
    }
}

struct LinkBar: View {
    @Environment(AppModel.self) var model
    @FocusState var focused: Bool

    var detected: ParsedLink? {
        LinkParser.firstLink(in: model.input)
    }

    var isBusy: Bool {
        if case .loading = model.analysis { return true }
        return false
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            ZStack {
                if let detected {
                    PlatformBadge(platform: detected.platform, size: 22)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(width: 26)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: detected?.platform)

            TextField("", text: $model.input, prompt: Text("Paste a link from YouTube, Spotify, Instagram or TikTok"))
                .textFieldStyle(.plain)
                .font(.system(size: 15.5))
                .focused($focused)
                .onSubmit { model.submit() }
                .onChange(of: model.input) { old, new in
                    let grew = new.count - old.count
                    if old.isEmpty, grew > 10, LinkParser.firstLink(in: new) != nil {
                        model.submit(new)
                    }
                }

            if !model.input.isEmpty {
                Button {
                    model.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }

            if model.input.isEmpty {
                Button {
                    model.pasteFromClipboard()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste")
                    }
                }
                .buttonStyle(SoftButtonStyle())
                .help("Paste link (⇧⌘V)")
            } else if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34, height: 34)
            } else {
                Button {
                    model.submit()
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(GradientCircleButtonStyle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 58)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: Theme.violet.opacity(focused ? 0.16 : 0.06), radius: focused ? 18 : 12, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.hairline), lineWidth: focused ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.2), value: focused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focused = true
            }
        }
        .onChange(of: model.focusRequest) {
            focused = true
        }
    }
}

struct ClipboardPill: View {
    @Environment(AppModel.self) var model
    let link: ParsedLink

    var body: some View {
        HStack(spacing: 12) {
            PlatformBadge(platform: link.platform, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("Link on your clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(link.url.absoluteString)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Use Link") {
                model.useClipboardSuggestion()
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            Button {
                model.dismissClipboardSuggestion()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle(size: 24))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accent.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
        }
    }
}

struct HeroView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 116, height: 116)
                .shadow(color: Theme.violet.opacity(0.35), radius: 26, y: 12)
                .padding(.bottom, 4)
            VStack(spacing: 8) {
                Text("Download anything, beautifully.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Paste a link to save videos, music, reels, stories and photos —\nin the best quality, with sound, every time.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            PlatformStrip()
                .padding(.top, 6)
            HStack(spacing: 18) {
                hint("doc.on.clipboard", "Copy a link anywhere — Downly offers it")
                hint("hand.draw", "Or drag a link onto this window")
            }
            .padding(.top, 10)
        }
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}

struct AnalysisArea: View {
    @Environment(AppModel.self) var model

    var body: some View {
        Group {
            switch model.analysis {
            case .idle:
                if model.downloads.items.isEmpty {
                    HeroView()
                        .transition(.opacity)
                }
            case .loading(let link, let summary):
                LoadingCard(link: link, summary: summary)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            case .failed(let link, let message, let suggestion, let needsAccount):
                ErrorCard(link: link, message: message, suggestion: suggestion, needsAccount: needsAccount)
                    .transition(.opacity)
            case .loaded(let link, let analysis):
                Group {
                    switch analysis {
                    case .video(let video):
                        VideoCard(link: link, video: video)
                    case .playlist(let playlist):
                        PlaylistCard(link: link, playlist: playlist)
                    case .music(let collection):
                        MusicCard(link: link, collection: collection)
                    case .gallery(let gallery):
                        GalleryCard(link: link, gallery: gallery)
                    }
                }
                .id(model.analysisID)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)), removal: .opacity))
            }
        }
    }
}

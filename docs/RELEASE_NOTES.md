## Downly 2.0

Downly is rebuilt from the ground up with a Rust engine and a new interface, still designed to look and feel at home on your Mac.

- **Everything from 1.0.** YouTube in every quality up to 8K (always with sound), Spotify songs, albums and playlists matched on YouTube Music with Spotify's cover art and tags, Instagram posts, reels, stories, highlights and profile pictures, and TikTok videos without the watermark.
- **Feels native.** Translucent window with the traffic lights built into the toolbar, native menus and right-click menus, a Settings window with toolbar tabs, dark mode, a Dock badge while downloads run, and notifications when they finish in the background.
- **Runs on more Macs.** Now supports macOS 12 Monterey and later, on Apple Silicon and Intel.
- Copy a link anywhere and Downly offers it when you switch back, drag a link onto the window, or use the `downly://` bookmarklet from your browser.
- The download engine updates itself, so downloads keep working when sites change.

### Installing

1. Open `Downly.dmg` and drag Downly into Applications.
2. The app isn't notarized, so macOS blocks it the first time. Open **System Settings → Privacy & Security** and click **Open Anyway**. You can also run this in Terminal:
   `xattr -dr com.apple.quarantine /Applications/Downly.app`
3. On first launch Downly downloads its components (yt-dlp, FFmpeg and Deno). This happens once and takes about a minute.

Your settings and download history from Downly 1.0 aren't carried over.

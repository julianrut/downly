## Downly 2.1

A new look: flat, black and white, and stripped down to what you need.

- **One input.** The window opens to a single line: paste a link and go.
- **Pick quality at a glance.** Resolutions and formats are shown as large numbers and names; choose one and download.
- **Less noise.** No gradients, glows or explanatory text. Thumbnails stay grayscale until you hover them.
- **New icon** to match.
- Everything else is unchanged: YouTube up to 8K with sound, Spotify songs, albums and playlists, Instagram posts, reels, stories and profile pictures, and TikTok without the watermark.

### Installing

1. Open `Downly.dmg` and drag Downly into Applications.
2. The app isn't notarized, so macOS blocks it the first time. Open **System Settings → Privacy & Security** and click **Open Anyway**. You can also run this in Terminal:
   `xattr -dr com.apple.quarantine /Applications/Downly.app`
3. On first launch Downly downloads its components (yt-dlp, FFmpeg and Deno). This happens once and takes about a minute.

Requires macOS 12 Monterey or later. Runs natively on Apple Silicon and Intel.

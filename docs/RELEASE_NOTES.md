## Downly 1.0

Paste a link and download it on your Mac.

- **YouTube**: every quality from 144p to 8K, always with sound. Videos above 1080p can be converted to HEVC with your Mac's media engine so they play in QuickTime and Photos.
- **Spotify**: songs, albums and playlists. Downly matches each song on YouTube Music, then adds Spotify's cover art, title, artist and album.
- **Instagram**: posts, carousels, reels, stories, highlights and profile pictures.
- **TikTok**: videos without the watermark, photo posts and sounds.
- Works with 1,000+ other sites through yt-dlp.

### Installing

1. Open `Downly.dmg` and drag Downly into Applications.
2. The app isn't notarized, so macOS blocks it the first time. Open **System Settings → Privacy & Security** and click **Open Anyway**. You can also run this in Terminal:
   `xattr -dr com.apple.quarantine /Applications/Downly.app`
3. On first launch Downly downloads its components (yt-dlp, FFmpeg and Deno). This happens once and takes about a minute.

Requires macOS 14 Sonoma or later. Runs natively on Apple Silicon and Intel.

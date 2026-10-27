export type Platform = 'youtube' | 'spotify' | 'instagram' | 'tiktok' | 'web';
export type VideoContainer = 'mp4' | 'mkv';
export type AudioFormat = 'mp3' | 'm4a' | 'opus' | 'flac' | 'wav';
export type FilenameStyle = 'title' | 'titleAndId' | 'authorAndTitle';
export type CookieBrowser = 'safari' | 'chrome' | 'firefox' | 'brave' | 'edge' | 'opera' | 'vivaldi' | 'chromium';
export type Mode = 'video' | 'audio';

export type LinkKind =
  | { type: 'youtubeVideo'; id: string }
  | { type: 'youtubePlaylist'; id: string }
  | { type: 'youtubeOther' }
  | { type: 'spotifyTrack' | 'spotifyAlbum' | 'spotifyPlaylist' | 'spotifyArtist'; id: string }
  | { type: 'spotifyShort' }
  | { type: 'instagramPost'; shortcode: string }
  | { type: 'instagramStory'; username: string; storyId: string | null }
  | { type: 'instagramHighlight'; id: string }
  | { type: 'instagramProfile'; username: string }
  | { type: 'instagramShare' }
  | { type: 'tiktokVideo' | 'tiktokPhoto'; id: string }
  | { type: 'tiktokShort' | 'tiktokOther' | 'generic' };

export interface ParsedLink {
  url: string;
  platform: Platform;
  kind: LinkKind;
  playlistId: string | null;
  isMusic: boolean;
}

export interface MediaSummary {
  title: string;
  author: string | null;
  thumbnail: string | null;
  duration: number | null;
  platform: Platform;
  webpageUrl: string;
}

export interface VideoChoice {
  tier: number;
  label: string;
  caption: string;
  fps: number | null;
  isHdr: boolean;
  videoId: string;
  audioId: string | null;
  codec: string;
  audioCodec: string | null;
  muxed: boolean;
  estimatedBytes: number | null;
  needsTranscode: boolean;
  isVertical: boolean;
  selector: string;
  expectedSizes: Record<string, number>;
}

export interface AudioOption {
  format: AudioFormat;
  title: string;
  detail: string;
  estimatedBytes: number | null;
}

export interface PlaylistEntry {
  id: string;
  title: string;
  url: string;
  duration: number | null;
  thumbnail: string | null;
  author: string | null;
}

export interface SpotifyTrack {
  id: string;
  title: string;
  artists: string[];
  album: string | null;
  durationMs: number | null;
  cover: string | null;
  releaseDate: string | null;
  trackNumber: number | null;
  explicit: boolean;
}

export type GalleryKind = 'photo' | 'video' | 'audio';

export interface GalleryItem {
  id: string;
  kind: GalleryKind;
  url: string;
  thumbnail: string | null;
  width: number | null;
  height: number | null;
  headers: Record<string, string>;
  suggestedName: string;
  ytdlpUrl: string | null;
  playlistIndex: number | null;
}

export interface GallerySection {
  id: string;
  title: string;
  items: GalleryItem[];
}

export type Analysis =
  | {
      type: 'video';
      summary: MediaSummary;
      id: string;
      sourceUrl: string;
      isLive: boolean;
      playlistUrl: string | null;
      isMusic: boolean;
      hasVideo: boolean;
      mp4Choices: VideoChoice[];
      mkvChoices: VideoChoice[];
      audioOptions: AudioOption[];
    }
  | { type: 'playlist'; summary: MediaSummary; entries: PlaylistEntry[]; isMusic: boolean }
  | { type: 'music'; summary: MediaSummary; kind: 'track' | 'album' | 'playlist' | 'artist'; tracks: SpotifyTrack[] }
  | { type: 'gallery'; summary: MediaSummary; sections: GallerySection[]; folderName: string; isProfile: boolean };

export type JobKind =
  | {
      type: 'video';
      url: string;
      selector: string;
      sort: string | null;
      container: VideoContainer;
      appleCompatible: boolean;
      expectedSizes: Record<string, number>;
    }
  | { type: 'audio'; url: string; format: AudioFormat; squareCover: boolean }
  | { type: 'spotify'; track: SpotifyTrack; format: AudioFormat; folder: string | null }
  | { type: 'gallery'; items: GalleryItem[]; folder: string | null };

export interface DownloadJob {
  id: string;
  title: string;
  subtitle: string;
  detail: string;
  thumbnail: string | null;
  platform: Platform;
  kind: JobKind;
}

export type Phase =
  | { kind: 'preparing'; message: string }
  | { kind: 'downloading' }
  | { kind: 'processing'; message: string };

export type ItemState = 'queued' | 'running' | 'finished' | 'failed' | 'cancelled';

export interface DownloadItem {
  id: string;
  job: DownloadJob;
  state: ItemState;
  phase: Phase | null;
  fraction: number | null;
  speed: number | null;
  eta: number | null;
  downloaded: number | null;
  total: number | null;
  note: string | null;
  error: string | null;
  hint: string | null;
  files: string[];
  reveal: string | null;
  finishedAt: number | null;
  fileSize: number | null;
  filesExist: boolean;
  sourceUrl: string | null;
}

export interface Settings {
  downloadFolder: string;
  videoContainer: VideoContainer;
  appleCompatible: boolean;
  preferHdr: boolean;
  defaultQuality: number;
  audioFormat: AudioFormat;
  musicFormat: AudioFormat;
  embedMetadata: boolean;
  filenameStyle: FilenameStyle;
  cookieBrowser: CookieBrowser | null;
  alwaysUseCookies: boolean;
  maxConcurrent: number;
  notifications: boolean;
  watchClipboard: boolean;
  autoUpdateEngine: boolean;
  defaultMode: Mode;
}

export type ToolId = 'ytdlp' | 'ffmpeg' | 'ffprobe' | 'deno';

export type ToolPhase =
  | { state: 'waiting' }
  | { state: 'downloading'; fraction: number }
  | { state: 'installing' }
  | { state: 'ready'; version: string }
  | { state: 'failed'; message: string };

export interface ToolStatus {
  id: ToolId;
  name: string;
  phase: ToolPhase;
}

export interface SetupView {
  ready: boolean;
  running: boolean;
  tools: ToolStatus[];
  error: string | null;
  versions: Record<string, string>;
}

export interface Bootstrap {
  settings: Settings;
  setup: SetupView;
  downloads: DownloadItem[];
  version: string;
  platform: string;
  appleSilicon: boolean;
}

export interface ErrorInfo {
  message: string;
  suggestion: string | null;
  needsAccount: boolean;
  cancelled: boolean;
}

export interface BrowserInfo {
  id: CookieBrowser;
  name: string;
}

export interface EngineReport {
  updated: string | null;
  versions: Record<string, string>;
}

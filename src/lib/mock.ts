import type {
  Analysis,
  Bootstrap,
  DownloadItem,
  DownloadJob,
  GalleryItem,
  ParsedLink,
  Platform,
  Settings,
  SetupView,
  SpotifyTrack,
  VideoChoice,
} from './types';

type Handler = (payload: unknown) => void;

const listeners = new Map<string, Set<Handler>>();
const params = new URLSearchParams(typeof location !== 'undefined' ? location.search : '');
const demo = params.get('demo') ?? 'home';

function emit(event: string, payload: unknown) {
  listeners.get(event)?.forEach((handler) => handler(payload));
}

export function listen(event: string, handler: Handler): () => void {
  if (!listeners.has(event)) listeners.set(event, new Set());
  listeners.get(event)!.add(handler);
  return () => listeners.get(event)?.delete(handler);
}

const palettes = [
  ['#0f2027', '#203a43', '#2c5364', '#f8b195'],
  ['#ff9a8b', '#ff6a88', '#ff99ac', '#fcd5ce'],
  ['#355c7d', '#6c5b7b', '#c06c84', '#f67280'],
  ['#1a2a6c', '#b21f1f', '#fdbb2d', '#ffe29f'],
  ['#134e5e', '#71b280', '#d4fc79', '#96e6a1'],
  ['#41295a', '#2f0743', '#8e2de2', '#f5a1ff'],
  ['#ee9ca7', '#ffdde1', '#a1c4fd', '#c2e9fb'],
  ['#232526', '#414345', '#e96443', '#904e95'],
  ['#0b486b', '#f56217', '#fceabb', '#f8b500'],
  ['#3a1c71', '#d76d77', '#ffaf7b', '#fff1eb'],
];

export function art(seed: number, width = 640, height = 360): string {
  const [a, b, c, d] = palettes[seed % palettes.length];
  const r = (n: number) => ((Math.sin(seed * 9301 + n * 49297) + 1) / 2);
  const circles = Array.from({ length: 4 }, (_, i) => {
    const cx = Math.round(r(i) * width);
    const cy = Math.round(r(i + 7) * height);
    const radius = Math.round((0.18 + r(i + 3) * 0.32) * Math.min(width, height));
    const fill = [c, d, b, a][i];
    return `<circle cx="${cx}" cy="${cy}" r="${radius}" fill="${fill}" opacity="${0.35 + r(i + 11) * 0.4}"/>`;
  }).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="0.55" stop-color="${b}"/><stop offset="1" stop-color="${c}"/></linearGradient><filter id="f"><feGaussianBlur stdDeviation="${Math.round(Math.min(width, height) / 9)}"/></filter></defs><rect width="100%" height="100%" fill="url(#g)"/><g filter="url(#f)">${circles}</g></svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

const settings: Settings = {
  downloadFolder: '/Users/you/Downloads/Downly',
  videoContainer: 'mp4',
  appleCompatible: true,
  preferHdr: false,
  defaultQuality: 1080,
  audioFormat: 'mp3',
  musicFormat: 'mp3',
  embedMetadata: true,
  filenameStyle: 'title',
  cookieBrowser: params.get('tab') === 'accounts' ? 'chrome' : null,
  alwaysUseCookies: false,
  maxConcurrent: 3,
  notifications: true,
  watchClipboard: true,
  autoUpdateEngine: true,
  defaultMode: 'video',
};

const versions = { ytdlp: '2026.10.19', ffmpeg: '8.0.1', ffprobe: '8.0.1', deno: '2.5.6' };

function setupView(): SetupView {
  if (demo === 'setup') {
    return {
      ready: false,
      running: true,
      error: null,
      versions: {},
      tools: [
        { id: 'ytdlp', name: 'yt-dlp', phase: { state: 'ready', version: '2026.10.19' } },
        { id: 'ffmpeg', name: 'FFmpeg', phase: { state: 'downloading', fraction: 0.62 } },
        { id: 'ffprobe', name: 'FFprobe', phase: { state: 'downloading', fraction: 0.81 } },
        { id: 'deno', name: 'Deno', phase: { state: 'installing' } },
      ],
    };
  }
  return { ready: true, running: false, tools: [], error: null, versions };
}

function choice(tier: number, label: string, caption: string, bytes: number, extra: Partial<VideoChoice> = {}): VideoChoice {
  return {
    tier,
    label,
    caption,
    fps: null,
    isHdr: false,
    videoId: String(tier),
    audioId: '140',
    codec: 'h264',
    audioCodec: 'aac',
    muxed: false,
    estimatedBytes: bytes,
    needsTranscode: false,
    isVertical: false,
    selector: `${tier}+140`,
    expectedSizes: {},
    ...extra,
  };
}

function videoAnalysis(platform: Platform = 'youtube', vertical = false): Analysis {
  const youtube = platform === 'youtube';
  const choices = youtube
    ? [
        choice(2160, '4K', '2160p · 60 fps', 2_140_000_000, { fps: 60, codec: 'vp9', needsTranscode: true }),
        choice(1440, '1440p', 'Quad HD · 60 fps', 1_020_000_000, { fps: 60, codec: 'vp9', needsTranscode: true }),
        choice(1080, '1080p', 'Full HD · 60 fps', 412_000_000, { fps: 60 }),
        choice(720, '720p', 'HD · 60 fps', 198_000_000, { fps: 60 }),
        choice(480, '480p', 'SD', 86_000_000),
        choice(360, '360p', 'SD', 48_000_000),
      ]
    : [choice(1080, '1080p', 'Full HD', 18_400_000, { isVertical: vertical }), choice(720, '720p', 'HD', 9_100_000, { isVertical: vertical })];
  const duration = youtube ? 1336 : 27;
  return {
    type: 'video',
    summary: {
      title: youtube ? 'Exploring the Northern Lights — a 4K Journey Through Iceland' : 'golden hour in lisbon never misses ✨',
      author: youtube ? 'Wanderlust Films' : '@marta.travels',
      thumbnail: art(youtube ? 3 : 9, vertical ? 360 : 640, vertical ? 640 : 360),
      duration,
      platform,
      webpageUrl: youtube ? 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' : 'https://www.tiktok.com/@marta.travels/video/7311234567890123456',
    },
    id: 'demo',
    sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    isLive: false,
    playlistUrl: null,
    isMusic: false,
    hasVideo: true,
    mp4Choices: choices,
    mkvChoices: choices.map((c) => ({ ...c, needsTranscode: false, codec: c.tier > 1080 ? 'vp9' : c.codec })),
    audioOptions: [
      { format: 'mp3', title: 'MP3', detail: '320 kbps', estimatedBytes: Math.round((duration * 320000) / 8) },
      { format: 'm4a', title: 'M4A', detail: 'AAC', estimatedBytes: Math.round((duration * 129000) / 8) },
      { format: 'opus', title: 'Opus', detail: 'Original', estimatedBytes: Math.round((duration * 135000) / 8) },
      { format: 'flac', title: 'FLAC', detail: 'Lossless', estimatedBytes: Math.round((duration * 900000) / 8) },
      { format: 'wav', title: 'WAV', detail: 'PCM', estimatedBytes: Math.round((duration * 1411200) / 8) },
    ],
  };
}

const songs: [string, string, number, boolean][] = [
  ['Midnight Cartography', 'Lumen Vale', 214, false],
  ['Paper Satellites', 'Lumen Vale, Ora', 187, false],
  ['Glass Harbor', 'Lumen Vale', 243, true],
  ['Slow Bloom', 'Lumen Vale', 201, false],
  ['Neon Tides', 'Lumen Vale, Kai Rivers', 229, false],
  ['Afterglow Static', 'Lumen Vale', 196, false],
  ['Northbound', 'Lumen Vale', 258, false],
  ['Quiet Constellations', 'Lumen Vale', 233, false],
];

function musicAnalysis(): Analysis {
  const cover = art(5, 600, 600);
  const tracks: SpotifyTrack[] = songs.map(([title, artists, seconds, explicit], i) => ({
    id: `track${i}`,
    title,
    artists: artists.split(', '),
    album: 'Satellite Hearts',
    durationMs: seconds * 1000,
    cover,
    releaseDate: '2026-03-14',
    trackNumber: i + 1,
    explicit,
  }));
  return {
    type: 'music',
    kind: 'album',
    summary: { title: 'Satellite Hearts', author: 'Lumen Vale · 2026', thumbnail: cover, duration: null, platform: 'spotify', webpageUrl: 'https://open.spotify.com/album/demo' },
    tracks,
  };
}

function galleryAnalysis(profile = false): Analysis {
  const items: GalleryItem[] = Array.from({ length: profile ? 1 : 5 }, (_, i) => ({
    id: profile ? 'pfp' : `item${i}`,
    kind: i === 1 || i === 3 ? 'video' : 'photo',
    url: art(i + 1, 1080, 1350),
    thumbnail: art(i + 1, 480, 600),
    width: 1080,
    height: 1350,
    headers: {},
    suggestedName: `item${i}`,
    ytdlpUrl: null,
    playlistIndex: null,
  }));
  if (profile) {
    return {
      type: 'gallery',
      isProfile: true,
      folderName: 'marta.travels',
      summary: { title: 'Marta Lindqvist', author: '@marta.travels · 1.3M followers', thumbnail: art(6, 400, 400), duration: null, platform: 'instagram', webpageUrl: 'https://www.instagram.com/marta.travels/' },
      sections: [
        { id: 'pfp', title: 'Profile picture', items: [{ ...items[0], kind: 'photo', url: art(6, 1080, 1080), thumbnail: art(6, 400, 400) }] },
        {
          id: 'stories',
          title: 'Stories',
          items: Array.from({ length: 4 }, (_, i) => ({ ...items[0], id: `story${i}`, kind: i % 2 ? 'video' : 'photo', url: art(i + 2, 1080, 1920), thumbnail: art(i + 2, 360, 640) })),
        },
      ],
    };
  }
  return {
    type: 'gallery',
    isProfile: false,
    folderName: 'marta.travels — Lisbon',
    summary: { title: 'Three days of tiles, trams and pastéis de nata 🇵🇹', author: '@marta.travels', thumbnail: art(1, 480, 600), duration: null, platform: 'instagram', webpageUrl: 'https://www.instagram.com/p/CDUMkliABpa/' },
    sections: [{ id: 'post', title: 'Post', items }],
  };
}

function playlistAnalysis(): Analysis {
  const titles = ['Morning Light Over Reykjavík', 'Chasing Aurora at Jökulsárlón', 'Black Sand Beaches of Vík', 'The Golden Circle by Night', 'Westfjords Road Trip', 'Snæfellsnes in Winter'];
  return {
    type: 'playlist',
    isMusic: false,
    summary: { title: 'Iceland in 4K', author: 'Wanderlust Films', thumbnail: art(3), duration: null, platform: 'youtube', webpageUrl: 'https://www.youtube.com/playlist?list=demo' },
    entries: titles.map((title, i) => ({ id: `v${i}`, title, url: `https://www.youtube.com/watch?v=v${i}`, duration: 300 + i * 97, thumbnail: art(i + 2), author: 'Wanderlust Films' })),
  };
}

function item(job: Partial<DownloadJob> & { title: string }, rest: Partial<DownloadItem>): DownloadItem {
  const full: DownloadJob = {
    id: Math.random().toString(36).slice(2),
    subtitle: '',
    detail: '',
    thumbnail: null,
    platform: 'youtube',
    kind: { type: 'audio', url: '', format: 'mp3', squareCover: false },
    ...job,
  };
  return {
    id: full.id,
    job: full,
    state: 'finished',
    phase: null,
    fraction: null,
    speed: null,
    eta: null,
    downloaded: null,
    total: null,
    note: null,
    error: null,
    hint: null,
    files: ['/Users/you/Downloads/Downly/file.mp4'],
    reveal: '/Users/you/Downloads/Downly/file.mp4',
    finishedAt: Date.now() / 1000,
    fileSize: null,
    filesExist: true,
    sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    ...rest,
  };
}

function demoDownloads(): DownloadItem[] {
  if (!['downloads', 'video', 'spotify', 'gallery', 'playlist', 'profile', 'tiktok'].includes(demo)) return [];
  const list = [
    item(
      { title: 'Exploring the Northern Lights — a 4K Journey Through Iceland', subtitle: 'Wanderlust Films', detail: '4K · MP4', thumbnail: art(3), platform: 'youtube', kind: { type: 'video', url: '', selector: '', sort: null, container: 'mp4', appleCompatible: true, expectedSizes: {} } },
      { state: 'running', phase: { kind: 'downloading' }, fraction: 0.64, downloaded: 1_370_000_000, total: 2_140_000_000, speed: 38_400_000, eta: 21 },
    ),
    item(
      { title: 'Paper Satellites', subtitle: 'Lumen Vale, Ora', detail: 'MP3 · 320 kbps', thumbnail: art(5, 300, 300), platform: 'spotify' },
      { state: 'running', phase: { kind: 'processing', message: 'Adding cover art' }, fraction: null },
    ),
    item(
      { title: 'Three days of tiles, trams and pastéis de nata 🇵🇹', subtitle: '@marta.travels', detail: '3 photos · 2 videos', thumbnail: art(1, 300, 300), platform: 'instagram', kind: { type: 'gallery', items: [], folder: null } },
      { state: 'finished', fileSize: 48_200_000, files: ['a', 'b', 'c', 'd', 'e'] },
    ),
    item(
      { title: 'golden hour in lisbon never misses ✨', subtitle: '@marta.travels', detail: '1080p · MP4', thumbnail: art(9, 360, 640), platform: 'tiktok', kind: { type: 'video', url: '', selector: '', sort: null, container: 'mp4', appleCompatible: true, expectedSizes: {} } },
      { state: 'finished', fileSize: 18_400_000 },
    ),
    item(
      { title: 'Slow Bloom', subtitle: 'Lumen Vale', detail: 'MP3 · 320 kbps', thumbnail: art(5, 300, 300), platform: 'spotify' },
      { state: 'failed', error: 'Couldn’t find a good match on YouTube Music.', hint: 'Try again later or pick a different format.' },
    ),
  ];
  return demo === 'downloads' ? list : list.slice(2, 4);
}

let downloads: DownloadItem[] = demoDownloads();

function demoLink(url: string): ParsedLink | null {
  const text = url.trim();
  const match = text.match(/https?:\/\/\S+/) ?? text.match(/(?:www\.)?[a-z0-9-]+\.(?:com|be|tv|net)\/\S*/i);
  if (!match) return null;
  const href = match[0].startsWith('http') ? match[0] : `https://${match[0]}`;
  const platform: Platform = /youtu/.test(href) ? 'youtube' : /spotify/.test(href) ? 'spotify' : /instagram/.test(href) ? 'instagram' : /tiktok/.test(href) ? 'tiktok' : 'web';
  return { url: href, platform, kind: { type: 'generic' }, playlistId: null, isMusic: false };
}

function analysisFor(url: string): Analysis {
  if (/spotify/.test(url)) return musicAnalysis();
  if (/instagram\.com\/(?!p\/|reel)/.test(url)) return galleryAnalysis(true);
  if (/instagram/.test(url)) return galleryAnalysis();
  if (/tiktok/.test(url)) return videoAnalysis('tiktok', true);
  if (/list=/.test(url)) return playlistAnalysis();
  return videoAnalysis();
}

export function initialAnalysis(): { url: string; analysis: Analysis } | null {
  switch (demo) {
    case 'video':
      return { url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', analysis: videoAnalysis() };
    case 'tiktok':
      return { url: 'https://www.tiktok.com/@marta.travels/video/7311234567890123456', analysis: videoAnalysis('tiktok', true) };
    case 'spotify':
      return { url: 'https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy', analysis: musicAnalysis() };
    case 'gallery':
      return { url: 'https://www.instagram.com/p/CDUMkliABpa/', analysis: galleryAnalysis() };
    case 'profile':
      return { url: 'https://www.instagram.com/marta.travels/', analysis: galleryAnalysis(true) };
    case 'playlist':
      return { url: 'https://www.youtube.com/playlist?list=PLdemo', analysis: playlistAnalysis() };
    default:
      return null;
  }
}

function simulate(id: string) {
  let fraction = 0;
  const timer = setInterval(() => {
    const index = downloads.findIndex((d) => d.id === id);
    if (index < 0 || downloads[index].state !== 'running') {
      clearInterval(timer);
      return;
    }
    fraction = Math.min(1, fraction + 0.04 + Math.random() * 0.05);
    const current = downloads[index];
    const total = 180_000_000;
    if (fraction >= 1) {
      downloads[index] = { ...current, state: 'finished', phase: null, fraction: 1, fileSize: total, filesExist: true, files: ['/tmp/x'] };
      clearInterval(timer);
    } else {
      downloads[index] = { ...current, phase: { kind: 'downloading' }, fraction, downloaded: Math.round(total * fraction), total, speed: 24_000_000 + Math.random() * 9_000_000, eta: Math.round(((1 - fraction) * total) / 28_000_000) };
    }
    emit('download', downloads[index]);
  }, 400);
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function handle(command: string, args: Record<string, unknown>): Promise<unknown> {
  switch (command) {
    case 'bootstrap': {
      const boot: Bootstrap = { settings: { ...settings }, setup: setupView(), downloads, version: '2.0.0', platform: 'macos', appleSilicon: true };
      return boot;
    }
    case 'parse_link':
      return demoLink(String(args.text ?? ''));
    case 'quick_preview':
      return null;
    case 'analyze': {
      const url = String(args.text ?? '');
      await wait(demo === 'loading' ? 600_000 : 900);
      if (/fail|private/.test(url)) {
        throw { message: 'This content is private or needs you to be signed in.', suggestion: 'Choose a browser you’re signed in with in Settings → Accounts.', needsAccount: true, cancelled: false };
      }
      return analysisFor(url);
    }
    case 'enqueue': {
      const jobs = (args.jobs as DownloadJob[]) ?? [];
      const added = jobs.map((job) => item(job, { state: 'running', phase: { kind: 'preparing', message: 'Starting' }, files: [], filesExist: false, sourceUrl: null }));
      downloads = [...added, ...downloads];
      emit('downloads', downloads);
      added.forEach((d) => simulate(d.id));
      return null;
    }
    case 'cancel_download':
    case 'remove_download':
    case 'retry_download': {
      const id = String(args.id);
      if (command === 'remove_download') downloads = downloads.filter((d) => d.id !== id);
      if (command === 'cancel_download') downloads = downloads.map((d) => (d.id === id ? { ...d, state: 'cancelled', phase: null } : d));
      if (command === 'retry_download') {
        downloads = downloads.map((d) => (d.id === id ? { ...d, state: 'running', error: null, phase: { kind: 'preparing', message: 'Starting' } } : d));
        simulate(id);
      }
      emit('downloads', downloads);
      return null;
    }
    case 'clear_finished':
      downloads = downloads.filter((d) => d.state === 'queued' || d.state === 'running');
      emit('downloads', downloads);
      return null;
    case 'get_settings':
      return { ...settings };
    case 'update_settings':
      Object.assign(settings, args.settings as Settings);
      emit('settings', { ...settings });
      return { ...settings };
    case 'reset_settings':
      return { ...settings };
    case 'installed_browsers':
      return [
        { id: 'safari', name: 'Safari' },
        { id: 'chrome', name: 'Google Chrome' },
        { id: 'firefox', name: 'Firefox' },
        { id: 'brave', name: 'Brave' },
      ];
    case 'check_instagram_login':
      await wait(700);
      return true;
    case 'check_engine_updates':
      await wait(900);
      return { updated: null, versions };
    case 'read_clipboard_link':
      if (demo === 'clipboard' || args.force) {
        return { url: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ', platform: 'youtube', kind: { type: 'youtubeVideo', id: 'aqz-KE-bpKQ' }, playlistId: null, isMusic: false };
      }
      return null;
    default:
      return null;
  }
}

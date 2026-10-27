import { api, listen, onWindowFocus, prepareThumbs, toError } from './api';
import type { Analysis, DownloadItem, DownloadJob, ErrorInfo, MediaSummary, ParsedLink, Settings, SetupView } from './types';

export type AnalysisState =
  | { status: 'idle' }
  | { status: 'loading'; link: ParsedLink; preview: MediaSummary | null }
  | { status: 'loaded'; link: ParsedLink; analysis: Analysis; key: number }
  | { status: 'failed'; link: ParsedLink | null; error: ErrorInfo };

const defaultSettings: Settings = {
  downloadFolder: '~/Downloads/Downly',
  videoContainer: 'mp4',
  appleCompatible: true,
  preferHdr: false,
  defaultQuality: 1080,
  audioFormat: 'mp3',
  musicFormat: 'mp3',
  embedMetadata: true,
  filenameStyle: 'title',
  cookieBrowser: null,
  alwaysUseCookies: false,
  maxConcurrent: 3,
  notifications: true,
  watchClipboard: true,
  autoUpdateEngine: true,
  defaultMode: 'video',
};

class AppStore {
  booted = $state(false);
  version = $state('');
  settings = $state<Settings>({ ...defaultSettings });
  setup = $state<SetupView>({ ready: false, running: false, tools: [], error: null, versions: {} });
  downloads = $state<DownloadItem[]>([]);
  input = $state('');
  analysis = $state<AnalysisState>({ status: 'idle' });
  clipboard = $state<ParsedLink | null>(null);
  focusTick = $state(0);
  dropActive = $state(false);

  active = $derived(this.downloads.filter((d) => d.state === 'queued' || d.state === 'running').length);
  hasFinished = $derived(this.downloads.some((d) => d.state !== 'queued' && d.state !== 'running'));

  private token = 0;
  private dismissedClipboard: string | null = null;

  async init() {
    await prepareThumbs();
    const boot = await api.bootstrap();
    this.settings = boot.settings;
    this.setup = boot.setup;
    this.downloads = boot.downloads;
    this.version = boot.version;
    this.booted = true;

    await listen<DownloadItem[]>('downloads', (items) => {
      this.downloads = items;
    });
    await listen<DownloadItem>('download', (item) => {
      const index = this.downloads.findIndex((d) => d.id === item.id);
      if (index >= 0) this.downloads[index] = item;
    });
    await listen<SetupView>('setup', (setup) => {
      const becameReady = !this.setup.ready && setup.ready;
      this.setup = setup;
      if (becameReady) this.checkClipboard();
    });
    await listen<Settings>('settings', (settings) => {
      this.settings = settings;
    });
    await listen<void>('focus-link', () => {
      this.focusTick++;
    });
    await listen<void>('paste-link', () => {
      this.pasteLink();
    });
    await listen<string>('open-link', (text) => {
      this.input = text;
      this.submit(text);
    });
    await onWindowFocus(() => this.checkClipboard());
    if (this.setup.ready) this.checkClipboard();
  }

  async submit(text: string = this.input) {
    const raw = text.trim();
    if (!raw) return;
    const link = await api.parseLink(raw);
    if (!link) {
      this.token++;
      this.analysis = {
        status: 'failed',
        link: null,
        error: {
          message: 'That doesn’t look like a link.',
          suggestion: 'Paste a link from YouTube, Spotify, Instagram, TikTok or another video site.',
          needsAccount: false,
          cancelled: false,
        },
      };
      return;
    }
    this.input = link.url;
    this.analyze(link);
  }

  async analyze(link: ParsedLink, force = false) {
    const current = this.analysis;
    if (!force && (current.status === 'loading' || current.status === 'loaded') && current.link.url === link.url) return;
    const token = ++this.token;
    this.clipboard = null;
    this.analysis = { status: 'loading', link, preview: null };
    api
      .quickPreview(link.url)
      .then((preview) => {
        if (preview && token === this.token && this.analysis.status === 'loading') {
          this.analysis = { status: 'loading', link, preview };
        }
      })
      .catch(() => {});
    try {
      const analysis = await api.analyze(link.url);
      if (token !== this.token) return;
      this.analysis = { status: 'loaded', link, analysis, key: token };
    } catch (e) {
      if (token !== this.token) return;
      const error = toError(e);
      if (error.cancelled) return;
      this.analysis = { status: 'failed', link, error };
    }
  }

  retry() {
    const current = this.analysis;
    if (current.status === 'failed' && current.link) {
      this.analyze(current.link, true);
    } else {
      this.submit();
    }
  }

  openPlaylist(url: string) {
    this.input = url;
    this.submit(url);
  }

  clear() {
    this.token++;
    api.cancelAnalysis().catch(() => {});
    this.input = '';
    this.analysis = { status: 'idle' };
    this.focusTick++;
  }

  async enqueue(jobs: DownloadJob[]) {
    if (!jobs.length) return;
    await api.enqueue(jobs);
    this.token++;
    this.input = '';
    this.analysis = { status: 'idle' };
  }

  async pasteLink() {
    const link = await api.readClipboardLink(true);
    if (link) {
      this.input = link.url;
      this.analyze(link);
    } else {
      this.token++;
      this.analysis = {
        status: 'failed',
        link: null,
        error: {
          message: 'There’s no link on your clipboard.',
          suggestion: 'Copy a link from YouTube, Spotify, Instagram or TikTok, then press Paste.',
          needsAccount: false,
          cancelled: false,
        },
      };
    }
  }

  async checkClipboard() {
    if (!this.setup.ready || !this.settings.watchClipboard) return;
    const link = await api.readClipboardLink().catch(() => null);
    if (!link) return;
    if (link.url === this.dismissedClipboard) return;
    const current = this.analysis;
    if ((current.status === 'loading' || current.status === 'loaded') && current.link.url === link.url) return;
    if (this.input.trim() === link.url) return;
    if (this.downloads.slice(0, 5).some((d) => d.sourceUrl === link.url)) return;
    this.clipboard = link;
  }

  useClipboard() {
    const link = this.clipboard;
    if (!link) return;
    this.input = link.url;
    this.analyze(link);
  }

  dismissClipboard() {
    this.dismissedClipboard = this.clipboard?.url ?? null;
    this.clipboard = null;
  }

  async saveSettings(patch: Partial<Settings>) {
    const next = { ...this.settings, ...patch };
    this.settings = next;
    this.settings = await api.updateSettings(next);
  }
}

export const app = new AppStore();

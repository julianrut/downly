import type {
  Analysis,
  Bootstrap,
  BrowserInfo,
  CookieBrowser,
  DownloadItem,
  DownloadJob,
  EngineReport,
  ErrorInfo,
  MediaSummary,
  ParsedLink,
  Settings,
  SetupView,
} from './types';

export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

type Handler<T> = (payload: T) => void;

let mockModule: typeof import('./mock') | null = null;

async function mock() {
  if (!mockModule) mockModule = await import('./mock');
  return mockModule;
}

async function call<T>(command: string, args: Record<string, unknown> = {}): Promise<T> {
  if (isTauri) {
    const { invoke } = await import('@tauri-apps/api/core');
    return invoke<T>(command, args);
  }
  return (await mock()).handle(command, args) as Promise<T>;
}

export async function listen<T>(event: string, handler: Handler<T>): Promise<() => void> {
  if (isTauri) {
    const { listen } = await import('@tauri-apps/api/event');
    return listen<T>(event, (e) => handler(e.payload));
  }
  return (await mock()).listen(event, handler as Handler<unknown>);
}

export function toError(error: unknown): ErrorInfo {
  if (error && typeof error === 'object' && 'message' in error) {
    const e = error as Partial<ErrorInfo>;
    return {
      message: String(e.message ?? 'Something went wrong.'),
      suggestion: e.suggestion ?? null,
      needsAccount: Boolean(e.needsAccount),
      cancelled: Boolean(e.cancelled),
    };
  }
  return { message: String(error ?? 'Something went wrong.'), suggestion: null, needsAccount: false, cancelled: false };
}

export const api = {
  bootstrap: () => call<Bootstrap>('bootstrap'),
  startSetup: () => call<boolean>('start_setup'),
  parseLink: (text: string) => call<ParsedLink | null>('parse_link', { text }),
  quickPreview: (text: string) => call<MediaSummary | null>('quick_preview', { text }),
  analyze: (text: string) => call<Analysis>('analyze', { text }),
  cancelAnalysis: () => call<void>('cancel_analysis'),
  enqueue: (jobs: DownloadJob[]) => call<void>('enqueue', { jobs }),
  cancelDownload: (id: string) => call<void>('cancel_download', { id }),
  retryDownload: (id: string) => call<void>('retry_download', { id }),
  removeDownload: (id: string) => call<void>('remove_download', { id }),
  clearFinished: () => call<void>('clear_finished'),
  reveal: (id: string) => call<void>('reveal_download', { id }),
  open: (id: string) => call<void>('open_download', { id }),
  openUrl: (url: string) => call<void>('open_url', { url }),
  openDownloadsFolder: () => call<void>('open_downloads_folder'),
  getSettings: () => call<Settings>('get_settings'),
  updateSettings: (settings: Settings) => call<Settings>('update_settings', { settings }),
  resetSettings: () => call<Settings>('reset_settings'),
  chooseDownloadFolder: () => call<Settings | null>('choose_download_folder'),
  checkEngineUpdates: () => call<EngineReport>('check_engine_updates'),
  reinstallEngine: () => call<boolean>('reinstall_engine'),
  openToolsFolder: () => call<void>('open_tools_folder'),
  checkInstagramLogin: (browser: CookieBrowser) => call<boolean>('check_instagram_login', { browser }),
  installedBrowsers: () => call<BrowserInfo[]>('installed_browsers'),
  readClipboardLink: (force = false) => call<ParsedLink | null>('read_clipboard_link', { force }),
  copyText: (text: string) => call<void>('copy_text', { text }),
  openSettingsWindow: () => call<void>('open_settings_window'),
  showMainWindow: () => call<void>('show_main_window'),
};

export type DownloadsEvent = DownloadItem[];
export type SetupEvent = SetupView;

export async function windowLabel(): Promise<string> {
  if (isTauri) {
    const { getCurrentWebviewWindow } = await import('@tauri-apps/api/webviewWindow');
    return getCurrentWebviewWindow().label;
  }
  return new URLSearchParams(location.search).get('window') ?? 'main';
}

let converter: ((path: string, protocol?: string) => string) | null = null;

export async function prepareThumbs() {
  if (isTauri) {
    const core = await import('@tauri-apps/api/core');
    converter = core.convertFileSrc;
  }
}

export function thumb(url: string | null | undefined): string | null {
  if (!url) return null;
  if (!converter || url.startsWith('data:')) return url;
  return converter(url, 'thumb');
}

export interface MenuEntry {
  label?: string;
  action?: () => void;
  enabled?: boolean;
  separator?: boolean;
  accelerator?: string;
}

export async function popupMenu(entries: MenuEntry[]) {
  if (!isTauri) return;
  const { Menu, MenuItem, PredefinedMenuItem } = await import('@tauri-apps/api/menu');
  const items = await Promise.all(
    entries.map((entry) =>
      entry.separator
        ? PredefinedMenuItem.new({ item: 'Separator' })
        : MenuItem.new({
            text: entry.label ?? '',
            enabled: entry.enabled ?? true,
            accelerator: entry.accelerator,
            action: () => entry.action?.(),
          }),
    ),
  );
  const menu = await Menu.new({ items });
  await menu.popup();
}

export async function resizeWindow(width: number, height: number) {
  if (!isTauri) return;
  const { getCurrentWindow, LogicalSize } = await import('@tauri-apps/api/window');
  await getCurrentWindow().setSize(new LogicalSize(width, height));
}

export async function showCurrentWindow() {
  if (!isTauri) return;
  const { getCurrentWindow } = await import('@tauri-apps/api/window');
  const window = getCurrentWindow();
  await window.show();
  await window.setFocus();
}

export async function onWindowFocus(handler: () => void): Promise<() => void> {
  if (!isTauri) {
    const listener = () => handler();
    window.addEventListener('focus', listener);
    return () => window.removeEventListener('focus', listener);
  }
  const { getCurrentWindow } = await import('@tauri-apps/api/window');
  return getCurrentWindow().onFocusChanged(({ payload }) => {
    if (payload) handler();
  });
}

<script lang="ts">
  import { onMount, tick } from 'svelte';
  import Popup from './Popup.svelte';
  import Toggle from './Toggle.svelte';
  import ProgressBar from '../components/ProgressBar.svelte';
  import Tabs from '../components/Tabs.svelte';
  import { api, isTauri, listen, resizeWindow, showCurrentWindow, toError } from '../lib/api';
  import { audioFormats, homePath, tierLabel } from '../lib/format';
  import type { AudioFormat, BrowserInfo, CookieBrowser, FilenameStyle, Mode, Settings, SetupView, ToolId, VideoContainer } from '../lib/types';

  type Tab = 'general' | 'formats' | 'accounts' | 'engine';

  const tabs: { id: Tab; title: string }[] = [
    { id: 'general', title: 'General' },
    { id: 'formats', title: 'Formats' },
    { id: 'accounts', title: 'Accounts' },
    { id: 'engine', title: 'Engine' },
  ];

  const initialTab = new URLSearchParams(location.search).get('tab') as Tab | null;
  let tab = $state<Tab>(tabs.some((t) => t.id === initialTab) ? initialTab! : 'general');
  let settings = $state<Settings | null>(null);
  let setup = $state<SetupView | null>(null);
  let version = $state('');
  let browsers = $state<BrowserInfo[]>([]);
  let content: HTMLElement | undefined = $state();

  let loginStatus = $state<string | null>(null);
  let checkingLogin = $state(false);
  let engineMessage = $state<string | null>(null);
  let engineBusy = $state(false);

  const tools: { id: ToolId; name: string }[] = [
    { id: 'ytdlp', name: 'yt-dlp' },
    { id: 'ffmpeg', name: 'FFmpeg' },
    { id: 'ffprobe', name: 'FFprobe' },
    { id: 'deno', name: 'Deno' },
  ];

  const qualities = [0, 4320, 2160, 1440, 1080, 720, 480, 360];

  onMount(async () => {
    const boot = await api.bootstrap();
    settings = boot.settings;
    setup = boot.setup;
    version = boot.version;
    browsers = await api.installedBrowsers();
    await listen<Settings>('settings', (next) => (settings = next));
    await listen<SetupView>('setup', (next) => {
      const finished = setup?.running && !next.running;
      setup = next;
      if (finished) {
        engineBusy = false;
        engineMessage = next.error ? next.error : 'Reinstalled';
        fit();
      }
    });
    await fit();
    await showCurrentWindow();
  });

  $effect(() => {
    tab;
    loginStatus = null;
    fit();
  });

  async function fit() {
    await tick();
    if (!content) return;
    const height = Math.ceil(content.getBoundingClientRect().height) + 52;
    await resizeWindow(520, Math.min(720, Math.max(220, height)));
  }

  async function save(patch: Partial<Settings>) {
    if (!settings) return;
    const next = { ...settings, ...patch };
    settings = next;
    settings = await api.updateSettings(next);
  }

  async function chooseFolder() {
    const next = await api.chooseDownloadFolder();
    if (next) settings = next;
  }

  async function checkLogin() {
    if (!settings?.cookieBrowser) return;
    checkingLogin = true;
    loginStatus = null;
    try {
      loginStatus = (await api.checkInstagramLogin(settings.cookieBrowser)) ? 'Signed in' : 'Not signed in';
    } catch (error) {
      loginStatus = toError(error).message;
    }
    checkingLogin = false;
    await fit();
  }

  async function checkUpdates() {
    engineBusy = true;
    engineMessage = null;
    try {
      const report = await api.checkEngineUpdates();
      engineMessage = report.updated ? `Updated to ${report.updated}` : 'Up to date';
      if (setup) setup = { ...setup, versions: report.versions };
    } catch (error) {
      engineMessage = toError(error).message;
    }
    engineBusy = false;
    await fit();
  }

  async function reinstall() {
    engineBusy = true;
    engineMessage = null;
    try {
      if (!(await api.reinstallEngine())) engineBusy = false;
    } catch (error) {
      engineBusy = false;
      engineMessage = toError(error).message;
    }
    await fit();
  }

  const filenameOptions: { id: FilenameStyle; title: string }[] = [
    { id: 'title', title: 'Title' },
    { id: 'titleAndId', title: 'Title [ID]' },
    { id: 'authorAndTitle', title: 'Creator – Title' },
  ];

  const formatOptions = audioFormats.map((f) => ({ id: f.id as AudioFormat, title: f.title }));

  let browserOptions = $derived<{ id: CookieBrowser | null; title: string }[]>([
    { id: null, title: 'None' },
    ...browsers.map((b) => ({ id: b.id, title: b.name })),
  ]);

  let reinstalling = $derived(Boolean(setup?.running));
  let overall = $derived.by(() => {
    const list = setup?.tools ?? [];
    if (!list.length) return 0;
    return (
      list
        .map((t) => (t.phase.state === 'downloading' ? t.phase.fraction * 0.9 : t.phase.state === 'installing' ? 0.95 : t.phase.state === 'ready' ? 1 : 0))
        .reduce((a, b) => a + b, 0) / list.length
    );
  });
</script>

<div class="settings" class:browser={!isTauri}>
  <header class="toolbar" data-tauri-drag-region>
    {#if !isTauri}
      <div class="lights" aria-hidden="true"><span></span><span></span><span></span></div>
    {/if}
    <Tabs bind:value={tab} options={tabs} label="Settings" />
  </header>

  {#if settings}
    <div class="content" bind:this={content}>
      {#if tab === 'general'}
        <div class="row">
          <span class="name">Save to</span>
          <button class="value link mono truncate" title={settings.downloadFolder} onclick={chooseFolder}>{homePath(settings.downloadFolder)}</button>
        </div>
        <div class="row">
          <span class="name">Simultaneous downloads</span>
          <span class="stepper mono">
            <button aria-label="Fewer" disabled={settings.maxConcurrent <= 1} onclick={() => save({ maxConcurrent: settings!.maxConcurrent - 1 })}>−</button>
            <span>{settings.maxConcurrent}</span>
            <button aria-label="More" disabled={settings.maxConcurrent >= 6} onclick={() => save({ maxConcurrent: settings!.maxConcurrent + 1 })}>+</button>
          </span>
        </div>
        <div class="row">
          <span class="name">File names</span>
          <Popup label="File names" value={settings.filenameStyle} options={filenameOptions} onchange={(v) => save({ filenameStyle: v })} />
        </div>
        <div class="row">
          <span class="name">Suggest copied links</span>
          <Toggle label="Suggest copied links" checked={settings.watchClipboard} onchange={(v) => save({ watchClipboard: v })} />
        </div>
        <div class="row">
          <span class="name">Notifications</span>
          <Toggle label="Notifications" checked={settings.notifications} onchange={(v) => save({ notifications: v })} />
        </div>
      {:else if tab === 'formats'}
        <div class="section label">Video</div>
        <div class="row">
          <span class="name">Default</span>
          <Popup
            label="Default"
            value={settings.defaultMode}
            options={[
              { id: 'video' as Mode, title: 'Video' },
              { id: 'audio' as Mode, title: 'Audio' },
            ]}
            onchange={(v) => save({ defaultMode: v })}
          />
        </div>
        <div class="row">
          <span class="name">Quality</span>
          <Popup label="Quality" value={settings.defaultQuality} options={qualities.map((q) => ({ id: q, title: q === 0 ? 'Best' : tierLabel(q) }))} onchange={(v) => save({ defaultQuality: v })} />
        </div>
        <div class="row">
          <span class="name">Container</span>
          <Popup
            label="Container"
            value={settings.videoContainer}
            options={[
              { id: 'mp4' as VideoContainer, title: 'MP4' },
              { id: 'mkv' as VideoContainer, title: 'MKV' },
            ]}
            onchange={(v) => save({ videoContainer: v })}
          />
        </div>
        <div class="row">
          <span class="name">QuickTime compatible</span>
          <Toggle label="QuickTime compatible" checked={settings.appleCompatible} disabled={settings.videoContainer !== 'mp4'} onchange={(v) => save({ appleCompatible: v })} />
        </div>
        <div class="row">
          <span class="name">Prefer HDR</span>
          <Toggle label="Prefer HDR" checked={settings.preferHdr} onchange={(v) => save({ preferHdr: v })} />
        </div>
        <div class="section label">Audio</div>
        <div class="row">
          <span class="name">Format</span>
          <Popup label="Audio format" value={settings.audioFormat} options={formatOptions} onchange={(v) => save({ audioFormat: v })} />
        </div>
        <div class="row">
          <span class="name">Spotify format</span>
          <Popup label="Spotify format" value={settings.musicFormat} options={formatOptions} onchange={(v) => save({ musicFormat: v })} />
        </div>
        <div class="row">
          <span class="name">Cover art and tags</span>
          <Toggle label="Cover art and tags" checked={settings.embedMetadata} onchange={(v) => save({ embedMetadata: v })} />
        </div>
      {:else if tab === 'accounts'}
        <div class="row">
          <span class="name">Browser sign-in</span>
          <Popup
            label="Browser sign-in"
            value={settings.cookieBrowser}
            options={browserOptions}
            onchange={(v) => {
              loginStatus = null;
              save({ cookieBrowser: v });
            }}
          />
        </div>
        <div class="row">
          <span class="name">Use for all sites</span>
          <Toggle label="Use for all sites" checked={settings.alwaysUseCookies} disabled={!settings.cookieBrowser} onchange={(v) => save({ alwaysUseCookies: v })} />
        </div>
        <div class="row">
          <span class="name">Instagram</span>
          <span class="value">
            {#if checkingLogin}<span class="spinner"></span>{:else if loginStatus}<span class="note">{loginStatus}</span>{/if}
            <button class="text-button strong" disabled={!settings.cookieBrowser || checkingLogin} onclick={checkLogin}>Check</button>
          </span>
        </div>
        {#if settings.cookieBrowser === 'safari'}
          <div class="row">
            <span class="name">Safari needs Full Disk Access</span>
            <button class="text-button strong" onclick={() => api.openUrl('x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles')}>Open</button>
          </div>
        {/if}
        <p class="footer">For stories, highlights and private posts. Your password is never seen.</p>
      {:else}
        {#each tools as tool (tool.id)}
          <div class="row">
            <span class="name">{tool.name}</span>
            <span class="note mono selectable">{setup?.versions[tool.id] ?? '—'}</span>
          </div>
        {/each}
        <div class="row">
          <span class="name">Update automatically</span>
          <Toggle label="Update automatically" checked={settings.autoUpdateEngine} onchange={(v) => save({ autoUpdateEngine: v })} />
        </div>
        <div class="row">
          {#if reinstalling}
            <span class="grow"><ProgressBar fraction={overall} height={1} /></span>
          {:else}
            <span class="note mono">{engineBusy ? '…' : (engineMessage ?? `Downly ${version}`)}</span>
          {/if}
          <span class="value actions">
            <button class="text-button" onclick={() => api.openToolsFolder()}>Show</button>
            <button class="text-button" disabled={engineBusy || reinstalling} onclick={reinstall}>Reinstall</button>
            <button class="text-button strong" disabled={engineBusy || reinstalling} onclick={checkUpdates}>Update</button>
          </span>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  :global(html),
  :global(body) {
    height: auto;
    min-height: 100%;
  }

  .settings {
    min-height: 100vh;
    background: var(--bg);
  }

  .settings.browser {
    width: 520px;
    margin: 0 auto;
    box-shadow: 0 0 0 1px var(--line);
  }

  .toolbar {
    position: relative;
    height: 52px;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding-bottom: 8px;
  }

  .lights {
    position: absolute;
    left: 14px;
    top: 12px;
    display: flex;
    gap: 8px;
  }

  .lights span {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    box-shadow: inset 0 0 0 1px var(--line-strong);
  }

  .content {
    padding: 10px 28px 26px;
    display: flex;
    flex-direction: column;
  }

  .section {
    padding: 22px 0 8px;
  }

  .section:first-child {
    padding-top: 8px;
  }

  .row {
    min-height: 44px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    border-bottom: 1px solid var(--line);
  }

  .name {
    font-size: 13px;
  }

  .value {
    display: inline-flex;
    align-items: center;
    gap: 14px;
    min-width: 0;
  }

  .link {
    max-width: 260px;
    font-size: 11.5px;
    color: var(--text-2);
    transition: color 0.12s ease;
  }

  .link:hover {
    color: var(--text);
  }

  .note {
    font-size: 11.5px;
    color: var(--text-2);
    min-width: 0;
  }

  .grow {
    flex: 1;
  }

  .actions {
    gap: 18px;
  }

  .stepper {
    display: inline-flex;
    align-items: center;
    gap: 14px;
    font-size: 13px;
  }

  .stepper button {
    width: 18px;
    font-size: 15px;
    color: var(--text-2);
    transition: color 0.12s ease;
  }

  .stepper button:hover:not(:disabled) {
    color: var(--text);
  }

  .stepper button:disabled {
    opacity: 0.3;
  }

  .footer {
    margin: 12px 0 0;
    font-size: 12px;
    color: var(--text-2);
  }
</style>

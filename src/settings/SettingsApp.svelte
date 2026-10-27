<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { CircleCheck, CircleUser, Folder, Minus, Package, Plus, Settings as Gear, SlidersHorizontal, TriangleAlert } from '@lucide/svelte';
  import Popup from './Popup.svelte';
  import Toggle from './Toggle.svelte';
  import ProgressBar from '../components/ProgressBar.svelte';
  import { api, isTauri, listen, resizeWindow, showCurrentWindow, toError } from '../lib/api';
  import { audioFormats, homePath, tierCaption, tierLabel } from '../lib/format';
  import type { AudioFormat, BrowserInfo, CookieBrowser, FilenameStyle, Mode, Settings, SetupView, ToolId, VideoContainer } from '../lib/types';

  type Tab = 'general' | 'formats' | 'accounts' | 'engine';

  const tabs: { id: Tab; title: string; icon: typeof Gear }[] = [
    { id: 'general', title: 'General', icon: Gear },
    { id: 'formats', title: 'Formats', icon: SlidersHorizontal },
    { id: 'accounts', title: 'Accounts', icon: CircleUser },
    { id: 'engine', title: 'Engine', icon: Package },
  ];

  const initialTab = (new URLSearchParams(location.search).get('tab') as Tab) ?? 'general';
  let tab = $state<Tab>(tabs.some((t) => t.id === initialTab) ? initialTab : 'general');
  let settings = $state<Settings | null>(null);
  let setup = $state<SetupView | null>(null);
  let version = $state('');
  let browsers = $state<BrowserInfo[]>([]);
  let content: HTMLElement | undefined = $state();

  let loginStatus = $state<{ good: boolean; text: string } | null>(null);
  let checkingLogin = $state(false);
  let engineMessage = $state<string | null>(null);
  let engineBusy = $state(false);

  const tools: { id: ToolId; name: string; purpose: string }[] = [
    { id: 'ytdlp', name: 'yt-dlp', purpose: 'Finds and downloads the media' },
    { id: 'ffmpeg', name: 'FFmpeg', purpose: 'Merges video with sound and converts' },
    { id: 'ffprobe', name: 'FFprobe', purpose: 'Checks every finished file' },
    { id: 'deno', name: 'Deno', purpose: 'Unlocks YouTube’s protected formats' },
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
        engineMessage = next.error ? next.error : 'Components reinstalled.';
      }
    });
    await fit();
    await showCurrentWindow();
  });

  async function fit() {
    await tick();
    if (!content) return;
    const height = Math.ceil(content.getBoundingClientRect().height) + 78;
    await resizeWindow(600, Math.min(760, Math.max(320, height)));
  }

  async function select(next: Tab) {
    tab = next;
    loginStatus = null;
    await fit();
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
    const browser = browsers.find((b) => b.id === settings!.cookieBrowser);
    try {
      const signedIn = await api.checkInstagramLogin(settings.cookieBrowser);
      loginStatus = signedIn
        ? { good: true, text: 'Signed in to Instagram' }
        : { good: false, text: `Not signed in to Instagram in ${browser?.name ?? 'this browser'}` };
    } catch (error) {
      loginStatus = { good: false, text: toError(error).message };
    }
    checkingLogin = false;
    await fit();
  }

  async function checkUpdates() {
    engineBusy = true;
    engineMessage = 'Checking for updates…';
    try {
      const report = await api.checkEngineUpdates();
      engineMessage = report.updated ? `Updated yt-dlp to ${report.updated}.` : 'Everything is up to date.';
      if (setup) setup = { ...setup, versions: report.versions };
    } catch (error) {
      engineMessage = toError(error).message;
    }
    engineBusy = false;
    await fit();
  }

  async function reinstall() {
    engineBusy = true;
    engineMessage = 'Reinstalling components…';
    try {
      const started = await api.reinstallEngine();
      if (!started) engineBusy = false;
    } catch (error) {
      engineBusy = false;
      engineMessage = toError(error).message;
    }
    await fit();
  }

  function phaseText(id: ToolId): string | null {
    const tool = setup?.tools.find((t) => t.id === id);
    if (!setup?.running || !tool) return null;
    switch (tool.phase.state) {
      case 'waiting':
        return 'Waiting…';
      case 'downloading':
        return `${Math.round(tool.phase.fraction * 100)}%`;
      case 'installing':
        return 'Installing…';
      case 'ready':
        return tool.phase.version;
      case 'failed':
        return 'Failed';
    }
  }

  const filenameOptions: { id: FilenameStyle; title: string }[] = [
    { id: 'title', title: 'Title' },
    { id: 'titleAndId', title: 'Title [ID]' },
    { id: 'authorAndTitle', title: 'Creator – Title' },
  ];

  let browserOptions = $derived<{ id: CookieBrowser | null; title: string }[]>([
    { id: null, title: 'Don’t use a browser' },
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
    <div class="title" data-tauri-drag-region>{tabs.find((t) => t.id === tab)?.title}</div>
    <div class="tabs" role="tablist">
      {#each tabs as item (item.id)}
        {@const Icon = item.icon}
        <button role="tab" aria-selected={tab === item.id} class:selected={tab === item.id} onclick={() => select(item.id)}>
          <Icon size={20} strokeWidth={1.7} />
          <span>{item.title}</span>
        </button>
      {/each}
    </div>
  </header>

  {#if settings}
    <div class="content" bind:this={content}>
      {#if tab === 'general'}
        <section>
          <h3>Downloads</h3>
          <div class="group">
            <div class="row">
              <span class="label">Save downloads to</span>
              <span class="value folder">
                <span class="folder-icon"><Folder size={15} strokeWidth={2} fill="currentColor" fill-opacity="0.18" /></span>
                <span class="path truncate" title={settings.downloadFolder}>{homePath(settings.downloadFolder)}</span>
                <button class="mac-button" onclick={chooseFolder}>Choose…</button>
              </span>
            </div>
            <div class="row">
              <span class="label">Simultaneous downloads</span>
              <span class="value stepper">
                <span class="tabular count">{settings.maxConcurrent}</span>
                <span class="steps">
                  <button aria-label="Fewer" disabled={settings.maxConcurrent <= 1} onclick={() => save({ maxConcurrent: settings!.maxConcurrent - 1 })}><Minus size={11} strokeWidth={2.6} /></button>
                  <button aria-label="More" disabled={settings.maxConcurrent >= 6} onclick={() => save({ maxConcurrent: settings!.maxConcurrent + 1 })}><Plus size={11} strokeWidth={2.6} /></button>
                </span>
              </span>
            </div>
            <div class="row">
              <span class="label">File names</span>
              <Popup label="File names" value={settings.filenameStyle} options={filenameOptions} onchange={(v) => save({ filenameStyle: v })} />
            </div>
          </div>
        </section>
        <section>
          <h3>Convenience</h3>
          <div class="group">
            <div class="row">
              <span class="label">Offer links I copy</span>
              <Toggle label="Offer links I copy" checked={settings.watchClipboard} onchange={(v) => save({ watchClipboard: v })} />
            </div>
            <div class="row">
              <span class="label">Notify me when downloads finish in the background</span>
              <Toggle label="Notifications" checked={settings.notifications} onchange={(v) => save({ notifications: v })} />
            </div>
          </div>
          <p class="footer">When you switch to Downly with a supported link on your clipboard, it offers to grab it. Nothing leaves your Mac.</p>
        </section>
      {:else if tab === 'formats'}
        <section>
          <h3>Video</h3>
          <div class="group">
            <div class="row">
              <span class="label">Start with</span>
              <Popup
                label="Start with"
                value={settings.defaultMode}
                options={[
                  { id: 'video' as Mode, title: 'Video' },
                  { id: 'audio' as Mode, title: 'Audio' },
                ]}
                onchange={(v) => save({ defaultMode: v })}
              />
            </div>
            <div class="row">
              <span class="label">Preferred quality</span>
              <Popup
                label="Preferred quality"
                value={settings.defaultQuality}
                options={qualities.map((q) => ({ id: q, title: q === 0 ? 'Best available' : `${tierLabel(q)}${q >= 2160 ? ` (${tierCaption(q)})` : ''}` }))}
                onchange={(v) => save({ defaultQuality: v })}
              />
            </div>
            <div class="row">
              <span class="label">Container</span>
              <Popup
                label="Container"
                value={settings.videoContainer}
                options={[
                  { id: 'mp4' as VideoContainer, title: 'MP4 — works everywhere' },
                  { id: 'mkv' as VideoContainer, title: 'MKV — keeps original streams' },
                ]}
                onchange={(v) => save({ videoContainer: v })}
              />
            </div>
            <div class="row">
              <span class="label">Make every video play in QuickTime & Photos</span>
              <Toggle label="QuickTime compatibility" checked={settings.appleCompatible} disabled={settings.videoContainer !== 'mp4'} onchange={(v) => save({ appleCompatible: v })} />
            </div>
            <div class="row">
              <span class="label">Prefer HDR when available</span>
              <Toggle label="Prefer HDR" checked={settings.preferHdr} onchange={(v) => save({ preferHdr: v })} />
            </div>
          </div>
          <p class="footer">YouTube only offers 1440p, 4K and 8K as VP9 or AV1. With QuickTime compatibility on, Downly converts those to HEVC using your Mac’s media engine. Every video always includes sound.</p>
        </section>
        <section>
          <h3>Audio</h3>
          <div class="group">
            <div class="row">
              <span class="label">Audio downloads</span>
              <Popup label="Audio downloads" value={settings.audioFormat} options={audioFormats.map((f) => ({ id: f.id as AudioFormat, title: `${f.title} — ${f.detail}` }))} onchange={(v) => save({ audioFormat: v })} />
            </div>
            <div class="row">
              <span class="label">Spotify songs</span>
              <Popup label="Spotify songs" value={settings.musicFormat} options={audioFormats.map((f) => ({ id: f.id as AudioFormat, title: `${f.title} — ${f.detail}` }))} onchange={(v) => save({ musicFormat: v })} />
            </div>
            <div class="row">
              <span class="label">Add cover art, title and artist</span>
              <Toggle label="Embed metadata" checked={settings.embedMetadata} onchange={(v) => save({ embedMetadata: v })} />
            </div>
          </div>
        </section>
      {:else if tab === 'accounts'}
        <section>
          <h3>Browser sign-in</h3>
          <div class="group">
            <div class="row">
              <span class="label">Use sign-in from</span>
              <Popup
                label="Use sign-in from"
                value={settings.cookieBrowser}
                options={browserOptions}
                onchange={(v) => {
                  loginStatus = null;
                  save({ cookieBrowser: v });
                }}
              />
            </div>
            <div class="row">
              <span class="label">Also use it for YouTube and other sites</span>
              <Toggle label="Use for all sites" checked={settings.alwaysUseCookies} disabled={!settings.cookieBrowser} onchange={(v) => save({ alwaysUseCookies: v })} />
            </div>
            <div class="row">
              <span class="value left">
                <button class="mac-button" disabled={!settings.cookieBrowser || checkingLogin} onclick={checkLogin}>
                  {checkingLogin ? 'Checking…' : 'Check Instagram Sign-in'}
                </button>
                {#if checkingLogin}<span class="spinner" style:--spinner="13px"></span>{/if}
                {#if loginStatus}
                  <span class="status" class:good={loginStatus.good}>
                    {#if loginStatus.good}<CircleCheck size={14} strokeWidth={2.4} />{:else}<TriangleAlert size={14} strokeWidth={2.4} />{/if}
                    {loginStatus.text}
                  </span>
                {/if}
              </span>
            </div>
          </div>
          <p class="footer">
            Instagram stories, highlights, HD profile pictures and private posts need you to be signed in. Downly borrows the session from your browser on this Mac — your password is never seen or sent anywhere. YouTube also uses it when asking for age or bot checks.
          </p>
        </section>
        {#if settings.cookieBrowser === 'safari'}
          <section>
            <div class="group">
              <div class="row">
                <span class="label small">Safari keeps its cookies private. Give Downly Full Disk Access to use them.</span>
                <button class="mac-button" onclick={() => api.openUrl('x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles')}>Open Privacy Settings</button>
              </div>
            </div>
          </section>
        {/if}
      {:else}
        <section>
          <h3>Components</h3>
          <div class="group">
            {#each tools as tool (tool.id)}
              <div class="row">
                <span class="label stacked">
                  <span>{tool.name}</span>
                  <span class="caption">{tool.purpose}</span>
                </span>
                <span class="version tabular selectable">{phaseText(tool.id) ?? setup?.versions[tool.id] ?? 'Not installed'}</span>
              </div>
            {/each}
          </div>
        </section>
        <section>
          <h3>Updates</h3>
          <div class="group">
            <div class="row">
              <span class="label">Keep the download engine up to date</span>
              <Toggle label="Auto update" checked={settings.autoUpdateEngine} onchange={(v) => save({ autoUpdateEngine: v })} />
            </div>
            <div class="row">
              <span class="value left">
                <button class="mac-button" disabled={engineBusy || reinstalling} onclick={checkUpdates}>Check for Updates</button>
                <button class="mac-button" disabled={engineBusy || reinstalling} onclick={reinstall}>Reinstall Components</button>
              </span>
              <button class="icon-button" title="Show components in Finder" aria-label="Show components in Finder" onclick={() => api.openToolsFolder()}>
                <Folder size={15} strokeWidth={2} />
              </button>
            </div>
            {#if reinstalling}
              <div class="row">
                <span class="value left grow">
                  <span class="spinner" style:--spinner="13px"></span>
                  <span class="secondary">Reinstalling components…</span>
                  <span class="grow"><ProgressBar fraction={overall} height={4} /></span>
                </span>
              </div>
            {:else if engineMessage}
              <div class="row">
                <span class="value left">
                  {#if engineBusy}<span class="spinner" style:--spinner="13px"></span>{/if}
                  <span class="secondary">{engineMessage}</span>
                </span>
              </div>
            {/if}
          </div>
          <p class="footer">Sites change often. Downly quietly refreshes yt-dlp once a day so downloads keep working. Downly {version}</p>
        </section>
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
    background: var(--window);
  }

  .settings.browser {
    width: 600px;
    margin: 0 auto;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 0 0 1px var(--hairline);
  }

  .toolbar {
    position: relative;
    height: 78px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-end;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--separator);
    background: color-mix(in srgb, var(--window-solid) 40%, transparent);
  }

  .lights {
    position: absolute;
    left: 12px;
    top: 10px;
    display: flex;
    gap: 8px;
  }

  .lights span {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.12);
  }

  .lights span:nth-child(1) {
    background: #ff5f57;
  }

  .lights span:nth-child(2) {
    background: #febc2e;
  }

  .lights span:nth-child(3) {
    background: #28c840;
  }

  .title {
    position: absolute;
    top: 7px;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
    pointer-events: none;
  }

  .tabs {
    display: flex;
    gap: 4px;
  }

  .tabs button {
    width: 72px;
    height: 44px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 3px;
    border-radius: 7px;
    font-size: 11px;
    color: var(--text-2);
    transition:
      background 0.15s ease,
      color 0.15s ease;
  }

  .tabs button:hover {
    background: var(--fill);
  }

  .tabs button.selected {
    color: var(--accent);
    background: var(--fill-2);
  }

  .content {
    padding: 18px 22px 22px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  section {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  h3 {
    margin: 0 0 0 8px;
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
  }

  .group {
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--hairline);
    padding: 0 12px;
  }

  .row {
    min-height: 40px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 7px 0;
  }

  .row + .row {
    border-top: 1px solid var(--separator);
  }

  .label {
    font-size: 13px;
    min-width: 0;
  }

  .label.small {
    font-size: 12px;
    color: var(--text-2);
  }

  .label.stacked {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .caption {
    font-size: 11px;
    color: var(--text-2);
  }

  .value {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  .value.left {
    justify-content: flex-start;
  }

  .grow {
    flex: 1;
  }

  .folder {
    max-width: 330px;
  }

  .folder-icon {
    display: flex;
    color: #4a9ff5;
    flex-shrink: 0;
  }

  .path {
    color: var(--text-2);
    min-width: 0;
  }

  .stepper .count {
    min-width: 14px;
    text-align: right;
  }

  .steps {
    display: inline-flex;
    flex-direction: column;
    border-radius: 6px;
    overflow: hidden;
    background: var(--card-solid);
    box-shadow:
      0 0.5px 1.5px rgba(0, 0, 0, 0.2),
      0 0 0 0.5px rgba(0, 0, 0, 0.1);
  }

  .steps button {
    width: 20px;
    height: 12px;
    display: grid;
    place-items: center;
    color: var(--text-2);
  }

  .steps button:active:not(:disabled) {
    background: var(--fill-2);
  }

  .steps button:disabled {
    opacity: 0.35;
  }

  .steps button + button {
    border-top: 0.5px solid var(--separator);
  }

  .mac-button {
    height: 24px;
    padding: 0 12px;
    border-radius: 6px;
    font-size: 13px;
    white-space: nowrap;
    background: var(--card-solid);
    box-shadow:
      0 0.5px 1.5px rgba(0, 0, 0, 0.2),
      0 0 0 0.5px rgba(0, 0, 0, 0.1);
  }

  @media (prefers-color-scheme: dark) {
    .mac-button,
    .steps {
      background: rgba(255, 255, 255, 0.12);
      box-shadow:
        0 0.5px 1px rgba(0, 0, 0, 0.4),
        inset 0 0.5px 0 rgba(255, 255, 255, 0.08);
    }
  }

  .mac-button:active:not(:disabled) {
    filter: brightness(0.93);
  }

  .mac-button:disabled {
    opacity: 0.45;
  }

  .status {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    color: var(--orange);
  }

  .status.good {
    color: var(--green);
  }

  .version {
    font-size: 12.5px;
    color: var(--text-2);
  }

  .footer {
    margin: 2px 8px 0;
    font-size: 11.5px;
    line-height: 1.45;
    color: var(--text-2);
  }
</style>

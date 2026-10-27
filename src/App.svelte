<script lang="ts">
  import { onMount } from 'svelte';
  import { fade, fly } from 'svelte/transition';
  import ClipboardPill from './components/ClipboardPill.svelte';
  import Downloads from './components/Downloads.svelte';
  import DropOverlay from './components/DropOverlay.svelte';
  import Hero from './components/Hero.svelte';
  import LinkBar from './components/LinkBar.svelte';
  import Setup from './components/Setup.svelte';
  import TopBar from './components/TopBar.svelte';
  import ErrorCard from './components/cards/ErrorCard.svelte';
  import GalleryCard from './components/cards/GalleryCard.svelte';
  import LoadingCard from './components/cards/LoadingCard.svelte';
  import MusicCard from './components/cards/MusicCard.svelte';
  import PlaylistCard from './components/cards/PlaylistCard.svelte';
  import VideoCard from './components/cards/VideoCard.svelte';
  import { isTauri } from './lib/api';
  import { app } from './lib/state.svelte';

  let scrolled = $state(false);
  let dragDepth = 0;

  onMount(() => {
    app.init().then(applyDemo);
  });

  async function applyDemo() {
    if (isTauri) return;
    const mock = await import('./lib/mock');
    const params = new URLSearchParams(location.search);
    const demo = params.get('demo');
    const initial = mock.initialAnalysis();
    if (initial) {
      app.input = initial.url;
      app.analysis = { status: 'loaded', link: { url: initial.url, platform: initial.analysis.summary.platform, kind: { type: 'generic' }, playlistId: null, isMusic: false }, analysis: initial.analysis, key: 1 };
    } else if (demo === 'error') {
      app.input = 'https://www.instagram.com/stories/private.account/fail';
      app.submit(app.input);
    } else if (demo === 'loading') {
      app.input = 'https://www.youtube.com/watch?v=aqz-KE-bpKQ';
      app.submit(app.input);
    } else if (demo === 'clipboard') {
      app.checkClipboard();
    }
  }

  function onkeydown(event: KeyboardEvent) {
    const target = event.target as HTMLElement | null;
    const typing = target?.tagName === 'INPUT' || target?.tagName === 'TEXTAREA' || target?.tagName === 'SELECT';
    if (event.key === 'Escape' && app.analysis.status !== 'idle') {
      app.clear();
    } else if (event.key === 'Enter' && !typing && target?.tagName !== 'BUTTON') {
      document.querySelector<HTMLButtonElement>('[data-default-action]:not(:disabled)')?.click();
    } else if (event.key.toLowerCase() === 'v' && event.metaKey && !typing) {
      event.preventDefault();
      app.pasteLink();
    }
  }

  function extract(data: DataTransfer | null): string {
    if (!data) return '';
    const uri = data.getData('text/uri-list').split('\n').find((line) => line && !line.startsWith('#'));
    return uri || data.getData('text/plain') || data.getData('URL') || '';
  }

  function ondragenter(event: DragEvent) {
    if (!app.setup.ready) return;
    event.preventDefault();
    dragDepth++;
    app.dropActive = true;
  }

  function ondragleave() {
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) app.dropActive = false;
  }

  function ondragover(event: DragEvent) {
    if (!app.setup.ready) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  }

  function ondrop(event: DragEvent) {
    event.preventDefault();
    dragDepth = 0;
    app.dropActive = false;
    const text = extract(event.dataTransfer).trim();
    if (text) {
      app.input = text;
      app.submit(text);
    }
  }
</script>

<svelte:window {onkeydown} {ondragenter} {ondragleave} {ondragover} {ondrop} />

<div class="window">
  <div class="glow" aria-hidden="true"></div>
  <TopBar {scrolled} />
  {#if !app.booted}
    <div class="center"><span class="spinner"></span></div>
  {:else if !app.setup.ready}
    <div class="setup" in:fade={{ duration: 250 }}><Setup /></div>
  {:else}
    <main class="scroll" onscroll={(e) => (scrolled = (e.currentTarget as HTMLElement).scrollTop > 2)} in:fade={{ duration: 300 }}>
      <div class="content">
        <LinkBar />
        {#if app.clipboard && app.analysis.status === 'idle'}
          <div transition:fly={{ y: -8, duration: 260 }}><ClipboardPill link={app.clipboard} /></div>
        {/if}

        {#if app.analysis.status === 'idle'}
          {#if app.downloads.length === 0}
            <div in:fade={{ duration: 300 }}><Hero /></div>
          {/if}
        {:else if app.analysis.status === 'loading'}
          <div in:fly={{ y: -10, duration: 320 }}>
            <LoadingCard link={app.analysis.link} preview={app.analysis.preview} />
          </div>
        {:else if app.analysis.status === 'failed'}
          <div in:fade={{ duration: 200 }}>
            <ErrorCard link={app.analysis.link} error={app.analysis.error} />
          </div>
        {:else}
          {#key app.analysis.key}
            <div class="appear">
              {#if app.analysis.analysis.type === 'video'}
                <VideoCard video={app.analysis.analysis} />
              {:else if app.analysis.analysis.type === 'playlist'}
                <PlaylistCard playlist={app.analysis.analysis} link={app.analysis.link} />
              {:else if app.analysis.analysis.type === 'music'}
                <MusicCard music={app.analysis.analysis} />
              {:else}
                <GalleryCard gallery={app.analysis.analysis} />
              {/if}
            </div>
          {/key}
        {/if}

        {#if app.downloads.length > 0}
          <Downloads />
        {/if}
      </div>
    </main>
  {/if}
  {#if app.dropActive}<DropOverlay />{/if}
</div>

<style>
  .window {
    position: relative;
    height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--window);
    overflow: hidden;
  }

  .glow {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 380px;
    pointer-events: none;
    background:
      radial-gradient(45% 180px at 22% 0, var(--glow-a), transparent 72%),
      radial-gradient(42% 170px at 80% 0, var(--glow-b), transparent 72%),
      radial-gradient(35% 150px at 50% 0, var(--glow-c), transparent 72%);
  }

  .center {
    flex: 1;
    display: grid;
    place-items: center;
  }

  .setup {
    flex: 1;
    display: flex;
  }

  .scroll {
    position: absolute;
    inset: 0;
    overflow-y: auto;
    overflow-x: hidden;
    padding-top: 52px;
  }

  .content {
    position: relative;
    max-width: 780px;
    margin: 0 auto;
    padding: 6px 28px 28px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .appear {
    animation: appear 0.42s var(--ease-out);
    transform-origin: top center;
  }

  @keyframes appear {
    from {
      opacity: 0;
      transform: scale(0.985) translateY(-4px);
    }
    to {
      opacity: 1;
      transform: none;
    }
  }
</style>

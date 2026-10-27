<script lang="ts">
  import { onMount } from 'svelte';
  import { fade } from 'svelte/transition';
  import ClipboardPill from './components/ClipboardPill.svelte';
  import Downloads from './components/Downloads.svelte';
  import DropOverlay from './components/DropOverlay.svelte';
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

  let empty = $derived(app.analysis.status === 'idle' && app.downloads.length === 0);

  onMount(() => {
    app.init().then(applyDemo);
  });

  async function applyDemo() {
    if (isTauri) return;
    const mock = await import('./lib/mock');
    const demo = new URLSearchParams(location.search).get('demo');
    const initial = mock.initialAnalysis();
    if (initial) {
      app.input = initial.url;
      app.analysis = {
        status: 'loaded',
        link: { url: initial.url, platform: initial.analysis.summary.platform, kind: { type: 'generic' }, playlistId: null, isMusic: false },
        analysis: initial.analysis,
        key: 1,
      };
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
    const typing = target?.tagName === 'INPUT' || target?.tagName === 'SELECT';
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
  <TopBar {scrolled} />
  {#if !app.booted}
    <div class="center"></div>
  {:else if !app.setup.ready}
    <div class="center" in:fade={{ duration: 200 }}><Setup /></div>
  {:else}
    <main class="scroll" onscroll={(e) => (scrolled = (e.currentTarget as HTMLElement).scrollTop > 2)}>
      <div class="content" class:empty>
        <LinkBar />
        {#if app.clipboard && app.analysis.status === 'idle'}
          <div transition:fade={{ duration: 150 }}><ClipboardPill link={app.clipboard} /></div>
        {/if}

        {#if app.analysis.status === 'loading'}
          <LoadingCard link={app.analysis.link} preview={app.analysis.preview} />
        {:else if app.analysis.status === 'failed'}
          <ErrorCard link={app.analysis.link} error={app.analysis.error} />
        {:else if app.analysis.status === 'loaded'}
          {#key app.analysis.key}
            {#if app.analysis.analysis.type === 'video'}
              <VideoCard video={app.analysis.analysis} />
            {:else if app.analysis.analysis.type === 'playlist'}
              <PlaylistCard playlist={app.analysis.analysis} link={app.analysis.link} />
            {:else if app.analysis.analysis.type === 'music'}
              <MusicCard music={app.analysis.analysis} />
            {:else}
              <GalleryCard gallery={app.analysis.analysis} />
            {/if}
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
    background: var(--bg);
  }

  .center {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .scroll {
    position: absolute;
    inset: 0;
    overflow-y: auto;
    overflow-x: hidden;
    padding-top: 52px;
  }

  .content {
    max-width: 640px;
    margin: 0 auto;
    padding: 4px 36px 36px;
    display: flex;
    flex-direction: column;
    gap: 26px;
    transition: padding-top 0.45s var(--ease);
  }

  .content.empty {
    padding-top: calc(50vh - 92px);
  }
</style>

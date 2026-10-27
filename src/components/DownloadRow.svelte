<script lang="ts">
  import { Folder, Play, RotateCw, Search, X } from '@lucide/svelte';
  import ProgressBar from './ProgressBar.svelte';
  import Thumb from './Thumb.svelte';
  import { api, popupMenu, type MenuEntry } from '../lib/api';
  import { bytes, eta, speed } from '../lib/format';
  import type { DownloadItem } from '../lib/types';

  let { item }: { item: DownloadItem } = $props();

  let square = $derived(item.job.platform === 'spotify' || item.job.kind.type === 'audio' || item.job.kind.type === 'spotify');
  let active = $derived(item.state === 'queued' || item.state === 'running');
  let finished = $derived(item.state === 'finished');
  let multiple = $derived(item.files.length > 1);

  let status = $derived.by(() => {
    switch (item.state) {
      case 'queued':
        return 'Waiting';
      case 'cancelled':
        return 'Cancelled';
      case 'failed':
        return item.error ?? 'Failed';
      case 'finished':
        return [item.job.detail, bytes(item.fileSize), item.files.length && !item.filesExist ? 'Missing' : null].filter(Boolean).join('  ·  ');
    }
    const phase = item.phase;
    if (phase?.kind === 'preparing') return phase.message.includes('Downloading') && item.note ? item.note : phase.message;
    if (phase?.kind === 'processing') return item.fraction ? `${phase.message}  ${Math.round(item.fraction * 100)}%` : phase.message;
    return [item.fraction != null ? `${Math.round(item.fraction * 100)}%` : null, speed(item.speed), eta(item.eta)].filter(Boolean).join('  ·  ') || 'Downloading';
  });

  function menu(event: MouseEvent) {
    event.preventDefault();
    const entries: MenuEntry[] = [];
    if (finished) {
      entries.push({ label: 'Open', action: () => api.open(item.id), enabled: item.filesExist });
      entries.push({ label: 'Show in Finder', action: () => api.reveal(item.id), enabled: item.filesExist });
      entries.push({ separator: true });
    }
    if (item.sourceUrl) {
      const url = item.sourceUrl;
      entries.push({ label: 'Copy Link', action: () => api.copyText(url) });
      entries.push({ label: 'Open Original Page', action: () => api.openUrl(url) });
      entries.push({ separator: true });
    }
    if (active) {
      entries.push({ label: 'Cancel', action: () => api.cancelDownload(item.id) });
    } else {
      entries.push({ label: finished ? 'Download Again' : 'Try Again', action: () => api.retryDownload(item.id) });
      entries.push({ label: 'Remove', action: () => api.removeDownload(item.id) });
    }
    popupMenu(entries);
  }
</script>

<div class="row" class:dim={item.state === 'cancelled'} role="listitem" oncontextmenu={menu} ondblclick={() => finished && item.filesExist && api.open(item.id)}>
  <Thumb src={item.job.thumbnail} width={square ? 34 : 60} height={34} />
  <div class="body">
    <div class="title truncate">{item.job.title}</div>
    <div class="status mono truncate" title={item.state === 'failed' ? (item.hint ?? item.error ?? '') : ''}>{status}</div>
  </div>
  <div class="actions">
    {#if active}
      <button class="icon-button" title="Cancel" aria-label="Cancel" onclick={() => api.cancelDownload(item.id)}><X size={14} strokeWidth={1.5} /></button>
    {:else if finished}
      <button class="icon-button" title="Open" aria-label="Open" disabled={!item.filesExist} onclick={() => api.open(item.id)}>
        {#if multiple}<Folder size={14} strokeWidth={1.5} />{:else}<Play size={13} strokeWidth={1.5} />{/if}
      </button>
      <button class="icon-button" title="Show in Finder" aria-label="Show in Finder" disabled={!item.filesExist} onclick={() => api.reveal(item.id)}><Search size={14} strokeWidth={1.5} /></button>
    {:else}
      <button class="icon-button" title="Try again" aria-label="Try again" onclick={() => api.retryDownload(item.id)}><RotateCw size={13} strokeWidth={1.5} /></button>
      <button class="icon-button" title="Remove" aria-label="Remove" onclick={() => api.removeDownload(item.id)}><X size={14} strokeWidth={1.5} /></button>
    {/if}
  </div>
  {#if item.state === 'running'}
    <div class="progress"><ProgressBar fraction={item.phase?.kind === 'preparing' ? null : item.fraction} height={1} /></div>
  {/if}
</div>

<style>
  .row {
    position: relative;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px 0;
  }

  .row.dim {
    opacity: 0.5;
  }

  .body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .title {
    font-size: 13px;
    filter: grayscale(1);
  }

  .status {
    font-size: 11px;
    color: var(--text-2);
  }

  .actions {
    display: flex;
    flex-shrink: 0;
    opacity: 0;
    transition: opacity 0.15s ease;
  }

  .row:hover .actions,
  .actions:focus-within {
    opacity: 1;
  }

  .progress {
    position: absolute;
    left: 0;
    right: 0;
    bottom: -1px;
  }
</style>

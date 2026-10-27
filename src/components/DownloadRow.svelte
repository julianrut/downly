<script lang="ts">
  import { CircleAlert, CircleCheck, Clock, CircleX, Folder, Play, RotateCw, Search, Trash2, X } from '@lucide/svelte';
  import PlatformBadge from './PlatformBadge.svelte';
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

  let running = $derived.by(() => {
    const phase = item.phase;
    if (phase?.kind === 'preparing') {
      if (item.note && phase.message.includes('Downloading')) return item.note;
      return `${phase.message}…`;
    }
    if (phase?.kind === 'processing') {
      if (item.fraction && item.fraction > 0) return `${phase.message}… ${Math.round(item.fraction * 100)}%`;
      return `${phase.message}…`;
    }
    const parts: string[] = [];
    const done = bytes(item.downloaded);
    const total = bytes(item.total);
    if (done && total) parts.push(`${done} of ${total}`);
    else if (item.fraction != null) parts.push(`${Math.round(item.fraction * 100)}%`);
    else parts.push('Downloading');
    const rate = speed(item.speed);
    if (rate) parts.push(rate);
    const left = eta(item.eta);
    if (left) parts.push(left);
    return parts.join(' · ');
  });

  let finishedText = $derived(
    [item.job.detail, bytes(item.fileSize), item.files.length && !item.filesExist ? 'moved or deleted' : null].filter(Boolean).join(' · '),
  );

  let barFraction = $derived(item.phase?.kind === 'downloading' || item.phase?.kind === 'processing' ? item.fraction : item.phase?.kind === 'preparing' ? null : item.fraction);

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
      entries.push({ label: 'Remove from List', action: () => api.removeDownload(item.id) });
    }
    popupMenu(entries);
  }
</script>

<div
  class="row"
  role="listitem"
  oncontextmenu={menu}
  ondblclick={() => finished && item.filesExist && api.open(item.id)}
>
  <div class="art">
    <Thumb src={item.job.thumbnail} width={square ? 46 : 64} height={square ? 46 : 40} radius={8} />
    <span class="badge"><PlatformBadge platform={item.job.platform} size={15} /></span>
  </div>
  <div class="body">
    <div class="title truncate">{item.job.title}</div>
    {#if item.state === 'queued'}
      <div class="status"><Clock size={11} strokeWidth={2.2} /> Waiting to start…</div>
    {:else if item.state === 'running'}
      <div class="status tabular truncate">{running}</div>
      <div class="bar"><ProgressBar fraction={barFraction} height={4} /></div>
    {:else if item.state === 'finished'}
      <div class="status">
        <span class="ok"><CircleCheck size={12} strokeWidth={2.4} /></span>
        <span class="truncate">{finishedText}</span>
      </div>
    {:else if item.state === 'failed'}
      <div class="status failed" title={item.hint ?? item.error ?? ''}>
        <span class="warn"><CircleAlert size={12} strokeWidth={2.4} /></span>
        <span class="clamp">{item.error}</span>
      </div>
    {:else}
      <div class="status"><CircleX size={11} strokeWidth={2.2} /> Cancelled</div>
    {/if}
  </div>
  <div class="actions">
    {#if active}
      <button class="icon-button" title="Cancel" aria-label="Cancel" onclick={() => api.cancelDownload(item.id)}>
        <X size={14} strokeWidth={2.4} />
      </button>
    {:else if finished}
      <button class="icon-button" title={multiple ? 'Open folder' : 'Open'} aria-label="Open" disabled={!item.filesExist} onclick={() => api.open(item.id)}>
        {#if multiple}<Folder size={14} strokeWidth={2.2} />{:else}<Play size={13} strokeWidth={0} fill="currentColor" />{/if}
      </button>
      <button class="icon-button" title="Show in Finder" aria-label="Show in Finder" disabled={!item.filesExist} onclick={() => api.reveal(item.id)}>
        <Search size={14} strokeWidth={2.4} />
      </button>
    {:else}
      <button class="icon-button" title="Try again" aria-label="Try again" onclick={() => api.retryDownload(item.id)}>
        <RotateCw size={14} strokeWidth={2.4} />
      </button>
      <button class="icon-button" title="Remove" aria-label="Remove" onclick={() => api.removeDownload(item.id)}>
        <Trash2 size={14} strokeWidth={2.2} />
      </button>
    {/if}
  </div>
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 9px 10px;
    border-radius: 12px;
    transition: background 0.15s ease;
  }

  .row:hover {
    background: var(--fill);
  }

  .art {
    position: relative;
    width: 64px;
    height: 46px;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .badge {
    position: absolute;
    right: -3px;
    bottom: -2px;
    display: flex;
    filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.3));
  }

  .body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .title {
    font-size: 13.5px;
    font-weight: 500;
    letter-spacing: -0.005em;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11.5px;
    color: var(--text-2);
    min-width: 0;
  }

  .ok {
    display: flex;
    color: var(--green);
    flex-shrink: 0;
  }

  .warn {
    display: flex;
    color: var(--orange);
    flex-shrink: 0;
  }

  .clamp {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .bar {
    padding-top: 2px;
  }

  .actions {
    display: flex;
    gap: 2px;
    flex-shrink: 0;
  }
</style>

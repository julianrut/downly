<script lang="ts">
  import { X } from '@lucide/svelte';
  import PlatformBadge from './PlatformBadge.svelte';
  import Thumb from './Thumb.svelte';
  import { duration as formatDuration, platformNames } from '../lib/format';
  import { app } from '../lib/state.svelte';
  import type { MediaSummary } from '../lib/types';

  type Shape = 'wide' | 'square' | 'portrait' | 'circle';

  let {
    summary,
    badge = null,
    shape = 'wide',
    closable = true,
  }: { summary: MediaSummary; badge?: string | null; shape?: Shape; closable?: boolean } = $props();

  const sizes: Record<Shape, [number, number]> = {
    wide: [176, 99],
    square: [104, 104],
    portrait: [74, 116],
    circle: [96, 96],
  };

  let length = $derived(formatDuration(summary.duration));
</script>

<div class="header">
  <div class="art" class:ring={shape === 'circle'}>
    <Thumb src={summary.thumbnail} width={sizes[shape][0]} height={sizes[shape][1]} round={shape === 'circle'} />
    {#if length && (shape === 'wide' || shape === 'portrait')}
      <span class="duration tabular">{length}</span>
    {/if}
  </div>
  <div class="text">
    <div class="meta">
      <PlatformBadge platform={summary.platform} size={15} />
      <span>{platformNames[summary.platform]}</span>
      {#if badge}<span class="dot">·</span><span class="badge">{badge}</span>{/if}
    </div>
    <h2 class="title selectable">{summary.title}</h2>
    {#if summary.author}<div class="author truncate">{summary.author}</div>{/if}
  </div>
  {#if closable}
    <button class="icon-button close" style:--size="26px" title="Close" aria-label="Close" onclick={() => app.clear()}>
      <X size={14} strokeWidth={2.4} />
    </button>
  {/if}
</div>

<style>
  .header {
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .art {
    position: relative;
    flex-shrink: 0;
    border-radius: 12px;
    box-shadow: 0 6px 16px -6px rgba(0, 0, 0, 0.28);
  }

  .art.ring {
    padding: 4px;
    border-radius: 50%;
    box-shadow: none;
    background:
      linear-gradient(var(--card-solid), var(--card-solid)) padding-box,
      linear-gradient(45deg, #feda75, #fa7e1e, #d62976, #962fbf) border-box;
    border: 3px solid transparent;
  }

  .duration {
    position: absolute;
    right: 6px;
    bottom: 6px;
    padding: 1px 6px;
    border-radius: 999px;
    font-size: 10.5px;
    font-weight: 600;
    color: #fff;
    background: rgba(0, 0, 0, 0.66);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
  }

  .text {
    flex: 1;
    min-width: 0;
    padding-top: 2px;
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .meta {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--text-2);
  }

  .dot {
    color: var(--text-3);
  }

  .badge {
    font-weight: 500;
  }

  .title {
    margin: 0;
    font-size: 17px;
    font-weight: 600;
    letter-spacing: -0.015em;
    line-height: 1.28;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    cursor: text;
  }

  .author {
    font-size: 13px;
    color: var(--text-2);
  }

  .close {
    margin: -4px -6px 0 0;
  }
</style>

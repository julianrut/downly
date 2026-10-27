<script lang="ts">
  import { X } from '@lucide/svelte';
  import Thumb from './Thumb.svelte';
  import { duration as formatDuration } from '../lib/format';
  import { app } from '../lib/state.svelte';
  import type { MediaSummary } from '../lib/types';

  type Shape = 'wide' | 'square' | 'portrait' | 'circle';

  let { summary, extra = null, shape = 'wide' }: { summary: MediaSummary; extra?: string | null; shape?: Shape } = $props();

  const sizes: Record<Shape, [number, number]> = {
    wide: [112, 63],
    square: [63, 63],
    portrait: [44, 70],
    circle: [63, 63],
  };

  let meta = $derived([summary.author, formatDuration(summary.duration), extra].filter(Boolean).join('  ·  '));
</script>

<div class="header">
  <Thumb src={summary.thumbnail} width={sizes[shape][0]} height={sizes[shape][1]} round={shape === 'circle'} />
  <div class="text">
    <div class="title selectable">{summary.title}</div>
    {#if meta}<div class="meta mono truncate">{meta}</div>{/if}
  </div>
  <button class="icon-button" title="Close" aria-label="Close" onclick={() => app.clear()}>
    <X size={15} strokeWidth={1.5} />
  </button>
</div>

<style>
  .header {
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .title {
    font-size: 16px;
    font-weight: 500;
    letter-spacing: -0.01em;
    line-height: 1.3;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    cursor: text;
    filter: grayscale(1);
  }

  .meta {
    font-size: 11px;
    color: var(--text-2);
  }

  .icon-button {
    margin: -5px -7px 0 0;
  }
</style>

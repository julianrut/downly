<script lang="ts">
  import { thumb } from '../lib/api';
  import { Image } from '@lucide/svelte';

  let {
    src,
    width,
    height,
    radius = 12,
    round = false,
    fit = 'cover',
  }: {
    src: string | null | undefined;
    width: number | string;
    height: number | string;
    radius?: number;
    round?: boolean;
    fit?: 'cover' | 'contain';
  } = $props();

  let loaded = $state(false);
  let failed = $state(false);
  let resolved = $derived(thumb(src));

  $effect(() => {
    resolved;
    loaded = false;
    failed = false;
  });

  const size = (value: number | string) => (typeof value === 'number' ? `${value}px` : value);
</script>

<div
  class="thumb"
  style:width={size(width)}
  style:height={size(height)}
  style:border-radius={round ? '50%' : `${radius}px`}
>
  {#if resolved && !failed}
    <img
      src={resolved}
      alt=""
      draggable="false"
      decoding="async"
      class:loaded
      style:object-fit={fit}
      onload={() => (loaded = true)}
      onerror={() => (failed = true)}
    />
  {/if}
  {#if !resolved || failed}
    <div class="placeholder"><Image size={Math.min(22, Number(height) / 3 || 16)} strokeWidth={1.6} /></div>
  {/if}
</div>

<style>
  .thumb {
    position: relative;
    overflow: hidden;
    flex-shrink: 0;
    background: var(--fill-2);
    isolation: isolate;
  }

  .thumb::after {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
    box-shadow: inset 0 0 0 1px var(--hairline);
    pointer-events: none;
  }

  img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0;
    transition: opacity 0.35s ease;
  }

  img.loaded {
    opacity: 1;
  }

  .placeholder {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-3);
  }
</style>

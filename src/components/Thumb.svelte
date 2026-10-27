<script lang="ts">
  import { thumb } from '../lib/api';

  let {
    src,
    width,
    height,
    radius = 2,
    round = false,
  }: {
    src: string | null | undefined;
    width: number | string;
    height: number | string;
    radius?: number;
    round?: boolean;
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

<div class="thumb" style:width={size(width)} style:height={size(height)} style:border-radius={round ? '50%' : `${radius}px`}>
  {#if resolved && !failed}
    <img src={resolved} alt="" draggable="false" decoding="async" class:loaded onload={() => (loaded = true)} onerror={() => (failed = true)} />
  {/if}
</div>

<style>
  .thumb {
    position: relative;
    overflow: hidden;
    flex-shrink: 0;
    background: var(--fill);
  }

  img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    opacity: 0;
  }

  img.loaded {
    opacity: 1;
  }

  img {
    filter: grayscale(1) contrast(1.04);
    transition:
      opacity 0.25s ease,
      filter 0.35s ease;
  }

  :global(:hover) > .thumb img,
  .thumb:hover img {
    filter: none;
  }
</style>

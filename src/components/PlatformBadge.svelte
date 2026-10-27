<script lang="ts">
  import type { Platform } from '../lib/types';
  import { platformNames } from '../lib/format';

  let { platform, size = 18 }: { platform: Platform; size?: number } = $props();
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.7"
  stroke-linecap="round"
  stroke-linejoin="round"
  role="img"
  aria-label={platformNames[platform]}
>
  {#if platform === 'youtube'}
    <rect x="2.5" y="5" width="19" height="14" rx="4.5" />
    <path d="M10.2 9.2v5.6l4.8-2.8z" fill="currentColor" stroke="none" />
  {:else if platform === 'spotify'}
    <circle cx="12" cy="12" r="9.5" />
    <path d="M7.2 9.6c3.2-1 6.9-.7 9.6.9M7.8 12.6c2.6-.8 5.6-.5 7.8.7M8.4 15.5c2-.5 4.2-.3 5.9.6" />
  {:else if platform === 'instagram'}
    <rect x="3" y="3" width="18" height="18" rx="5.5" />
    <circle cx="12" cy="12" r="4" />
    <circle cx="17.2" cy="6.8" r="0.9" fill="currentColor" stroke="none" />
  {:else if platform === 'tiktok'}
    <path d="M14.5 3v11.2a3.8 3.8 0 1 1-3.8-3.8" />
    <path d="M14.5 3c.4 2.6 2.2 4.4 4.8 4.7" />
  {:else}
    <circle cx="12" cy="12" r="9.5" />
    <path d="M2.5 12h19M12 2.5c2.6 2.6 3.8 5.8 3.8 9.5s-1.2 6.9-3.8 9.5c-2.6-2.6-3.8-5.8-3.8-9.5S9.4 5.1 12 2.5z" />
  {/if}
</svg>

<style>
  svg {
    display: block;
    flex-shrink: 0;
  }
</style>

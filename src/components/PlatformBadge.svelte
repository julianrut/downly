<script lang="ts">
  import type { Platform } from '../lib/types';
  import { platformNames } from '../lib/format';

  let { platform, size = 20 }: { platform: Platform; size?: number } = $props();
  const uid = Math.random().toString(36).slice(2, 8);
  const note =
    'M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z';
</script>

<svg
  class="badge"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  role="img"
  aria-label={platformNames[platform]}
>
  {#if platform === 'youtube'}
    <rect x="0" y="3.1" width="24" height="17.8" rx="6.2" fill="#FF0033" />
    <path d="M9.6 8.2v7.6l6.6-3.8z" fill="#fff" />
  {:else if platform === 'spotify'}
    <circle cx="12" cy="12" r="12" fill="#1ED760" />
    <g fill="none" stroke="rgba(0,0,0,0.86)" stroke-linecap="round">
      <path d="M5.4 8.9c4.3-1.4 9.4-1 13.3 1.2" stroke-width="2.1" />
      <path d="M6.2 12.4c3.6-1.1 7.6-0.7 10.8 1" stroke-width="1.8" />
      <path d="M7 15.6c2.9-0.8 5.9-0.5 8.4 0.8" stroke-width="1.55" />
    </g>
  {:else if platform === 'instagram'}
    <defs>
      <linearGradient id="ig-{uid}" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0" stop-color="#FEDA75" />
        <stop offset="0.28" stop-color="#FA7E1E" />
        <stop offset="0.55" stop-color="#D62976" />
        <stop offset="0.8" stop-color="#962FBF" />
        <stop offset="1" stop-color="#4F5BD5" />
      </linearGradient>
    </defs>
    <rect width="24" height="24" rx="7.2" fill="url(#ig-{uid})" />
    <rect x="5.2" y="5.2" width="13.6" height="13.6" rx="4.2" fill="none" stroke="#fff" stroke-width="1.8" />
    <circle cx="12" cy="12" r="3.3" fill="none" stroke="#fff" stroke-width="1.8" />
    <circle cx="16.1" cy="7.9" r="1" fill="#fff" />
  {:else if platform === 'tiktok'}
    <rect width="24" height="24" rx="6.6" fill="#111" />
    <g transform="translate(5.2 4.6) scale(0.56)">
      <path transform="translate(-0.9 -0.8)" fill="#25F4EE" d={note} />
      <path transform="translate(0.9 0.8)" fill="#FE2C55" d={note} />
      <path fill="#fff" d={note} />
    </g>
  {:else}
    <circle cx="12" cy="12" r="12" fill="var(--fill-3)" />
    <g fill="none" stroke="var(--text-2)" stroke-width="1.5" stroke-linecap="round">
      <circle cx="12" cy="12" r="6.6" />
      <path d="M5.4 12h13.2M12 5.4c2 2.1 2.9 4.3 2.9 6.6s-0.9 4.5-2.9 6.6c-2-2.1-2.9-4.3-2.9-6.6s0.9-4.5 2.9-6.6z" />
    </g>
  {/if}
</svg>

<style>
  .badge {
    display: block;
    flex-shrink: 0;
    overflow: visible;
  }
</style>

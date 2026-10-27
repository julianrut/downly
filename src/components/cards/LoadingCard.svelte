<script lang="ts">
  import MediaHeader from '../MediaHeader.svelte';
  import type { MediaSummary, ParsedLink } from '../../lib/types';

  let { link, preview }: { link: ParsedLink; preview: MediaSummary | null } = $props();

  const messages: Record<string, string> = {
    youtube: 'Finding every quality…',
    spotify: 'Reading from Spotify…',
    instagram: 'Opening Instagram…',
    tiktok: 'Opening TikTok…',
    web: 'Looking for media…',
  };
  let square = $derived(link.platform === 'spotify');
</script>

<div class="card stack" aria-busy="true">
  {#if preview}
    <MediaHeader summary={preview} shape={square ? 'square' : 'wide'} />
  {:else}
    <div class="header">
      <div class="skeleton" style:width="{square ? 104 : 176}px" style:height="{square ? 104 : 99}px" style:border-radius="12px"></div>
      <div class="lines">
        <div class="skeleton" style:width="90px" style:height="10px"></div>
        <div class="skeleton" style:width="min(280px, 100%)" style:height="16px"></div>
        <div class="skeleton" style:width="150px" style:height="12px"></div>
      </div>
    </div>
  {/if}
  <div class="status">
    <span class="spinner" style:--spinner="14px"></span>
    <span>{messages[link.platform]}</span>
  </div>
  <div class="chips">
    {#each [0, 1, 2, 3] as i (i)}
      <div class="skeleton chip" style:animation-delay="{i * 0.12}s"></div>
    {/each}
  </div>
</div>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .header {
    display: flex;
    gap: 16px;
    align-items: flex-start;
  }

  .lines {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding-top: 4px;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    color: var(--text-2);
  }

  .chips {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
  }

  .chip {
    height: 60px;
    border-radius: 12px;
  }
</style>

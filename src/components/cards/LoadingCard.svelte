<script lang="ts">
  import ProgressBar from '../ProgressBar.svelte';
  import Thumb from '../Thumb.svelte';
  import type { MediaSummary, ParsedLink } from '../../lib/types';

  let { link, preview }: { link: ParsedLink; preview: MediaSummary | null } = $props();
  let square = $derived(link.platform === 'spotify');
</script>

<div class="panel" aria-busy="true">
  <div class="header">
    {#if preview?.thumbnail}
      <Thumb src={preview.thumbnail} width={square ? 63 : 112} height={63} />
    {:else}
      <div class="skeleton" style:width="{square ? 63 : 112}px" style:height="63px"></div>
    {/if}
    <div class="lines">
      {#if preview}
        <div class="title">{preview.title}</div>
        {#if preview.author}<div class="meta mono">{preview.author}</div>{/if}
      {:else}
        <div class="skeleton" style:width="min(240px, 90%)" style:height="13px"></div>
        <div class="skeleton" style:width="110px" style:height="10px"></div>
      {/if}
    </div>
  </div>
  <ProgressBar fraction={null} height={1} />
</div>

<style>
  .header {
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .lines {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding-top: 3px;
  }

  .title {
    font-size: 16px;
    font-weight: 500;
    line-height: 1.3;
    filter: grayscale(1);
  }

  .meta {
    font-size: 11px;
    color: var(--text-2);
  }
</style>

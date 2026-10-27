<script lang="ts">
  import { flip } from 'svelte/animate';
  import { fade } from 'svelte/transition';
  import DownloadRow from './DownloadRow.svelte';
  import { api } from '../lib/api';
  import { app } from '../lib/state.svelte';
</script>

<section>
  <div class="heading">
    <span class="label">Downloads{app.active ? `  ·  ${app.active}` : ''}</span>
    {#if app.hasFinished}
      <button class="text-button" onclick={() => api.clearFinished()}>Clear</button>
    {/if}
  </div>
  <div role="list">
    {#each app.downloads as item (item.id)}
      <div class="entry" animate:flip={{ duration: 250 }} in:fade={{ duration: 200 }}>
        <DownloadRow {item} />
      </div>
    {/each}
  </div>
</section>

<style>
  section {
    margin-top: 18px;
  }

  .heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 24px;
    padding-bottom: 4px;
    border-bottom: 1px solid var(--line);
  }

  .entry {
    border-bottom: 1px solid var(--line);
  }
</style>

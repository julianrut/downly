<script lang="ts">
  import { flip } from 'svelte/animate';
  import { fly } from 'svelte/transition';
  import DownloadRow from './DownloadRow.svelte';
  import { api } from '../lib/api';
  import { app } from '../lib/state.svelte';
</script>

<section class="downloads">
  <div class="heading">
    <h2 class="rounded">Downloads</h2>
    {#if app.active > 0}<span class="active tabular">{app.active} in progress</span>{/if}
    <div class="spacer"></div>
    {#if app.hasFinished}
      <button class="link-button" title="Remove finished downloads from the list (files stay on disk)" onclick={() => api.clearFinished()}>Clear</button>
    {/if}
  </div>
  <div class="card list" role="list">
    {#each app.downloads as item, index (item.id)}
      <div class="entry" animate:flip={{ duration: 320 }} in:fly={{ y: -10, duration: 320 }}>
        {#if index > 0}<div class="divider"></div>{/if}
        <DownloadRow {item} />
      </div>
    {/each}
  </div>
</section>

<style>
  .downloads {
    display: flex;
    flex-direction: column;
    gap: 10px;
    margin-top: 6px;
  }

  .heading {
    display: flex;
    align-items: baseline;
    gap: 10px;
    padding: 0 4px;
  }

  h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
  }

  .active {
    font-size: 11.5px;
    font-weight: 600;
    color: var(--accent);
  }

  .spacer {
    flex: 1;
  }

  .list {
    padding: 6px;
  }

  .divider {
    height: 1px;
    margin: 0 10px 0 86px;
    background: var(--separator);
  }
</style>

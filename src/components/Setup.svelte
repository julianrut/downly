<script lang="ts">
  import ProgressBar from './ProgressBar.svelte';
  import { api } from '../lib/api';
  import { app } from '../lib/state.svelte';

  let tools = $derived(app.setup.tools);
  let failed = $derived(!app.setup.running && Boolean(app.setup.error));
  let overall = $derived.by(() => {
    if (!tools.length) return 0;
    const values = tools.map((tool) => {
      switch (tool.phase.state) {
        case 'downloading':
          return tool.phase.fraction * 0.9;
        case 'installing':
          return 0.95;
        case 'ready':
          return 1;
        default:
          return 0;
      }
    });
    return values.reduce((a, b) => a + b, 0) / values.length;
  });
</script>

<div class="setup">
  {#if failed}
    <span class="label">Setup failed</span>
    <p class="error selectable">{app.setup.error}</p>
    <button class="text-button strong" onclick={() => api.startSetup()}>Retry</button>
  {:else}
    <div class="row">
      <span class="label">Setting up</span>
      <span class="label mono">{String(Math.round(overall * 100)).padStart(2, '0')}%</span>
    </div>
    <ProgressBar fraction={overall} height={1} />
  {/if}
</div>

<style>
  .setup {
    width: 240px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    margin-bottom: 40px;
  }

  .row {
    display: flex;
    justify-content: space-between;
  }

  .error {
    margin: 0;
    font-size: 12px;
    color: var(--text-2);
    white-space: pre-line;
  }

  .text-button {
    align-self: flex-start;
  }
</style>

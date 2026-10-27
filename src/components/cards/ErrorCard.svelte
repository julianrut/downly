<script lang="ts">
  import { api } from '../../lib/api';
  import { app } from '../../lib/state.svelte';
  import type { ErrorInfo, ParsedLink } from '../../lib/types';

  let { link, error }: { link: ParsedLink | null; error: ErrorInfo } = $props();
</script>

<div class="panel" role="alert">
  <div class="text">
    <div class="message selectable">{error.message}</div>
    {#if error.suggestion}<div class="suggestion">{error.suggestion}</div>{/if}
  </div>
  <div class="actions">
    {#if link}<button class="text-button strong" onclick={() => app.retry()}>Retry</button>{/if}
    {#if error.needsAccount}<button class="text-button" onclick={() => api.openSettingsWindow()}>Settings</button>{/if}
    <button class="text-button" onclick={() => app.clear()}>Dismiss</button>
  </div>
</div>

<style>
  .panel {
    padding-left: 14px;
    border-left: 1px solid var(--text);
  }

  .text {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .message {
    font-size: 14px;
    font-weight: 500;
  }

  .suggestion {
    font-size: 13px;
    color: var(--text-2);
  }

  .actions {
    display: flex;
    gap: 20px;
    margin-top: -8px;
  }
</style>

<script lang="ts">
  import { TriangleAlert, UserRound } from '@lucide/svelte';
  import { api } from '../../lib/api';
  import { app } from '../../lib/state.svelte';
  import type { ErrorInfo, ParsedLink } from '../../lib/types';

  let { link, error }: { link: ParsedLink | null; error: ErrorInfo } = $props();
</script>

<div class="card row" role="alert">
  <div class="icon">
    {#if error.needsAccount}
      <UserRound size={20} strokeWidth={2.2} />
    {:else}
      <TriangleAlert size={20} strokeWidth={2.2} />
    {/if}
  </div>
  <div class="body">
    <div class="message selectable">{error.message}</div>
    {#if error.suggestion}<div class="suggestion">{error.suggestion}</div>{/if}
    <div class="actions">
      {#if link}
        <button class="primary-button compact" onclick={() => app.retry()}>Try Again</button>
      {/if}
      {#if error.needsAccount}
        <button class="soft-button" onclick={() => api.openSettingsWindow()}>Open Settings</button>
      {/if}
      <button class="soft-button" onclick={() => app.clear()}>Dismiss</button>
    </div>
  </div>
</div>

<style>
  .row {
    display: flex;
    align-items: flex-start;
    gap: 14px;
  }

  .icon {
    flex-shrink: 0;
    width: 44px;
    height: 44px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--orange);
    background: color-mix(in srgb, var(--orange) 14%, transparent);
  }

  .body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .message {
    font-size: 14px;
    font-weight: 600;
    line-height: 1.35;
  }

  .suggestion {
    font-size: 13px;
    color: var(--text-2);
  }

  .actions {
    display: flex;
    gap: 8px;
    margin-top: 6px;
    flex-wrap: wrap;
  }
</style>

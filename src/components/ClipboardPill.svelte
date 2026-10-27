<script lang="ts">
  import { X } from '@lucide/svelte';
  import PlatformBadge from './PlatformBadge.svelte';
  import { shortUrl } from '../lib/format';
  import { app } from '../lib/state.svelte';
  import type { ParsedLink } from '../lib/types';

  let { link }: { link: ParsedLink } = $props();
</script>

<div class="suggestion">
  <span class="icon"><PlatformBadge platform={link.platform} size={14} /></span>
  <button class="url mono truncate" onclick={() => app.useClipboard()}>{shortUrl(link.url)}</button>
  <button class="text-button strong" onclick={() => app.useClipboard()}>Use</button>
  <button class="icon-button" title="Dismiss" aria-label="Dismiss" onclick={() => app.dismissClipboard()}>
    <X size={13} strokeWidth={1.5} />
  </button>
</div>

<style>
  .suggestion {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: -6px;
  }

  .icon {
    display: flex;
    color: var(--text-2);
  }

  .url {
    flex: 1;
    min-width: 0;
    text-align: left;
    font-size: 11.5px;
    color: var(--text-2);
  }

  .icon-button {
    margin-right: -7px;
  }
</style>

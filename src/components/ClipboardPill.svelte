<script lang="ts">
  import { X } from '@lucide/svelte';
  import PlatformBadge from './PlatformBadge.svelte';
  import { shortUrl } from '../lib/format';
  import { app } from '../lib/state.svelte';
  import type { ParsedLink } from '../lib/types';

  let { link }: { link: ParsedLink } = $props();
</script>

<div class="pill">
  <PlatformBadge platform={link.platform} size={20} />
  <div class="text">
    <span class="label">Link on your clipboard</span>
    <span class="url truncate">{shortUrl(link.url)}</span>
  </div>
  <button class="primary-button compact" onclick={() => app.useClipboard()}>Use Link</button>
  <button class="icon-button" style:--size="24px" title="Dismiss" aria-label="Dismiss" onclick={() => app.dismissClipboard()}>
    <X size={13} strokeWidth={2.4} />
  </button>
</div>

<style>
  .pill {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px 10px 14px;
    border-radius: 14px;
    background: var(--tint);
    box-shadow: inset 0 0 0 1px var(--tint-border);
  }

  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .label {
    font-size: 11.5px;
    color: var(--text-2);
  }

  .url {
    font-size: 13px;
    font-weight: 500;
  }
</style>

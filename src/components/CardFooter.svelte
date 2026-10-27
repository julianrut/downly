<script lang="ts">
  import { ArrowDown } from '@lucide/svelte';
  import type { Snippet } from 'svelte';

  let {
    title,
    detail = null,
    enabled = true,
    ondownload,
    children,
  }: {
    title: string;
    detail?: string | null;
    enabled?: boolean;
    ondownload: () => void;
    children?: Snippet;
  } = $props();
</script>

<div class="footer">
  <div class="leading">{@render children?.()}</div>
  <button class="primary-button" disabled={!enabled} onclick={ondownload} data-default-action>
    <ArrowDown size={15} strokeWidth={2.8} />
    <span>{title}</span>
    {#if detail}<span class="detail tabular">{detail}</span>{/if}
  </button>
</div>

<style>
  .footer {
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .leading {
    flex: 1;
    min-width: 0;
  }

  .detail {
    opacity: 0.78;
    font-size: 12.5px;
    font-weight: 500;
  }
</style>

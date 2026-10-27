<script lang="ts">
  import type { Component } from 'svelte';

  let { icon: Icon, text, highlight = false }: { icon: Component<any>; text: string; highlight?: boolean } = $props();
</script>

<span class="footnote" class:highlight>
  <span class="icon"><Icon size={13} strokeWidth={2.1} /></span>
  <span class="text">{text}</span>
</span>

<style>
  .footnote {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 11.5px;
    color: var(--text-2);
    min-width: 0;
  }

  .icon {
    display: inline-flex;
    flex-shrink: 0;
    color: var(--text-2);
  }

  .highlight .icon {
    color: var(--violet);
  }

  .text {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
</style>

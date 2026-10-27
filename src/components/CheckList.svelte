<script lang="ts" generics="T">
  import type { Snippet } from 'svelte';
  import Mark from './Mark.svelte';

  let {
    items,
    key,
    selected = $bindable(),
    row,
    maxHeight = 300,
  }: {
    items: T[];
    key: (item: T) => string;
    selected: Set<string>;
    row: Snippet<[T, number]>;
    maxHeight?: number;
  } = $props();

  let all = $derived(items.length > 0 && items.every((item) => selected.has(key(item))));

  function toggle(id: string) {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    selected = next;
  }

  function toggleAll() {
    selected = all ? new Set() : new Set(items.map(key));
  }
</script>

<div class="list">
  <div class="list-header">
    <span class="label">{selected.size}/{items.length}</span>
    <button class="text-button" onclick={toggleAll}>{all ? 'None' : 'All'}</button>
  </div>
  <div class="rows" style:max-height="{maxHeight}px">
    {#each items as item, index (key(item))}
      {@const id = key(item)}
      <button class="row" class:off={!selected.has(id)} role="checkbox" aria-checked={selected.has(id)} onclick={() => toggle(id)}>
        <Mark on={selected.has(id)} />
        {@render row(item, index)}
      </button>
    {/each}
  </div>
</div>

<style>
  .list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--line);
  }

  .rows {
    overflow-y: auto;
  }

  .row {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 9px 0;
    text-align: left;
    border-bottom: 1px solid var(--line);
    transition: opacity 0.15s ease;
  }

  .row.off {
    opacity: 0.42;
  }

  .row:hover {
    opacity: 1;
  }
</style>

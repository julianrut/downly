<script lang="ts" generics="T">
  import type { Snippet } from 'svelte';
  import SelectionMark from './SelectionMark.svelte';

  let {
    items,
    key,
    selected = $bindable(),
    row,
    maxHeight = 280,
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
    <span class="count">
      {all ? `All ${items.length} selected` : `${selected.size} of ${items.length} selected`}
    </span>
    <button class="link-button" onclick={toggleAll}>{all ? 'Select None' : 'Select All'}</button>
  </div>
  <div class="rows" style:max-height="{maxHeight}px">
    {#each items as item, index (key(item))}
      {@const id = key(item)}
      <button class="row" role="checkbox" aria-checked={selected.has(id)} onclick={() => toggle(id)}>
        <SelectionMark selected={selected.has(id)} size={17} />
        {@render row(item, index)}
      </button>
    {/each}
  </div>
</div>

<style>
  .list {
    padding: 8px 0;
    border-radius: 12px;
    background: var(--fill);
  }

  .list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 10px 6px 12px;
  }

  .count {
    font-size: 11.5px;
    font-weight: 500;
    color: var(--text-2);
  }

  .rows {
    overflow-y: auto;
    padding: 0 4px;
  }

  .row {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 8px;
    border-radius: 8px;
    text-align: left;
    transition: background 0.12s ease;
  }

  .row:hover {
    background: var(--fill);
  }
</style>

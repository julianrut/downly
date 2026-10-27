<script lang="ts" generics="T extends string | number | null">
  import { ChevronsUpDown } from '@lucide/svelte';

  let {
    value = $bindable(),
    options,
    label,
    disabled = false,
    onchange,
  }: {
    value: T;
    options: { id: T; title: string }[];
    label: string;
    disabled?: boolean;
    onchange?: (value: T) => void;
  } = $props();

  let index = $derived(Math.max(0, options.findIndex((o) => o.id === value)));

  function change(event: Event) {
    const selected = options[Number((event.currentTarget as HTMLSelectElement).value)];
    if (!selected) return;
    value = selected.id;
    onchange?.(selected.id);
  }
</script>

<span class="popup" class:disabled>
  <select aria-label={label} {disabled} value={index} onchange={change}>
    {#each options as option, i (i)}
      <option value={i}>{option.title}</option>
    {/each}
  </select>
  <span class="value truncate">{options[index]?.title}</span>
  <ChevronsUpDown size={11} strokeWidth={1.6} />
</span>

<style>
  .popup {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    max-width: 240px;
    color: var(--text-3);
  }

  .popup:hover:not(.disabled) {
    color: var(--text-2);
  }

  .popup.disabled {
    opacity: 0.4;
  }

  select {
    position: absolute;
    inset: -6px -4px;
    opacity: 0;
    border: none;
    -webkit-appearance: none;
    appearance: none;
    font-size: 13px;
  }

  .value {
    min-width: 0;
    font-size: 13px;
    color: var(--text);
    pointer-events: none;
  }
</style>

<script lang="ts" generics="T extends string | number | null">
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
  <span class="label truncate">{options[index]?.title}</span>
  <svg class="chevrons" width="9" height="13" viewBox="0 0 9 13" aria-hidden="true">
    <path d="M1.5 4.6 4.5 1.6l3 3M1.5 8.4l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
  </svg>
</span>

<style>
  .popup {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 24px;
    max-width: 280px;
    padding: 0 8px 0 10px;
    border-radius: 6px;
    font-size: 13px;
    background: var(--card-solid);
    box-shadow:
      0 0.5px 1.5px rgba(0, 0, 0, 0.2),
      0 0 0 0.5px rgba(0, 0, 0, 0.1);
  }

  @media (prefers-color-scheme: dark) {
    .popup {
      background: rgba(255, 255, 255, 0.12);
      box-shadow:
        0 0.5px 1px rgba(0, 0, 0, 0.4),
        inset 0 0.5px 0 rgba(255, 255, 255, 0.08);
    }
  }

  .popup.disabled {
    opacity: 0.45;
  }

  select {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0;
    -webkit-appearance: none;
    appearance: none;
    border: none;
    font-size: 13px;
  }

  .label {
    min-width: 0;
    pointer-events: none;
  }

  .chevrons {
    flex-shrink: 0;
    color: var(--text-2);
    pointer-events: none;
  }
</style>

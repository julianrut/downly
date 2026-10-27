<script lang="ts" generics="T extends string | number">
  let {
    value = $bindable(),
    options,
    label = '',
  }: {
    value: T;
    options: { id: T; title: string }[];
    label?: string;
  } = $props();

  let index = $derived(Math.max(0, options.findIndex((o) => o.id === value)));
</script>

<div class="segmented" role="radiogroup" aria-label={label} style:--count={options.length}>
  <div class="thumb" style:transform="translateX({index * 100}%)"></div>
  {#each options as option (option.id)}
    <button role="radio" aria-checked={value === option.id} class:active={value === option.id} onclick={() => (value = option.id)}>
      {option.title}
    </button>
  {/each}
</div>

<style>
  .segmented {
    position: relative;
    display: inline-grid;
    grid-template-columns: repeat(var(--count), 1fr);
    padding: 2px;
    border-radius: 8px;
    background: var(--fill-2);
  }

  .thumb {
    position: absolute;
    top: 2px;
    bottom: 2px;
    left: 2px;
    width: calc((100% - 4px) / var(--count));
    border-radius: 6px;
    background: var(--card-solid);
    box-shadow:
      0 1px 3px rgba(0, 0, 0, 0.14),
      0 0 0 0.5px rgba(0, 0, 0, 0.06);
    transition: transform 0.3s var(--ease-spring);
  }

  button {
    position: relative;
    height: 24px;
    padding: 0 14px;
    font-size: 12px;
    font-weight: 600;
    color: var(--text-2);
    border-radius: 6px;
    transition: color 0.2s ease;
  }

  button.active {
    color: var(--text);
  }
</style>

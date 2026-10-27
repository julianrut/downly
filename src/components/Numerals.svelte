<script lang="ts" generics="T extends string | number">
  let {
    value = $bindable(),
    options,
    label,
  }: {
    value: T;
    options: { id: T; title: string }[];
    label: string;
  } = $props();
</script>

<div class="numerals" role="radiogroup" aria-label={label}>
  {#each options as option (option.id)}
    <button role="radio" aria-checked={value === option.id} class:active={value === option.id} onclick={() => (value = option.id)}>
      {option.title}
    </button>
  {/each}
</div>

<style>
  .numerals {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 22px;
  }

  button {
    font-family: var(--mono);
    font-size: 26px;
    font-weight: 400;
    letter-spacing: -0.03em;
    line-height: 1.1;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
    transition: color 0.18s ease;
  }

  button:hover:not(.active) {
    color: var(--text-2);
  }

  button.active {
    color: var(--text);
  }
</style>

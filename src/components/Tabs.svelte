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

<div class="tabs" role="radiogroup" aria-label={label}>
  {#each options as option (option.id)}
    <button role="radio" aria-checked={value === option.id} class:active={value === option.id} onclick={() => (value = option.id)}>
      {option.title}
    </button>
  {/each}
</div>

<style>
  .tabs {
    display: flex;
    gap: 18px;
  }

  button {
    position: relative;
    padding: 4px 0 6px;
    font-family: var(--mono);
    font-size: 10.5px;
    font-weight: 500;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--text-3);
    transition: color 0.15s ease;
  }

  button::after {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 1px;
    background: var(--text);
    transform: scaleX(0);
    transform-origin: left;
    transition: transform 0.25s var(--ease);
  }

  button:hover:not(.active) {
    color: var(--text-2);
  }

  button.active {
    color: var(--text);
  }

  button.active::after {
    transform: scaleX(1);
  }
</style>

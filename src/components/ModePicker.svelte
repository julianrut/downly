<script lang="ts">
  import { Film, Music } from '@lucide/svelte';
  import type { Mode } from '../lib/types';

  let { value = $bindable() }: { value: Mode } = $props();
  const modes: { id: Mode; title: string }[] = [
    { id: 'video', title: 'Video' },
    { id: 'audio', title: 'Audio' },
  ];
</script>

<div class="picker" role="radiogroup" aria-label="Download type">
  <div class="thumb" class:right={value === 'audio'}></div>
  {#each modes as mode (mode.id)}
    <button
      role="radio"
      aria-checked={value === mode.id}
      class:active={value === mode.id}
      onclick={() => (value = mode.id)}
    >
      {#if mode.id === 'video'}
        <Film size={14} strokeWidth={2.2} />
      {:else}
        <Music size={14} strokeWidth={2.2} />
      {/if}
      {mode.title}
    </button>
  {/each}
</div>

<style>
  .picker {
    position: relative;
    display: inline-grid;
    grid-template-columns: 1fr 1fr;
    padding: 3px;
    border-radius: 999px;
    background: var(--fill-2);
  }

  .thumb {
    position: absolute;
    top: 3px;
    bottom: 3px;
    left: 3px;
    width: calc(50% - 3px);
    border-radius: 999px;
    background: var(--card-solid);
    box-shadow:
      0 2px 6px rgba(0, 0, 0, 0.12),
      0 0 0 0.5px rgba(0, 0, 0, 0.06);
    transition: transform 0.36s var(--ease-spring);
  }

  .thumb.right {
    transform: translateX(100%);
  }

  button {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 30px;
    padding: 0 18px;
    font-size: 13px;
    font-weight: 600;
    color: var(--text-2);
    border-radius: 999px;
    transition: color 0.2s ease;
  }

  button.active {
    color: var(--text);
  }
</style>

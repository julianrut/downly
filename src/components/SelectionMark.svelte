<script lang="ts">
  import { Check } from '@lucide/svelte';

  let { selected, size = 20, overlay = false }: { selected: boolean; size?: number; overlay?: boolean } = $props();
</script>

<span class="mark" class:selected class:overlay style:width="{size}px" style:height="{size}px">
  {#if selected}<Check size={size * 0.6} strokeWidth={3.4} color="#fff" />{/if}
</span>

<style>
  .mark {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    flex-shrink: 0;
    box-shadow: inset 0 0 0 1.5px var(--fill-3);
    transition:
      background 0.18s ease,
      box-shadow 0.18s ease,
      transform 0.25s var(--ease-spring);
  }

  .mark.overlay {
    background: rgba(0, 0, 0, 0.24);
    box-shadow:
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.92),
      0 1px 3px rgba(0, 0, 0, 0.25);
  }

  .mark.selected {
    background: var(--brand);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.18);
    transform: scale(1.04);
  }
</style>

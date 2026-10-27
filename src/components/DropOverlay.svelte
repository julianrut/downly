<script lang="ts">
  import { CircleArrowDown } from '@lucide/svelte';
  import { fade, scale } from 'svelte/transition';
</script>

<div class="overlay" transition:fade={{ duration: 160 }}>
  <div class="frame"></div>
  <div class="content" in:scale={{ start: 0.9, duration: 260 }}>
    <span class="icon"><CircleArrowDown size={54} strokeWidth={1.6} /></span>
    <span class="label rounded">Drop to download</span>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    background: color-mix(in srgb, var(--window-solid) 70%, transparent);
    backdrop-filter: blur(18px) saturate(1.4);
    -webkit-backdrop-filter: blur(18px) saturate(1.4);
  }

  .frame {
    position: absolute;
    inset: 24px;
    border-radius: 24px;
    border: 2.5px dashed color-mix(in srgb, var(--violet) 70%, transparent);
  }

  .content {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
  }

  .icon {
    display: flex;
    color: var(--violet);
  }

  .label {
    font-size: 20px;
    font-weight: 600;
  }
</style>

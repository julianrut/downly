<script lang="ts">
  import { fade } from 'svelte/transition';
</script>

<div class="overlay" transition:fade={{ duration: 120 }}>
  <div class="frame"><span class="label">Drop link</span></div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: flex;
    padding: 14px;
    pointer-events: none;
    background: var(--bg);
  }

  .frame {
    flex: 1;
    display: grid;
    place-items: center;
    border: 1px dashed var(--text-2);
  }
</style>

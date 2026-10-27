<script lang="ts">
  import { Folder, Settings } from '@lucide/svelte';
  import { api, isTauri } from '../lib/api';

  let { scrolled = false }: { scrolled?: boolean } = $props();
</script>

<header class="topbar" class:scrolled data-tauri-drag-region>
  {#if !isTauri}
    <div class="lights" aria-hidden="true"><span></span><span></span><span></span></div>
  {/if}
  <div class="spacer" data-tauri-drag-region></div>
  <button class="icon-button" title="Open download folder" aria-label="Open download folder" onclick={() => api.openDownloadsFolder()}>
    <Folder size={16} strokeWidth={1.4} />
  </button>
  <button class="icon-button" title="Settings" aria-label="Settings" onclick={() => api.openSettingsWindow()}>
    <Settings size={16} strokeWidth={1.4} />
  </button>
</header>

<style>
  .topbar {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    z-index: 5;
    display: flex;
    align-items: center;
    gap: 4px;
    height: 52px;
    padding: 0 14px 0 86px;
    background: var(--bg);
    border-bottom: 1px solid transparent;
    transition: border-color 0.2s ease;
  }

  .topbar.scrolled {
    border-bottom-color: var(--line);
  }

  .spacer {
    flex: 1;
    align-self: stretch;
  }

  .lights {
    position: absolute;
    left: 20px;
    top: 50%;
    transform: translateY(-50%);
    display: flex;
    gap: 8px;
  }

  .lights span {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    box-shadow: inset 0 0 0 1px var(--line-strong);
  }
</style>

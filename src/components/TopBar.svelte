<script lang="ts">
  import { Folder, Settings } from '@lucide/svelte';
  import { fade, scale } from 'svelte/transition';
  import { api, isTauri } from '../lib/api';
  import { app } from '../lib/state.svelte';

  let { scrolled = false }: { scrolled?: boolean } = $props();
</script>

<header class="topbar" class:scrolled data-tauri-drag-region>
  {#if !isTauri}
    <div class="lights" aria-hidden="true"><span></span><span></span><span></span></div>
  {/if}
  <div class="spacer" data-tauri-drag-region></div>
  {#if app.active > 0}
    <div class="activity" transition:scale={{ start: 0.85, duration: 220 }}>
      <span class="spinner" style:--spinner="10px"></span>
      <span class="tabular">{app.active} active</span>
    </div>
  {/if}
  <button class="icon-button" title="Open download folder" aria-label="Open download folder" onclick={() => api.openDownloadsFolder()} in:fade>
    <Folder size={15} strokeWidth={2} />
  </button>
  <button class="icon-button" title="Settings (⌘,)" aria-label="Settings" onclick={() => api.openSettingsWindow()}>
    <Settings size={15} strokeWidth={2} />
  </button>
</header>

<style>
  .topbar {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    z-index: 5;
    border-bottom: 1px solid transparent;
    transition:
      background-color 0.25s ease,
      border-color 0.25s ease,
      backdrop-filter 0.25s ease;
    display: flex;
    align-items: center;
    gap: 6px;
    height: 52px;
    padding: 0 14px 0 86px;
    flex-shrink: 0;
  }

  .topbar.scrolled {
    background: color-mix(in srgb, var(--window-solid) 72%, transparent);
    backdrop-filter: blur(20px) saturate(1.8);
    -webkit-backdrop-filter: blur(20px) saturate(1.8);
    border-bottom-color: var(--separator);
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
    box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.12);
  }

  .lights span:nth-child(1) {
    background: #ff5f57;
  }

  .lights span:nth-child(2) {
    background: #febc2e;
  }

  .lights span:nth-child(3) {
    background: #28c840;
  }

  .activity {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 22px;
    padding: 0 10px;
    margin-right: 4px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    color: var(--text-2);
    background: var(--fill-2);
  }
</style>

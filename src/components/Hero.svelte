<script lang="ts">
  import { ClipboardPaste, Hand } from '@lucide/svelte';
  import PlatformBadge from './PlatformBadge.svelte';
  import { platformNames } from '../lib/format';
  import type { Platform } from '../lib/types';
  import icon from '../assets/icon.png';

  const platforms: Platform[] = ['youtube', 'spotify', 'instagram', 'tiktok'];
</script>

<div class="hero">
  <img class="icon" src={icon} alt="" width="116" height="116" draggable="false" />
  <div class="copy">
    <h1 class="rounded">Download anything, beautifully.</h1>
    <p>Paste a link to save videos, music, reels, stories and photos —<br />in the best quality, with sound, every time.</p>
  </div>
  <div class="platforms">
    {#each platforms as platform (platform)}
      <span class="platform">
        <PlatformBadge {platform} size={18} />
        {platformNames[platform]}
      </span>
    {/each}
  </div>
  <div class="hints">
    <span><ClipboardPaste size={12} strokeWidth={2} /> Copy a link anywhere — Downly offers it</span>
    <span><Hand size={12} strokeWidth={2} /> Or drag a link onto this window</span>
  </div>
</div>

<style>
  .hero {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    padding: 30px 0 18px;
    text-align: center;
  }

  .icon {
    width: 116px;
    height: 116px;
    margin-bottom: 4px;
    filter: drop-shadow(0 14px 22px color-mix(in srgb, var(--violet) 38%, transparent));
    animation: float 6s ease-in-out infinite;
  }

  @keyframes float {
    0%,
    100% {
      transform: translateY(0);
    }
    50% {
      transform: translateY(-4px);
    }
  }

  .copy {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  h1 {
    margin: 0;
    font-size: 26px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }

  p {
    margin: 0;
    font-size: 14px;
    line-height: 1.5;
    color: var(--text-2);
  }

  .platforms {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 14px;
    margin-top: 6px;
  }

  .platform {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    font-weight: 500;
    color: var(--text-2);
  }

  .hints {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 18px;
    margin-top: 10px;
    font-size: 11.5px;
    color: var(--text-3);
  }

  .hints span {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
</style>

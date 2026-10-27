<script lang="ts">
  import { CircleArrowDown, Clapperboard, Activity, Zap, CircleCheck, TriangleAlert, Clock } from '@lucide/svelte';
  import ProgressBar from './ProgressBar.svelte';
  import { api } from '../lib/api';
  import { app } from '../lib/state.svelte';
  import type { ToolId, ToolStatus } from '../lib/types';
  import icon from '../assets/icon.png';

  const purposes: Record<ToolId, string> = {
    ytdlp: 'Finds and downloads the media',
    ffmpeg: 'Merges video with sound and converts',
    ffprobe: 'Checks every finished file',
    deno: 'Unlocks YouTube’s protected formats',
  };

  const icons = { ytdlp: CircleArrowDown, ffmpeg: Clapperboard, ffprobe: Activity, deno: Zap };

  let tools = $derived(app.setup.tools);
  let failed = $derived(!app.setup.running && Boolean(app.setup.error));
  let overall = $derived.by(() => {
    if (!tools.length) return 0;
    const values = tools.map((tool) => {
      switch (tool.phase.state) {
        case 'downloading':
          return tool.phase.fraction * 0.9;
        case 'installing':
          return 0.95;
        case 'ready':
          return 1;
        default:
          return 0;
      }
    });
    return values.reduce((a, b) => a + b, 0) / values.length;
  });

  function detail(tool: ToolStatus) {
    switch (tool.phase.state) {
      case 'waiting':
        return purposes[tool.id];
      case 'downloading':
        return 'Downloading…';
      case 'installing':
        return 'Installing…';
      case 'ready':
        return `Ready · ${tool.phase.version}`;
      case 'failed':
        return tool.phase.message;
    }
  }
</script>

<div class="setup">
  <div class="logo">
    <div class="halo"></div>
    <img src={icon} alt="" width="128" height="128" draggable="false" />
  </div>
  <div class="copy">
    <h1 class="rounded">{failed ? 'Setup needs another try' : 'Getting Downly ready'}</h1>
    <p>
      {#if failed}
        Something interrupted the download. Check your connection and try again.
      {:else}
        Downloading the engine that powers every download.<br />This happens once and takes about a minute.
      {/if}
    </p>
  </div>

  {#if tools.length}
    <div class="card tools">
      {#each tools as tool, index (tool.id)}
        {@const Icon = icons[tool.id]}
        {#if index > 0}<div class="divider"></div>{/if}
        <div class="tool">
          <div class="tool-icon"><Icon size={15} strokeWidth={2.2} /></div>
          <div class="tool-text">
            <span class="tool-name">{tool.name}</span>
            <span class="tool-detail truncate">{detail(tool)}</span>
          </div>
          <div class="tool-state">
            {#if tool.phase.state === 'waiting'}
              <span class="tertiary"><Clock size={14} strokeWidth={2} /></span>
            {:else if tool.phase.state === 'downloading'}
              <div class="mini"><ProgressBar fraction={tool.phase.fraction} height={4} /></div>
            {:else if tool.phase.state === 'installing'}
              <span class="spinner" style:--spinner="14px"></span>
            {:else if tool.phase.state === 'ready'}
              <span class="ok"><CircleCheck size={17} strokeWidth={2.4} /></span>
            {:else}
              <span class="warn"><TriangleAlert size={15} strokeWidth={2.4} /></span>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}

  {#if failed}
    <div class="failure">
      <p class="selectable">{app.setup.error}</p>
      <button class="primary-button" onclick={() => api.startSetup()}>Try Again</button>
    </div>
  {:else}
    <div class="overall">
      <div class="overall-bar"><ProgressBar fraction={overall} height={6} /></div>
      <span class="tabular">{Math.round(overall * 100)}%</span>
    </div>
  {/if}
</div>

<style>
  .setup {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 22px;
    padding: 0 32px 40px;
    text-align: center;
  }

  .logo {
    position: relative;
    width: 128px;
    height: 128px;
  }

  .halo {
    position: absolute;
    inset: -56px;
    border-radius: 50%;
    background: radial-gradient(circle, color-mix(in srgb, var(--violet) 35%, transparent), color-mix(in srgb, var(--pink) 12%, transparent) 45%, transparent 70%);
    animation: breathe 3.2s ease-in-out infinite;
  }

  @keyframes breathe {
    0%,
    100% {
      transform: scale(0.94);
      opacity: 0.85;
    }
    50% {
      transform: scale(1.04);
      opacity: 1;
    }
  }

  .logo img {
    position: relative;
    width: 128px;
    height: 128px;
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

  .copy p {
    margin: 0;
    font-size: 14px;
    line-height: 1.5;
    color: var(--text-2);
  }

  .tools {
    width: 100%;
    max-width: 440px;
    padding: 8px;
    text-align: left;
  }

  .divider {
    height: 1px;
    margin: 0 10px;
    background: var(--separator);
  }

  .tool {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 10px;
  }

  .tool-icon {
    width: 32px;
    height: 32px;
    border-radius: 8px;
    display: grid;
    place-items: center;
    color: var(--violet);
    background: var(--tint-strong);
    flex-shrink: 0;
  }

  .tool-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .tool-name {
    font-size: 13px;
    font-weight: 600;
  }

  .tool-detail {
    font-size: 11.5px;
    color: var(--text-2);
  }

  .tool-state {
    width: 70px;
    display: flex;
    justify-content: flex-end;
  }

  .mini {
    width: 64px;
  }

  .ok {
    display: flex;
    color: var(--green);
  }

  .warn {
    display: flex;
    color: var(--orange);
  }

  .overall {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    font-size: 11.5px;
    color: var(--text-2);
  }

  .overall-bar {
    width: 280px;
  }

  .failure {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    max-width: 440px;
  }

  .failure p {
    margin: 0;
    font-size: 11.5px;
    color: var(--text-2);
    white-space: pre-line;
  }
</style>

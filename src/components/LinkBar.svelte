<script lang="ts">
  import { ArrowRight, ClipboardPaste, Link, CircleX } from '@lucide/svelte';
  import { fade, scale } from 'svelte/transition';
  import PlatformBadge from './PlatformBadge.svelte';
  import { api } from '../lib/api';
  import { app } from '../lib/state.svelte';
  import type { Platform } from '../lib/types';

  let field: HTMLInputElement | undefined = $state();
  let focused = $state(false);
  let detected = $state<Platform | null>(null);
  let previous = '';

  let busy = $derived(app.analysis.status === 'loading');

  $effect(() => {
    app.focusTick;
    queueMicrotask(() => field?.focus());
  });

  $effect(() => {
    const text = app.input;
    if (!text.trim()) {
      detected = null;
      return;
    }
    let stale = false;
    api.parseLink(text).then((link) => {
      if (!stale) detected = link?.platform ?? null;
    });
    return () => {
      stale = true;
    };
  });

  function oninput() {
    const text = app.input;
    const grew = text.length - previous.length;
    const wasEmpty = previous.trim() === '';
    previous = text;
    if (wasEmpty && grew > 10 && /https?:\/\/|www\.|\.(com|be)\//i.test(text)) {
      app.submit(text);
    }
  }

  function onkeydown(event: KeyboardEvent) {
    if (event.key === 'Enter') {
      event.preventDefault();
      const current = app.analysis;
      if (current.status === 'loaded' && current.link.url === app.input.trim()) {
        document.querySelector<HTMLButtonElement>('[data-default-action]:not(:disabled)')?.click();
      } else {
        app.submit();
      }
    } else if (event.key === 'Escape') {
      if (app.input) {
        event.preventDefault();
        app.clear();
      }
    }
  }

  $effect(() => {
    previous = app.input;
  });
</script>

<div class="bar" class:focused>
  <div class="leading">
    {#key detected}
      <span class="glyph" in:scale={{ start: 0.6, duration: 260 }}>
        {#if detected}
          <PlatformBadge platform={detected} size={22} />
        {:else}
          <Link size={17} strokeWidth={2.3} />
        {/if}
      </span>
    {/key}
  </div>
  <input
    bind:this={field}
    bind:value={app.input}
    {oninput}
    {onkeydown}
    onfocus={() => (focused = true)}
    onblur={() => (focused = false)}
    type="text"
    spellcheck="false"
    autocomplete="off"
    autocapitalize="off"
    placeholder="Paste a link from YouTube, Spotify, Instagram or TikTok"
    aria-label="Link"
  />
  {#if app.input}
    <button class="clear" title="Clear" aria-label="Clear" onclick={() => app.clear()} transition:fade={{ duration: 120 }}>
      <CircleX size={16} strokeWidth={2} />
    </button>
  {/if}
  <div class="trailing">
    {#if !app.input}
      <button class="soft-button" title="Paste link (⇧⌘V)" onclick={() => app.pasteLink()} in:fade={{ duration: 150 }}>
        <ClipboardPaste size={14} strokeWidth={2.2} />
        Paste
      </button>
    {:else if busy}
      <span class="busy" in:fade={{ duration: 150 }}><span class="spinner" style:--spinner="18px"></span></span>
    {:else}
      <button class="go" title="Go" aria-label="Go" onclick={() => app.submit()} in:scale={{ start: 0.7, duration: 220 }}>
        <ArrowRight size={17} strokeWidth={2.8} />
      </button>
    {/if}
  </div>
</div>

<style>
  .bar {
    position: relative;
    display: flex;
    align-items: center;
    gap: 12px;
    height: 58px;
    padding: 0 10px 0 16px;
    border-radius: 17px;
    background: var(--card);
    box-shadow:
      0 8px 24px -10px color-mix(in srgb, var(--violet) 30%, transparent),
      inset 0 0 0 1px var(--hairline);
    transition: box-shadow 0.25s ease;
  }

  .bar::before {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
    padding: 1.5px;
    background: var(--brand);
    -webkit-mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    -webkit-mask-composite: xor;
    mask-composite: exclude;
    opacity: 0;
    transition: opacity 0.25s ease;
    pointer-events: none;
  }

  .bar.focused {
    box-shadow: 0 12px 34px -12px color-mix(in srgb, var(--violet) 55%, transparent);
  }

  .bar.focused::before {
    opacity: 1;
  }

  .leading {
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
    color: var(--text-2);
    flex-shrink: 0;
  }

  .glyph {
    grid-area: 1 / 1;
    display: flex;
  }

  input {
    flex: 1;
    min-width: 0;
    height: 100%;
    border: none;
    outline: none;
    background: transparent;
    font-size: 15.5px;
    letter-spacing: -0.01em;
    caret-color: var(--accent);
  }

  input::placeholder {
    color: var(--text-3);
  }

  .clear {
    display: flex;
    color: var(--text-3);
    transition: color 0.15s ease;
  }

  .clear:hover {
    color: var(--text-2);
  }

  .trailing {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    min-width: 34px;
  }

  .busy {
    width: 34px;
    height: 34px;
    display: grid;
    place-items: center;
  }

  .go {
    width: 34px;
    height: 34px;
    border-radius: 50%;
    display: grid;
    place-items: center;
    color: #fff;
    background: var(--brand);
    box-shadow: 0 6px 16px -6px color-mix(in srgb, var(--violet) 80%, transparent);
    transition: transform 0.2s var(--ease-spring);
  }

  .go:hover {
    transform: scale(1.06);
  }

  .go:active {
    transform: scale(0.94);
  }
</style>

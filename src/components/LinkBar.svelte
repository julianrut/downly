<script lang="ts">
  import { ArrowRight, X } from '@lucide/svelte';
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

  $effect(() => {
    previous = app.input;
  });

  function oninput() {
    const text = app.input;
    const wasEmpty = previous.trim() === '';
    const grew = text.length - previous.length;
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
    } else if (event.key === 'Escape' && app.input) {
      event.preventDefault();
      app.clear();
    }
  }
</script>

<div class="bar" class:focused class:filled={Boolean(app.input)}>
  {#if detected}
    <span class="platform"><PlatformBadge platform={detected} size={16} /></span>
  {/if}
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
    placeholder="Paste a link"
    aria-label="Link"
  />
  {#if busy}
    <span class="spinner"></span>
  {:else if app.input}
    <button class="icon-button" title="Clear" aria-label="Clear" onclick={() => app.clear()}>
      <X size={15} strokeWidth={1.5} />
    </button>
    <button class="icon-button go" title="Go" aria-label="Go" onclick={() => app.submit()}>
      <ArrowRight size={17} strokeWidth={1.5} />
    </button>
  {:else}
    <button class="text-button" onclick={() => app.pasteLink()}>Paste</button>
  {/if}
</div>

<style>
  .bar {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 52px;
    border-bottom: 1px solid var(--line-strong);
    transition: border-color 0.2s ease;
  }

  .bar.focused {
    border-bottom-color: var(--text);
  }

  .platform {
    display: flex;
    color: var(--text);
    animation: rise 0.3s var(--ease);
  }

  input {
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0;
    border: none;
    outline: none;
    background: transparent;
    font-size: 19px;
    font-weight: 400;
    letter-spacing: -0.015em;
    caret-color: var(--text);
  }

  input::placeholder {
    color: var(--text-3);
  }

  .go {
    color: var(--text);
    margin-right: -6px;
  }
</style>

<script lang="ts">
  import { untrack } from 'svelte';
  import { AudioLines } from '@lucide/svelte';
  import DownloadBar from '../DownloadBar.svelte';
  import Mark from '../Mark.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import Thumb from '../Thumb.svelte';
  import { describeItems, galleryJob } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import type { Analysis, GalleryItem } from '../../lib/types';

  let { gallery }: { gallery: Extract<Analysis, { type: 'gallery' }> } = $props();

  let all = $derived(gallery.sections.flatMap((s) => s.items));
  let selected = $state(untrack(() => new Set(gallery.sections.flatMap((s) => s.items.map((i) => i.id)))));
  let chosen = $derived(all.filter((i) => selected.has(i.id)));

  function toggle(id: string) {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    selected = next;
  }

  function toggleSection(items: GalleryItem[]) {
    const next = new Set(selected);
    const every = items.every((i) => next.has(i.id));
    for (const item of items) {
      if (every) next.delete(item.id);
      else next.add(item.id);
    }
    selected = next;
  }
</script>

<div class="panel">
  <MediaHeader summary={gallery.summary} extra={gallery.isProfile ? null : describeItems(all)} shape={gallery.isProfile ? 'circle' : 'square'} />

  {#each gallery.sections as section (section.id)}
    <section>
      <div class="section-header">
        <span class="label">{gallery.sections.length > 1 ? section.title : `${section.items.filter((i) => selected.has(i.id)).length}/${section.items.length}`}</span>
        {#if section.items.length > 1}
          <button class="text-button" onclick={() => toggleSection(section.items)}>
            {section.items.every((i) => selected.has(i.id)) ? 'None' : 'All'}
          </button>
        {/if}
      </div>
      <div class="tiles">
        {#each section.items as item (item.id)}
          {@const on = selected.has(item.id)}
          <button class="tile" class:on role="checkbox" aria-checked={on} onclick={() => toggle(item.id)}>
            {#if item.kind === 'audio'}
              <div class="audio"><AudioLines size={22} strokeWidth={1.4} /></div>
            {:else}
              <Thumb src={item.thumbnail ?? (item.kind === 'photo' ? item.url : null)} width="100%" height="100%" />
            {/if}
            {#if item.kind === 'video'}<span class="kind mono">VID</span>{/if}
            <span class="mark"><Mark {on} light size={12} /></span>
          </button>
        {/each}
      </div>
    </section>
  {/each}

  <DownloadBar
    title={chosen.length > 1 ? `Download ${chosen.length}` : 'Download'}
    enabled={chosen.length > 0}
    ondownload={() => chosen.length && app.enqueue([galleryJob(gallery, chosen)])}
  />
</div>

<style>
  section {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--line);
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(92px, 1fr));
    gap: 6px;
  }

  .tile {
    position: relative;
    aspect-ratio: 1;
    border-radius: 2px;
    overflow: hidden;
    opacity: 0.38;
    transition: opacity 0.15s ease;
  }

  .tile.on,
  .tile:hover {
    opacity: 1;
  }

  .audio {
    width: 100%;
    height: 100%;
    display: grid;
    place-items: center;
    color: var(--text-2);
    background: var(--fill);
  }

  .kind {
    position: absolute;
    left: 6px;
    bottom: 5px;
    font-size: 9px;
    letter-spacing: 0.08em;
    color: #fff;
    text-shadow: 0 0 4px rgba(0, 0, 0, 0.6);
  }

  .mark {
    position: absolute;
    top: 6px;
    right: 6px;
    display: flex;
  }
</style>

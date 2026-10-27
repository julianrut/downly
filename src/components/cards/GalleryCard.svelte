<script lang="ts">
  import { AudioWaveform, Play, Sparkles } from '@lucide/svelte';
  import CardFooter from '../CardFooter.svelte';
  import Footnote from '../Footnote.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import SelectionMark from '../SelectionMark.svelte';
  import Thumb from '../Thumb.svelte';
  import { platformNames } from '../../lib/format';
  import { describeItems, galleryJob } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import { untrack } from 'svelte';
  import type { Analysis, GalleryItem } from '../../lib/types';

  let { gallery }: { gallery: Extract<Analysis, { type: 'gallery' }> } = $props();

  let all = $derived(gallery.sections.flatMap((s) => s.items));
  let selected = $state(untrack(() => new Set(gallery.sections.flatMap((s) => s.items.map((i) => i.id)))));
  let chosen = $derived(all.filter((i) => selected.has(i.id)));
  let single = $derived(all.length === 1);

  let title = $derived.by(() => {
    if (chosen.length === 1) {
      const item = chosen[0];
      if (gallery.isProfile && item.id.startsWith('pfp')) return 'Download profile picture';
      return item.kind === 'photo' ? 'Download photo' : item.kind === 'video' ? 'Download video' : 'Download sound';
    }
    return `Download ${chosen.length} items`;
  });

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

  function resolution(item: GalleryItem) {
    return item.width && item.height ? `${item.width} × ${item.height}` : '';
  }

  function download() {
    if (chosen.length) app.enqueue([galleryJob(gallery, chosen)]);
  }
</script>

<div class="card stack">
  <MediaHeader summary={gallery.summary} badge={gallery.isProfile ? 'Profile' : describeItems(all)} shape={gallery.isProfile ? 'circle' : 'square'} />

  {#each gallery.sections as section (section.id)}
    <section class="section">
      <div class="section-header">
        <h3>{section.title}</h3>
        {#if section.items.length > 1}
          <button class="link-button" onclick={() => toggleSection(section.items)}>
            {section.items.every((i) => selected.has(i.id)) ? 'Select None' : 'Select All'}
          </button>
        {/if}
      </div>
      <div class="tiles" class:single>
        {#each section.items as item (item.id)}
          {@const on = selected.has(item.id)}
          <button class="tile" class:on role="checkbox" aria-checked={on} title={resolution(item)} onclick={() => toggle(item.id)}>
            {#if item.kind === 'audio'}
              <div class="audio"><AudioWaveform size={30} strokeWidth={2.2} /></div>
            {:else}
              <Thumb src={item.thumbnail ?? (item.kind === 'photo' ? item.url : null)} width="100%" height="100%" radius={12} />
            {/if}
            {#if item.kind === 'video'}
              <span class="play"><Play size={10} strokeWidth={0} fill="#fff" /></span>
            {/if}
            <span class="mark"><SelectionMark selected={on} overlay /></span>
          </button>
        {/each}
      </div>
    </section>
  {/each}

  <CardFooter {title} enabled={chosen.length > 0} ondownload={download}>
    <Footnote icon={Sparkles} text="Original resolution, straight from {platformNames[gallery.summary.platform]}" />
  </CardFooter>
</div>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .section {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  h3 {
    margin: 0;
    font-size: 13px;
    font-weight: 600;
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(104px, 1fr));
    gap: 10px;
  }

  .tiles.single {
    grid-template-columns: repeat(auto-fill, minmax(200px, 260px));
  }

  .tile {
    position: relative;
    aspect-ratio: 1;
    border-radius: 12px;
    opacity: 0.6;
    transition:
      transform 0.3s var(--ease-spring),
      opacity 0.18s ease;
  }

  .tile.on {
    opacity: 1;
  }

  .tile:hover {
    transform: scale(1.025);
  }

  .tile:active {
    transform: scale(0.98);
  }

  .tile::after {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
    box-shadow: inset 0 0 0 1px var(--hairline);
    pointer-events: none;
  }

  .tile.on::after {
    padding: 2px;
    box-shadow: none;
    background: var(--brand);
    -webkit-mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    -webkit-mask-composite: xor;
    mask-composite: exclude;
  }

  .audio {
    width: 100%;
    height: 100%;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    background: var(--brand);
  }

  .play {
    position: absolute;
    left: 7px;
    bottom: 7px;
    width: 22px;
    height: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding-left: 2px;
    border-radius: 50%;
    background: rgba(0, 0, 0, 0.55);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
  }

  .mark {
    position: absolute;
    top: 7px;
    right: 7px;
    display: flex;
  }
</style>

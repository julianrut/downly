<script lang="ts">
  import { Clapperboard, ListMusic } from '@lucide/svelte';
  import CardFooter from '../CardFooter.svelte';
  import CheckList from '../CheckList.svelte';
  import Footnote from '../Footnote.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import ModePicker from '../ModePicker.svelte';
  import OptionChip from '../OptionChip.svelte';
  import Thumb from '../Thumb.svelte';
  import { audioFormats, audioInfo, count, duration, tierCaption, tierLabel } from '../../lib/format';
  import { playlistJobs } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import { untrack } from 'svelte';
  import type { Analysis, AudioFormat, Mode, PlaylistEntry } from '../../lib/types';

  let { playlist, link }: { playlist: Extract<Analysis, { type: 'playlist' }>; link: import('../../lib/types').ParsedLink } = $props();

  const settings = app.settings;
  let mode = $state<Mode>(untrack(() => (playlist.isMusic ? 'audio' : settings.defaultMode)));
  let quality = $state(settings.defaultQuality);
  let audioFormat = $state<AudioFormat>(settings.audioFormat);
  let selected = $state(untrack(() => new Set(playlist.entries.map((e) => e.id))));
  const qualities = [0, 4320, 2160, 1440, 1080, 720, 480, 360];

  let title = $derived(selected.size === 1 ? 'Download 1 video' : `Download ${selected.size} ${mode === 'audio' ? 'songs' : 'videos'}`);

  function download() {
    app.enqueue(playlistJobs(playlist, link, selected, mode, quality, audioFormat, settings));
  }
</script>

<div class="card stack">
  <MediaHeader summary={playlist.summary} badge={count(playlist.entries.length, 'video')} />

  <div class="controls">
    <ModePicker bind:value={mode} />
    <div class="spacer"></div>
    {#if mode === 'video'}
      <label class="select">
        <select bind:value={quality} aria-label="Quality">
          {#each qualities as q (q)}
            <option value={q}>{q === 0 ? 'Best available' : `Up to ${tierLabel(q)}${q >= 2160 ? ` (${tierCaption(q)})` : ''}`}</option>
          {/each}
        </select>
      </label>
    {/if}
  </div>

  {#if mode === 'audio'}
    <div class="grid">
      {#each audioFormats as format (format.id)}
        <OptionChip title={format.title} caption={format.short} selected={audioFormat === format.id} onselect={() => (audioFormat = format.id)} />
      {/each}
    </div>
  {/if}

  <CheckList items={playlist.entries} key={(e: PlaylistEntry) => e.id} bind:selected>
    {#snippet row(entry: PlaylistEntry, index: number)}
      <span class="index tabular">{index + 1}</span>
      <Thumb src={entry.thumbnail} width={64} height={36} radius={6} />
      <span class="entry">
        <span class="entry-title truncate">{entry.title}</span>
        {#if entry.author}<span class="entry-author truncate">{entry.author}</span>{/if}
      </span>
      {#if duration(entry.duration)}<span class="length tabular">{duration(entry.duration)}</span>{/if}
    {/snippet}
  </CheckList>

  <CardFooter {title} enabled={selected.size > 0} ondownload={download}>
    {#if mode === 'video'}
      <Footnote icon={Clapperboard} text="Each video is saved with sound in the best quality up to your choice" />
    {:else}
      {@const info = audioInfo(audioFormat)}
      <Footnote icon={ListMusic} text="{info.title} · {info.detail}" />
    {/if}
  </CardFooter>
</div>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .controls {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .spacer {
    flex: 1;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(104px, 1fr));
    gap: 10px;
  }

  .select select {
    height: 28px;
    padding: 0 28px 0 12px;
    font-size: 12.5px;
    font-weight: 500;
    border-radius: 8px;
    border: none;
    color: var(--text);
    background: var(--fill-2)
      url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10' viewBox='0 0 24 24' fill='none' stroke='%23888' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'><path d='m7 9 5-5 5 5'/><path d='m7 15 5 5 5-5'/></svg>")
      no-repeat right 10px center;
    -webkit-appearance: none;
    appearance: none;
    outline: none;
  }

  .index {
    width: 22px;
    text-align: right;
    font-size: 11.5px;
    color: var(--text-3);
    flex-shrink: 0;
  }

  .entry {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .entry-title {
    font-size: 13px;
  }

  .entry-author {
    font-size: 11.5px;
    color: var(--text-2);
  }

  .length {
    font-size: 11.5px;
    color: var(--text-2);
    flex-shrink: 0;
  }
</style>

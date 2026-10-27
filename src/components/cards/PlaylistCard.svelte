<script lang="ts">
  import { untrack } from 'svelte';
  import CheckList from '../CheckList.svelte';
  import DownloadBar from '../DownloadBar.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import Numerals from '../Numerals.svelte';
  import Tabs from '../Tabs.svelte';
  import Thumb from '../Thumb.svelte';
  import { audioFormats, count, duration } from '../../lib/format';
  import { playlistJobs } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import type { Analysis, AudioFormat, Mode, ParsedLink, PlaylistEntry } from '../../lib/types';

  let { playlist, link }: { playlist: Extract<Analysis, { type: 'playlist' }>; link: ParsedLink } = $props();

  const settings = app.settings;
  let mode = $state<Mode>(untrack(() => (playlist.isMusic ? 'audio' : settings.defaultMode)));
  let quality = $state(settings.defaultQuality);
  let audioFormat = $state<AudioFormat>(settings.audioFormat);
  let selected = $state(untrack(() => new Set(playlist.entries.map((e) => e.id))));

  const qualities = [0, 2160, 1440, 1080, 720, 480].map((q) => ({ id: q, title: q === 0 ? 'MAX' : String(q) }));
  const formats = audioFormats.map((f) => ({ id: f.id, title: f.title.toUpperCase() }));
</script>

<div class="panel">
  <MediaHeader summary={playlist.summary} extra={count(playlist.entries.length, 'video')} />

  <div class="controls">
    <Tabs
      bind:value={mode}
      label="Type"
      options={[
        { id: 'video', title: 'Video' },
        { id: 'audio', title: 'Audio' },
      ]}
    />
  </div>

  {#if mode === 'video'}
    <Numerals bind:value={quality} options={qualities} label="Quality" />
  {:else}
    <Numerals bind:value={audioFormat} options={formats} label="Format" />
  {/if}

  <CheckList items={playlist.entries} key={(e: PlaylistEntry) => e.id} bind:selected>
    {#snippet row(entry: PlaylistEntry)}
      <Thumb src={entry.thumbnail} width={48} height={27} />
      <span class="name truncate">{entry.title}</span>
      <span class="length mono">{duration(entry.duration) ?? ''}</span>
    {/snippet}
  </CheckList>

  <DownloadBar
    title={`Download ${selected.size}`}
    enabled={selected.size > 0}
    ondownload={() => app.enqueue(playlistJobs(playlist, link, selected, mode, quality, audioFormat, settings))}
  />
</div>

<style>
  .name {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    filter: grayscale(1);
  }

  .length {
    font-size: 11px;
    color: var(--text-2);
    flex-shrink: 0;
  }
</style>

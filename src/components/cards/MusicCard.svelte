<script lang="ts">
  import { Music, Sparkles } from '@lucide/svelte';
  import CardFooter from '../CardFooter.svelte';
  import CheckList from '../CheckList.svelte';
  import Footnote from '../Footnote.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import OptionChip from '../OptionChip.svelte';
  import { approx, audioFormats, audioInfo, count, duration, estimateAudio } from '../../lib/format';
  import { artistLine, musicJobs } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import { untrack } from 'svelte';
  import type { Analysis, AudioFormat, SpotifyTrack } from '../../lib/types';

  let { music }: { music: Extract<Analysis, { type: 'music' }> } = $props();

  let format = $state<AudioFormat>(app.settings.musicFormat);
  let selected = $state(untrack(() => new Set(music.tracks.map((t) => t.id))));

  let single = $derived(music.kind === 'track');
  let chosen = $derived(single ? music.tracks : music.tracks.filter((t) => selected.has(t.id)));
  let seconds = $derived(chosen.reduce((sum, t) => sum + (t.durationMs ?? 0) / 1000, 0));
  let badge = $derived(
    music.kind === 'track'
      ? 'Song'
      : music.kind === 'album'
        ? `Album · ${count(music.tracks.length, 'song')}`
        : music.kind === 'playlist'
          ? `Playlist · ${count(music.tracks.length, 'song')}`
          : `Top songs · ${music.tracks.length}`,
  );
  let title = $derived(single ? 'Download song' : chosen.length === 1 ? 'Download 1 song' : `Download ${chosen.length} songs`);
  const order: AudioFormat[] = ['mp3', 'm4a', 'flac', 'opus', 'wav'];
  const formats = order.map((id) => audioFormats.find((f) => f.id === id)!);

  function download() {
    app.enqueue(musicJobs(music, chosen, format));
  }
</script>

<div class="card stack">
  <MediaHeader summary={music.summary} {badge} shape="square" />

  <div class="info">
    <span class="sparkles"><Sparkles size={15} strokeWidth={2} /></span>
    <span>Downly finds each song on YouTube Music, then adds Spotify’s cover art and tags.</span>
  </div>

  <div class="grid" role="radiogroup" aria-label="Audio format">
    {#each formats as option (option.id)}
      <OptionChip
        title={option.title}
        caption={option.short}
        footnote={approx(estimateAudio(option.id, seconds))}
        selected={format === option.id}
        onselect={() => (format = option.id)}
      />
    {/each}
  </div>

  {#if !single}
    <CheckList items={music.tracks} key={(t: SpotifyTrack) => t.id} bind:selected maxHeight={300}>
      {#snippet row(track: SpotifyTrack, index: number)}
        <span class="index tabular">{index + 1}</span>
        <span class="entry">
          <span class="entry-title">
            <span class="truncate">{track.title}</span>
            {#if track.explicit}<span class="explicit" title="Explicit">E</span>{/if}
          </span>
          <span class="entry-author truncate">{artistLine(track)}</span>
        </span>
        {#if duration((track.durationMs ?? 0) / 1000)}<span class="length tabular">{duration((track.durationMs ?? 0) / 1000)}</span>{/if}
      {/snippet}
    </CheckList>
  {/if}

  <CardFooter {title} enabled={chosen.length > 0} ondownload={download}>
    {@const info = audioInfo(format)}
    <Footnote icon={Music} text="{info.title} · {info.detail}" />
  </CardFooter>
</div>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .info {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 9px 12px;
    border-radius: 10px;
    font-size: 13px;
    color: var(--text-2);
    background: var(--tint);
  }

  .sparkles {
    display: inline-flex;
    color: var(--violet);
    flex-shrink: 0;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(104px, 1fr));
    gap: 10px;
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
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 13px;
    min-width: 0;
  }

  .explicit {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 13px;
    height: 13px;
    border-radius: 3px;
    font-size: 9px;
    font-weight: 800;
    color: var(--text-2);
    background: var(--fill-2);
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

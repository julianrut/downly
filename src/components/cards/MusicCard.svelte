<script lang="ts">
  import { untrack } from 'svelte';
  import CheckList from '../CheckList.svelte';
  import DownloadBar from '../DownloadBar.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import Numerals from '../Numerals.svelte';
  import { audioInfo, bytes, count, duration, estimateAudio } from '../../lib/format';
  import { artistLine, musicJobs } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import type { Analysis, AudioFormat, SpotifyTrack } from '../../lib/types';

  let { music }: { music: Extract<Analysis, { type: 'music' }> } = $props();

  let format = $state<AudioFormat>(app.settings.musicFormat);
  let selected = $state(untrack(() => new Set(music.tracks.map((t) => t.id))));

  let single = $derived(music.kind === 'track');
  let chosen = $derived(single ? music.tracks : music.tracks.filter((t) => selected.has(t.id)));
  let seconds = $derived(chosen.reduce((sum, t) => sum + (t.durationMs ?? 0) / 1000, 0));
  const order: AudioFormat[] = ['mp3', 'm4a', 'flac', 'opus', 'wav'];
  const formats = order.map((id) => ({ id, title: audioInfo(id).title.toUpperCase() }));

  let albumArtist = $derived(music.kind === 'album' ? (music.tracks[0]?.artists[0] ?? null) : null);
</script>

<div class="panel">
  <MediaHeader summary={music.summary} extra={single ? null : count(music.tracks.length, 'song')} shape="square" />

  <div class="picker">
    <Numerals bind:value={format} options={formats} label="Format" />
    <div class="label">{audioInfo(format).short}</div>
  </div>

  {#if !single}
    <CheckList items={music.tracks} key={(t: SpotifyTrack) => t.id} bind:selected>
      {#snippet row(track: SpotifyTrack)}
        <span class="track">
          <span class="name truncate">{track.title}</span>
          {#if artistLine(track) !== albumArtist}<span class="artist truncate">{artistLine(track)}</span>{/if}
        </span>
        <span class="length mono">{duration((track.durationMs ?? 0) / 1000) ?? ''}</span>
      {/snippet}
    </CheckList>
  {/if}

  <DownloadBar
    title={single ? 'Download' : `Download ${chosen.length}`}
    size={bytes(estimateAudio(format, seconds))}
    enabled={chosen.length > 0}
    ondownload={() => app.enqueue(musicJobs(music, chosen, format))}
  />
</div>

<style>
  .picker {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .track {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .name {
    font-size: 13px;
    filter: grayscale(1);
  }

  .artist {
    font-size: 12px;
    color: var(--text-2);
  }

  .length {
    font-size: 11px;
    color: var(--text-2);
    flex-shrink: 0;
  }
</style>

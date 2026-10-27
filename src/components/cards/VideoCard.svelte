<script lang="ts">
  import { BadgeCheck, CircleAlert, ListVideo, Music, WandSparkles, ChevronRight } from '@lucide/svelte';
  import CardFooter from '../CardFooter.svelte';
  import Footnote from '../Footnote.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import ModePicker from '../ModePicker.svelte';
  import OptionChip from '../OptionChip.svelte';
  import Segmented from '../Segmented.svelte';
  import { approx, audioInfo, bytes } from '../../lib/format';
  import { audioJob, defaultTier, videoJob } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import { untrack } from 'svelte';
  import type { Analysis, AudioFormat, Mode, VideoContainer } from '../../lib/types';

  let { video }: { video: Extract<Analysis, { type: 'video' }> } = $props();

  const settings = app.settings;
  let mode = $state<Mode>(untrack(() => (video.isMusic || !video.hasVideo ? 'audio' : settings.defaultMode)));
  let container = $state<VideoContainer>(settings.videoContainer);
  let audioFormat = $state<AudioFormat>(settings.audioFormat);
  let tier = $state<number | null>(null);

  let effectiveMode = $derived<Mode>(video.hasVideo ? mode : 'audio');
  let choices = $derived(container === 'mp4' ? video.mp4Choices : video.mkvChoices);
  let selected = $derived(choices.find((c) => c.tier === tier) ?? choices.find((c) => c.tier === defaultTier(choices, settings.defaultQuality)) ?? null);
  let vertical = $derived(choices[0]?.isVertical ?? false);
  let audioOption = $derived(video.audioOptions.find((o) => o.format === audioFormat));
  let footerSize = $derived(effectiveMode === 'video' ? bytes(selected?.estimatedBytes) : bytes(audioOption?.estimatedBytes));

  const codecNames: Record<string, string> = { h264: 'H.264', hevc: 'HEVC', vp9: 'VP9', av1: 'AV1', other: 'Video' };
  const audioNames: Record<string, string> = { aac: 'AAC', opus: 'Opus', mp3: 'MP3' };

  function caption(choice: (typeof choices)[number]) {
    return choice.caption;
  }

  function download() {
    if (effectiveMode === 'video' && selected) {
      app.enqueue([videoJob(video, selected, container, settings.appleCompatible)]);
    } else {
      app.enqueue([audioJob(video, audioFormat)]);
    }
  }
</script>

<div class="card stack">
  <MediaHeader summary={video.summary} badge={video.isLive ? 'Live' : null} shape={vertical ? 'portrait' : 'wide'} />

  {#if video.playlistUrl}
    <button class="playlist" onclick={() => app.openPlaylist(video.playlistUrl!)}>
      <ListVideo size={15} strokeWidth={2} />
      <span>This video is part of a playlist</span>
      <span class="show gradient-text">Show all</span>
      <ChevronRight size={14} strokeWidth={2.4} />
    </button>
  {/if}

  <div class="controls">
    {#if video.hasVideo}
      <ModePicker bind:value={mode} />
    {/if}
    <div class="spacer"></div>
    {#if effectiveMode === 'video'}
      <Segmented
        bind:value={container}
        label="Container"
        options={[
          { id: 'mp4', title: 'MP4' },
          { id: 'mkv', title: 'MKV' },
        ]}
      />
    {/if}
  </div>

  {#if effectiveMode === 'video'}
    {#if choices.length === 0}
      <Footnote icon={CircleAlert} text="No downloadable video streams were found. Try Audio instead." />
    {:else}
      <div class="grid" role="radiogroup" aria-label="Quality">
        {#each choices as choice (choice.tier)}
          <OptionChip
            title={choice.label}
            caption={caption(choice)}
            footnote={approx(choice.estimatedBytes)}
            badge={choice.isHdr ? 'HDR' : null}
            selected={choice.tier === selected?.tier}
            onselect={() => (tier = choice.tier)}
          />
        {/each}
      </div>
    {/if}
  {:else}
    <div class="grid" role="radiogroup" aria-label="Audio format">
      {#each video.audioOptions as option (option.format)}
        <OptionChip
          title={option.title}
          caption={option.detail}
          footnote={approx(option.estimatedBytes)}
          selected={audioFormat === option.format}
          onselect={() => (audioFormat = option.format)}
        />
      {/each}
    </div>
  {/if}

  <CardFooter title="Download" detail={footerSize} enabled={effectiveMode === 'audio' || selected != null} ondownload={download}>
    {#if effectiveMode === 'video' && selected}
      {#if selected.needsTranscode}
        <Footnote icon={WandSparkles} highlight text="{codecNames[selected.codec] ?? 'This'} stream is converted to HEVC so it plays in QuickTime & Photos" />
      {:else}
        <Footnote
          icon={BadgeCheck}
          text="{container.toUpperCase()} · {codecNames[selected.codec] ?? 'Video'} {selected.muxed || !selected.audioCodec ? 'with sound' : `+ ${audioNames[selected.audioCodec] ?? 'best'} audio`}"
        />
      {/if}
    {:else}
      {@const info = audioInfo(audioFormat)}
      <Footnote icon={Music} text="{info.title} · {info.detail}{info.cover ? ' · with cover art' : ''}" />
    {/if}
  </CardFooter>
</div>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .playlist {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    align-self: flex-start;
    padding: 8px 12px;
    font-size: 13px;
    border-radius: 10px;
    color: var(--text);
    background: var(--tint);
    transition: background 0.15s ease;
  }

  .playlist:hover {
    background: var(--tint-strong);
  }

  .show {
    font-weight: 600;
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
    grid-template-columns: repeat(auto-fill, minmax(112px, 1fr));
    gap: 10px;
  }
</style>

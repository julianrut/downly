<script lang="ts">
  import { untrack } from 'svelte';
  import DownloadBar from '../DownloadBar.svelte';
  import MediaHeader from '../MediaHeader.svelte';
  import Numerals from '../Numerals.svelte';
  import Tabs from '../Tabs.svelte';
  import { audioInfo, bytes } from '../../lib/format';
  import { audioJob, defaultTier, videoJob } from '../../lib/jobs';
  import { app } from '../../lib/state.svelte';
  import type { Analysis, AudioFormat, Mode, VideoContainer } from '../../lib/types';

  let { video }: { video: Extract<Analysis, { type: 'video' }> } = $props();

  const settings = app.settings;
  const codecs: Record<string, string> = { h264: 'H.264', hevc: 'HEVC', vp9: 'VP9', av1: 'AV1' };

  let mode = $state<Mode>(untrack(() => (video.isMusic || !video.hasVideo ? 'audio' : settings.defaultMode)));
  let container = $state<VideoContainer>(settings.videoContainer);
  let audioFormat = $state<AudioFormat>(settings.audioFormat);
  let tier = $state<number | null>(null);

  let effectiveMode = $derived<Mode>(video.hasVideo ? mode : 'audio');
  let choices = $derived(container === 'mp4' ? video.mp4Choices : video.mkvChoices);
  let fallback = $derived(defaultTier(choices, settings.defaultQuality));
  let selected = $derived(choices.find((c) => c.tier === tier) ?? choices.find((c) => c.tier === fallback) ?? null);
  let vertical = $derived(choices[0]?.isVertical ?? false);
  let audioOption = $derived(video.audioOptions.find((o) => o.format === audioFormat));
  let size = $derived(effectiveMode === 'video' ? bytes(selected?.estimatedBytes) : bytes(audioOption?.estimatedBytes));

  let tierValue = $derived(selected?.tier ?? 0);
  let tiers = $derived(choices.map((c) => ({ id: c.tier, title: String(c.tier) })));
  let formats = $derived(video.audioOptions.map((o) => ({ id: o.format, title: o.title.toUpperCase() })));

  let detail = $derived.by(() => {
    if (effectiveMode === 'audio') return audioInfo(audioFormat).short;
    if (!selected) return '';
    const parts: string[] = [];
    if (selected.fps) parts.push(`${selected.fps} fps`);
    if (selected.isHdr) parts.push('HDR');
    const codec = codecs[selected.codec] ?? selected.codec.toUpperCase();
    parts.push(selected.needsTranscode ? `${codec} → HEVC` : codec);
    return parts.join('  ·  ');
  });
</script>

<div class="panel">
  <MediaHeader summary={video.summary} extra={video.isLive ? 'Live' : null} shape={vertical ? 'portrait' : 'wide'} />

  <div class="controls">
    {#if video.hasVideo}
      <Tabs
        bind:value={mode}
        label="Type"
        options={[
          { id: 'video', title: 'Video' },
          { id: 'audio', title: 'Audio' },
        ]}
      />
    {:else}
      <span></span>
    {/if}
    {#if effectiveMode === 'video'}
      <Tabs
        bind:value={container}
        label="Container"
        options={[
          { id: 'mp4', title: 'MP4' },
          { id: 'mkv', title: 'MKV' },
        ]}
      />
    {/if}
  </div>

  <div class="picker">
    {#if effectiveMode === 'video'}
      {#if choices.length}
        <Numerals options={tiers} label="Quality" bind:value={() => tierValue, (v) => (tier = v)} />
      {:else}
        <span class="label">No video streams</span>
      {/if}
    {:else}
      <Numerals bind:value={audioFormat} options={formats} label="Audio format" />
    {/if}
    {#if detail}<div class="label">{detail}</div>{/if}
  </div>

  {#if video.playlistUrl}
    <button class="text-button playlist" onclick={() => app.openPlaylist(video.playlistUrl!)}>Open playlist →</button>
  {/if}

  <DownloadBar {size} enabled={effectiveMode === 'audio' || selected != null} ondownload={() => {
    if (effectiveMode === 'video' && selected) app.enqueue([videoJob(video, selected, container, settings.appleCompatible)]);
    else app.enqueue([audioJob(video, audioFormat)]);
  }} />
</div>

<style>
  .picker {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .playlist {
    align-self: flex-start;
    margin: -10px 0;
  }
</style>

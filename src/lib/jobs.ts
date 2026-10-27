import { audioInfo, count, platformNames, tierLabel } from './format';
import type {
  Analysis,
  AudioFormat,
  DownloadJob,
  GalleryItem,
  ParsedLink,
  Settings,
  SpotifyTrack,
  VideoChoice,
  VideoContainer,
} from './types';

type VideoAnalysis = Extract<Analysis, { type: 'video' }>;
type PlaylistAnalysis = Extract<Analysis, { type: 'playlist' }>;
type MusicAnalysis = Extract<Analysis, { type: 'music' }>;
type GalleryAnalysis = Extract<Analysis, { type: 'gallery' }>;

function newId(): string {
  return typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

export function videoJob(video: VideoAnalysis, choice: VideoChoice, container: VideoContainer, appleCompatible: boolean): DownloadJob {
  const summary = video.summary;
  return {
    id: newId(),
    title: summary.title,
    subtitle: summary.author ?? platformNames[summary.platform],
    detail: `${choice.label} · ${container.toUpperCase()}`,
    thumbnail: summary.thumbnail,
    platform: summary.platform,
    kind: {
      type: 'video',
      url: video.sourceUrl,
      selector: choice.selector,
      sort: null,
      container,
      appleCompatible: appleCompatible && container === 'mp4',
      expectedSizes: choice.expectedSizes ?? {},
    },
  };
}

export function audioJob(video: VideoAnalysis, format: AudioFormat): DownloadJob {
  const summary = video.summary;
  const info = audioInfo(format);
  return {
    id: newId(),
    title: summary.title,
    subtitle: summary.author ?? platformNames[summary.platform],
    detail: `${info.title} · ${info.short}`,
    thumbnail: summary.thumbnail,
    platform: summary.platform,
    kind: { type: 'audio', url: video.sourceUrl, format, squareCover: video.isMusic },
  };
}

export function playlistPlan(tier: number | null, container: VideoContainer, appleCompatible: boolean) {
  const apple = appleCompatible && container === 'mp4';
  const audioSort = container === 'mp4' || apple ? 'acodec:aac' : 'acodec:opus';
  const codec = apple ? ',vcodec:h264' : '';
  if (!tier) return { selector: 'bv*+ba/b', sort: `res,fps${codec},${audioSort}` };
  return {
    selector: `bv*[height<=${tier}]+ba/b[height<=${tier}]/bv*+ba/b`,
    sort: `res:${tier},fps${codec},${audioSort}`,
  };
}

export function playlistJobs(
  playlist: PlaylistAnalysis,
  link: ParsedLink | null,
  ids: Set<string>,
  mode: 'video' | 'audio',
  quality: number,
  format: AudioFormat,
  settings: Settings,
): DownloadJob[] {
  const platform = playlist.summary.platform;
  const plan = playlistPlan(quality || null, settings.videoContainer, settings.appleCompatible);
  const qualityLabel = quality ? tierLabel(quality) : 'Best';
  const info = audioInfo(format);
  return playlist.entries
    .filter((entry) => ids.has(entry.id))
    .map((entry) => {
      const url = entry.url.startsWith('http')
        ? entry.url
        : platform === 'youtube'
          ? `https://www.youtube.com/watch?v=${entry.id}`
          : entry.url;
      const base = {
        id: newId(),
        title: entry.title,
        subtitle: entry.author ?? playlist.summary.title,
        thumbnail: entry.thumbnail,
        platform,
      };
      if (mode === 'video') {
        return {
          ...base,
          detail: `${qualityLabel} · ${settings.videoContainer.toUpperCase()}`,
          kind: {
            type: 'video' as const,
            url,
            selector: plan.selector,
            sort: plan.sort,
            container: settings.videoContainer,
            appleCompatible: settings.appleCompatible && settings.videoContainer === 'mp4',
            expectedSizes: {},
          },
        };
      }
      return {
        ...base,
        detail: `${info.title} · ${info.short}`,
        kind: { type: 'audio' as const, url, format, squareCover: playlist.isMusic || Boolean(link?.isMusic) },
      };
    });
}

export function artistLine(track: SpotifyTrack): string {
  return track.artists.length ? track.artists.join(', ') : 'Unknown Artist';
}

export function musicJobs(music: MusicAnalysis, tracks: SpotifyTrack[], format: AudioFormat): DownloadJob[] {
  const single = music.kind === 'track';
  const folder = single ? null : music.summary.title;
  const info = audioInfo(format);
  return tracks.map((track) => ({
    id: newId(),
    title: track.title,
    subtitle: artistLine(track),
    detail: `${info.title} · ${info.short}`,
    thumbnail: track.cover ?? music.summary.thumbnail,
    platform: 'spotify',
    kind: { type: 'spotify', track, format, folder },
  }));
}

export function describeItems(items: GalleryItem[]): string | null {
  const photos = items.filter((i) => i.kind === 'photo').length;
  const videos = items.filter((i) => i.kind === 'video').length;
  const audio = items.filter((i) => i.kind === 'audio').length;
  const parts: string[] = [];
  if (photos) parts.push(count(photos, 'photo'));
  if (videos) parts.push(count(videos, 'video'));
  if (audio) parts.push('sound');
  return parts.length ? parts.join(' · ') : null;
}

export function galleryJob(gallery: GalleryAnalysis, items: GalleryItem[]): DownloadJob {
  return {
    id: newId(),
    title: gallery.summary.title,
    subtitle: gallery.summary.author ?? platformNames[gallery.summary.platform],
    detail: describeItems(items) ?? 'Media',
    thumbnail: items[0]?.thumbnail ?? (items[0]?.kind === 'photo' ? items[0].url : null) ?? gallery.summary.thumbnail,
    platform: gallery.summary.platform,
    kind: { type: 'gallery', items, folder: gallery.folderName },
  };
}

export function defaultTier(choices: VideoChoice[], preferred: number): number | null {
  if (!choices.length) return null;
  if (preferred <= 0) return choices[0].tier;
  return (choices.find((c) => c.tier <= preferred) ?? choices[choices.length - 1]).tier;
}

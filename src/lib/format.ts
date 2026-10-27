import type { AudioFormat, Platform } from './types';

export function bytes(value: number | null | undefined): string | null {
  if (!value || value <= 0) return null;
  if (value >= 1e9) return `${(value / 1e9).toFixed(value >= 1e10 ? 1 : 2)} GB`;
  if (value >= 1e6) return `${(value / 1e6).toFixed(value >= 1e8 ? 0 : 1)} MB`;
  return `${Math.max(1, Math.round(value / 1e3))} KB`;
}

export function approx(value: number | null | undefined): string | null {
  const text = bytes(value);
  return text ? `≈ ${text}` : null;
}

export function speed(value: number | null | undefined): string | null {
  const text = bytes(value);
  return text ? `${text}/s` : null;
}

export function duration(seconds: number | null | undefined): string | null {
  if (!seconds || !isFinite(seconds) || seconds <= 0) return null;
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

export function eta(seconds: number | null | undefined): string | null {
  if (!seconds || !isFinite(seconds) || seconds <= 0) return null;
  if (seconds < 60) return `${Math.round(seconds)}s left`;
  return `${duration(seconds)} left`;
}

export function count(value: number, singular: string, plural?: string): string {
  return `${value} ${value === 1 ? singular : (plural ?? `${singular}s`)}`;
}

export const platformNames: Record<Platform, string> = {
  youtube: 'YouTube',
  spotify: 'Spotify',
  instagram: 'Instagram',
  tiktok: 'TikTok',
  web: 'Web',
};

export const audioFormats: { id: AudioFormat; title: string; short: string; detail: string; cover: boolean; bitrate: number }[] = [
  { id: 'mp3', title: 'MP3', short: '320 kbps', detail: 'Plays everywhere', cover: true, bitrate: 320_000 },
  { id: 'm4a', title: 'M4A', short: 'AAC', detail: 'Great for Apple devices', cover: true, bitrate: 256_000 },
  { id: 'opus', title: 'Opus', short: 'Original', detail: 'Untouched source audio', cover: true, bitrate: 160_000 },
  { id: 'flac', title: 'FLAC', short: 'Lossless', detail: 'Lossless, larger files', cover: true, bitrate: 900_000 },
  { id: 'wav', title: 'WAV', short: 'PCM', detail: 'Uncompressed, for editing', cover: false, bitrate: 1_411_200 },
];

export function audioInfo(id: AudioFormat) {
  return audioFormats.find((f) => f.id === id) ?? audioFormats[0];
}

export function estimateAudio(id: AudioFormat, seconds: number | null | undefined): number | null {
  if (!seconds || seconds <= 0) return null;
  return Math.round((seconds * audioInfo(id).bitrate) / 8);
}

export function tierLabel(tier: number): string {
  switch (tier) {
    case 4320:
      return '8K';
    case 2880:
      return '5K';
    case 2160:
      return '4K';
    case 1440:
      return '1440p';
    default:
      return `${tier}p`;
  }
}

export function tierCaption(tier: number): string {
  switch (tier) {
    case 4320:
      return '4320p';
    case 2880:
      return '2880p';
    case 2160:
      return '2160p';
    case 1440:
      return 'Quad HD';
    case 1080:
      return 'Full HD';
    case 720:
      return 'HD';
    default:
      return 'SD';
  }
}

export function shortUrl(url: string): string {
  try {
    const parsed = new URL(url);
    const path = parsed.pathname === '/' ? '' : parsed.pathname;
    return `${parsed.hostname.replace(/^www\./, '')}${path}${parsed.search}`;
  } catch {
    return url;
  }
}

export function homePath(path: string): string {
  const match = path.match(/^\/Users\/[^/]+/) ?? path.match(/^\/home\/[^/]+/);
  return match ? `~${path.slice(match[0].length)}` : path;
}

export function folderName(path: string): string {
  const parts = path.split('/').filter(Boolean);
  return parts[parts.length - 1] ?? path;
}

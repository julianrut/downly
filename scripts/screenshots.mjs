import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const out = process.argv[2] ?? 'snapshots';
const port = 4173;

const shots = [
  ['01-setup', 'demo=setup', 'light'],
  ['02-home', 'demo=home', 'light'],
  ['03-video', 'demo=video', 'light'],
  ['04-loading', 'demo=loading', 'light'],
  ['05-downloads', 'demo=downloads', 'light'],
  ['06-spotify-dark', 'demo=spotify', 'dark'],
  ['07-instagram-dark', 'demo=gallery', 'dark'],
  ['08-video-dark', 'demo=video', 'dark'],
  ['09-error', 'demo=error', 'light'],
  ['10-settings-formats', 'window=settings&tab=formats', 'light', 520, 560],
  ['11-settings-accounts', 'window=settings&tab=accounts', 'dark', 520, 330],
  ['12-tiktok', 'demo=tiktok', 'light'],
  ['13-profile-dark', 'demo=profile', 'dark'],
];

const server = spawn('npx', ['vite', 'preview', '--port', String(port), '--strictPort'], { stdio: 'ignore' });

async function waitForServer() {
  for (let i = 0; i < 60; i++) {
    try {
      const response = await fetch(`http://localhost:${port}/`);
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error('preview server did not start');
}

try {
  await waitForServer();
  await mkdir(out, { recursive: true });
  const browser = await chromium.launch();
  for (const [name, query, scheme, width = 760, height = 700] of shots) {
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 2, colorScheme: scheme });
    page.on('pageerror', (error) => console.error(name, error.message));
    await page.goto(`http://localhost:${port}/?${query}`);
    await page.waitForTimeout(1600);
    await page.screenshot({ path: `${out}/${name}.png` });
    await page.close();
    console.log('captured', name);
  }
  await browser.close();
} finally {
  server.kill();
}

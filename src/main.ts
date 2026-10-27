import './app.css';
import { mount } from 'svelte';
import { isTauri, windowLabel } from './lib/api';

if (!isTauri) document.documentElement.classList.add('browser');

document.addEventListener('contextmenu', (event) => {
  const target = event.target as HTMLElement | null;
  if (!target?.closest('input, textarea, .selectable')) event.preventDefault();
});

async function start() {
  const label = await windowLabel();
  const target = document.getElementById('app')!;
  if (label === 'settings') {
    const { default: SettingsApp } = await import('./settings/SettingsApp.svelte');
    document.title = 'Settings';
    mount(SettingsApp, { target });
  } else {
    const { default: App } = await import('./App.svelte');
    mount(App, { target });
  }
}

start();

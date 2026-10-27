<script lang="ts">
  let {
    title,
    caption,
    footnote = null,
    badge = null,
    selected,
    onselect,
  }: {
    title: string;
    caption: string;
    footnote?: string | null;
    badge?: string | null;
    selected: boolean;
    onselect: () => void;
  } = $props();
</script>

<button class="chip" class:selected role="radio" aria-checked={selected} onclick={onselect}>
  <span class="title-row">
    <span class="title rounded" class:gradient-text={selected}>{title}</span>
    {#if badge}<span class="badge">{badge}</span>{/if}
  </span>
  <span class="caption truncate">{caption}</span>
  {#if footnote}<span class="footnote tabular truncate">{footnote}</span>{/if}
</button>

<style>
  .chip {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    min-width: 0;
    padding: 9px 12px 10px;
    text-align: left;
    border-radius: var(--radius-control);
    background: var(--fill);
    box-shadow: inset 0 0 0 1px var(--hairline);
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease,
      transform 0.18s var(--ease-out);
  }

  .chip:hover {
    background: var(--fill-2);
  }

  .chip:active {
    transform: scale(0.98);
  }

  .chip.selected {
    background: var(--tint-strong);
    box-shadow: none;
  }

  .chip.selected::before {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
    padding: 1.6px;
    background: var(--brand);
    -webkit-mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    -webkit-mask-composite: xor;
    mask-composite: exclude;
    pointer-events: none;
  }

  .title-row {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .title {
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--text);
    line-height: 1.25;
  }

  .badge {
    font-size: 9px;
    font-weight: 800;
    letter-spacing: 0.02em;
    padding: 2px 5px;
    border-radius: 999px;
    color: var(--text-2);
    background: var(--fill-2);
  }

  .caption {
    font-size: 11.5px;
    color: var(--text-2);
    max-width: 100%;
  }

  .footnote {
    font-size: 11px;
    color: var(--text-3);
    max-width: 100%;
  }
</style>

<script lang="ts">
  let { fraction, height = 2 }: { fraction: number | null | undefined; height?: number } = $props();
  let clamped = $derived(fraction == null ? null : Math.min(1, Math.max(0, fraction)));
</script>

<div class="track" style:height="{height}px" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={clamped == null ? undefined : Math.round(clamped * 100)}>
  {#if clamped == null}
    <div class="sweep"></div>
  {:else}
    <div class="fill" style:width="{clamped * 100}%"></div>
  {/if}
</div>

<style>
  .track {
    position: relative;
    width: 100%;
    border-radius: 999px;
    background: var(--line);
    overflow: hidden;
  }

  .fill {
    height: 100%;
    background: var(--text);
    transition: width 0.3s var(--ease);
  }

  .sweep {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 30%;
    background: var(--text);
    animation: sweep 1.1s ease-in-out infinite alternate;
  }

  @keyframes sweep {
    from {
      left: 0;
    }
    to {
      left: 70%;
    }
  }
</style>

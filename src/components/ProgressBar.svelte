<script lang="ts">
  let { fraction, height = 5 }: { fraction: number | null | undefined; height?: number } = $props();
  let clamped = $derived(fraction == null ? null : Math.min(1, Math.max(0, fraction)));
</script>

<div class="track" style:height="{height}px" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={clamped == null ? undefined : Math.round(clamped * 100)}>
  {#if clamped == null}
    <div class="sweep"></div>
  {:else}
    <div class="fill" style:width="max({height}px, {clamped * 100}%)"></div>
  {/if}
</div>

<style>
  .track {
    position: relative;
    width: 100%;
    border-radius: 999px;
    background: var(--fill-2);
    overflow: hidden;
  }

  .fill {
    height: 100%;
    border-radius: inherit;
    background: var(--brand-h);
    background-size: 200% 100%;
    transition: width 0.35s var(--ease-out);
    animation: flow 2.4s linear infinite;
  }

  .sweep {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 30%;
    border-radius: inherit;
    background: var(--brand-h);
    animation: sweep 1.15s ease-in-out infinite alternate;
  }

  @keyframes sweep {
    from {
      left: 0;
    }
    to {
      left: 70%;
    }
  }

  @keyframes flow {
    from {
      background-position: 0% 0;
    }
    to {
      background-position: -200% 0;
    }
  }
</style>

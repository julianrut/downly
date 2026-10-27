<script lang="ts">
  let { on, size = 10, light = false }: { on: boolean; size?: number; light?: boolean } = $props();
</script>

<span class="mark" class:on class:light style:width="{size}px" style:height="{size}px"></span>

<style>
  .mark {
    display: inline-block;
    flex-shrink: 0;
    border-radius: 1px;
    box-shadow: inset 0 0 0 1px var(--text-3);
    transition:
      background 0.12s ease,
      box-shadow 0.12s ease;
  }

  .mark.on {
    background: var(--ink);
    box-shadow: inset 0 0 0 1px var(--ink);
  }

  .mark.light {
    box-shadow: inset 0 0 0 1.25px #fff;
    background: rgba(0, 0, 0, 0.15);
  }

  .mark.light.on {
    background: #fff;
  }
</style>

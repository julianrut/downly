<script lang="ts">
  let { checked = $bindable(), disabled = false, label, onchange }: { checked: boolean; disabled?: boolean; label: string; onchange?: (value: boolean) => void } = $props();

  function toggle() {
    if (disabled) return;
    checked = !checked;
    onchange?.(checked);
  }
</script>

<button class="switch" class:on={checked} role="switch" aria-checked={checked} aria-label={label} {disabled} onclick={toggle}>
  <span class="knob"></span>
</button>

<style>
  .switch {
    position: relative;
    width: 28px;
    height: 16px;
    border-radius: 2px;
    flex-shrink: 0;
    box-shadow: inset 0 0 0 1px var(--line-strong);
    transition:
      background 0.18s ease,
      box-shadow 0.18s ease;
  }

  .switch.on {
    background: var(--ink);
    box-shadow: inset 0 0 0 1px var(--ink);
  }

  .switch:disabled {
    opacity: 0.35;
  }

  .knob {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 10px;
    height: 10px;
    border-radius: 1px;
    background: var(--text-2);
    transition:
      transform 0.22s var(--ease),
      background 0.18s ease;
  }

  .switch.on .knob {
    transform: translateX(12px);
    background: var(--on-ink);
  }
</style>

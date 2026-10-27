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
    width: 32px;
    height: 19px;
    border-radius: 999px;
    background: var(--fill-3);
    box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.06);
    transition: background 0.22s ease;
    flex-shrink: 0;
  }

  .switch.on {
    background: var(--brand-h);
  }

  .switch:disabled {
    opacity: 0.4;
  }

  .knob {
    position: absolute;
    top: 2px;
    left: 2px;
    width: 15px;
    height: 15px;
    border-radius: 50%;
    background: #fff;
    box-shadow:
      0 1px 2.5px rgba(0, 0, 0, 0.25),
      0 0 0 0.5px rgba(0, 0, 0, 0.04);
    transition: transform 0.28s var(--ease-spring);
  }

  .switch.on .knob {
    transform: translateX(13px);
  }

  .switch:active:not(:disabled) .knob {
    width: 18px;
  }

  .switch.on:active:not(:disabled) .knob {
    transform: translateX(10px);
  }
</style>

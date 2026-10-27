<script lang="ts">
  let {
    title = 'Download',
    size = null,
    enabled = true,
    ondownload,
  }: {
    title?: string;
    size?: string | null;
    enabled?: boolean;
    ondownload: () => void;
  } = $props();
</script>

<button class="bar-button" disabled={!enabled} onclick={ondownload} data-default-action>
  <span>{title}</span>
  {#if size}<span class="size">{size}</span>{/if}
</button>

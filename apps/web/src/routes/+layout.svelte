<script lang="ts">
  import "../app.css";
  let { children } = $props();
  // Marks the page interactive, so browser tests never click before Svelte attaches handlers
  // (tests/e2e/fixtures.ts).
  $effect(() => {
    document.documentElement.dataset.hydrated = "";
  });
</script>

{@render children()}

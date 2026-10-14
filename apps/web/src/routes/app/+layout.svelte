<script lang="ts">let { children } = $props();</script>
<header><a href="/">Platform starter</a><nav><a href="/app/items">Items</a></nav></header>
{@render children()}
<style>
  header { display: flex; gap: 2rem; align-items: center; justify-content: space-between; padding: 1rem max(1.25rem, calc((100vw - 960px)/2)); background: white; border-bottom: 1px solid #dce5e8; }
  header a { font-weight: 700; text-decoration: none; }
</style>

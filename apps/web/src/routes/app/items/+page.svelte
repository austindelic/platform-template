<script lang="ts">
  import type { ActionData, PageData } from "./$types";
  let { data, form }: { data: PageData; form: ActionData } = $props();
</script>
<svelte:head><title>Items · Platform starter</title></svelte:head>
<main>
  <p class="muted">EXAMPLE FEATURE</p>
  <h1>Items</h1>
  <p>These records travel through a route, a server operation, and the shared database package.</p>
  <section class="card">
    <h2>Add an item</h2>
    <form method="POST">
      <label for="title">Title</label>
      <div class="row"><input id="title" name="title" maxlength="120" required /><button>Add item</button></div>
    </form>
    {#if form?.message}<p role="status">{form.message}</p>{/if}
  </section>
  <section class="card list">
    <h2>Saved items</h2>
    {#if data.items.length === 0}<p class="muted">No items yet.</p>{/if}
    <ul>{#each data.items as item (item.id)}<li>{item.title}</li>{/each}</ul>
  </section>
</main>
<style>
  h1 { font-size: 2.5rem; margin-top: .2rem; }
  .row { display: flex; gap: .75rem; margin-top: .5rem; }
  input { flex: 1; }
  .list { margin-top: 1rem; }
  li { padding: .6rem 0; border-bottom: 1px solid #e6ecee; }
  ul { padding-left: 1.2rem; }
</style>

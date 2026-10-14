import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: process.env.DOCS_SITE_URL ?? "https://docs.example.test",
  integrations: [starlight({
    title: "Platform starter handbook",
    sidebar: [{ label: "Guides", items: [{ label: "Start here", slug: "start" }] }],
  })],
});

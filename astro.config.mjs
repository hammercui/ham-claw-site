import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

const siteUrl = process.env.SITE_URL?.trim() || "https://hammercui.github.io";
const basePath = process.env.BASE_PATH?.trim() || "/";

export default defineConfig({
  site: siteUrl,
  base: basePath,
  output: "static",
  integrations: [sitemap()],
  build: {
    format: "directory"
  },
  vite: {
    build: {
      cssMinify: "lightningcss"
    }
  }
});

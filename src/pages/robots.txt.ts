import type { APIRoute } from "astro";
import { withBase } from "../lib/paths";

export const prerender = true;

export const GET: APIRoute = ({ site }) => {
  const sitemapUrl = new URL(withBase("/sitemap-index.xml"), site);

  return new Response(`User-agent: *\nAllow: /\n\nSitemap: ${sitemapUrl}\n`, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8"
    }
  });
};

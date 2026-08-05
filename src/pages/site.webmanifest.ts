import type { APIRoute } from "astro";
import { withBase } from "../lib/paths";

export const prerender = true;

export const GET: APIRoute = () => {
  const manifest = {
    name: "龙虾卫士",
    short_name: "龙虾卫士",
    description: "OpenClaw Windows 控制中心",
    lang: "zh-CN",
    start_url: withBase("/"),
    display: "browser",
    background_color: "#ffffff",
    theme_color: "#ff7100",
    icons: [
      {
        src: withBase("/assets/brand-mark.png"),
        sizes: "256x256",
        type: "image/png"
      }
    ]
  };

  return new Response(JSON.stringify(manifest), {
    headers: {
      "Content-Type": "application/manifest+json; charset=utf-8"
    }
  });
};

import { withBase } from "../lib/paths";

const githubUrl = import.meta.env.PUBLIC_GITHUB_URL?.trim() || null;
const supportEmail = import.meta.env.PUBLIC_SUPPORT_EMAIL?.trim() || null;

function safeHttpsUrl(value: string | undefined) {
  if (!value?.trim()) return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

const previewApplyUrl = safeHttpsUrl(import.meta.env.PUBLIC_PREVIEW_APPLY_URL);

export const site = {
  name: "龙虾卫士",
  description: "让 OpenClaw 稳定运行，人人都能用。安装、供应商、聊天软件、Skills、定时任务和故障恢复，一个桌面工具完成。",
  githubUrl,
  supportEmail,
  previewApplyUrl
} as const;

export const navigation = [
  { label: "产品能力", href: withBase("/#capabilities") },
  { label: "工作方式", href: withBase("/#workflow") },
  { label: "安全与更新", href: withBase("/#trust") },
  { label: "常见问题", href: withBase("/#faq") }
] as const;

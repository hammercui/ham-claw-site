import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcRoot = path.join(root, "src");

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(full));
    else files.push(full);
  }
  return files;
}

test("required public pages exist", async () => {
  for (const page of ["index.astro", "guide.astro", "changelog.astro", "privacy.astro", "security.astro", "404.astro"]) {
    const source = await readFile(path.join(srcRoot, "pages", page), "utf8");
    assert(source.length > 100, `${page} 缺失或为空`);
  }
});

test("homepage contains exactly the five approved diagnosis rows", async () => {
  const source = await readFile(path.join(srcRoot, "pages", "index.astro"), "utf8");
  for (const label of ["网关未运行", "端口冲突", "模型不可用", "聊天无回复", "配置无效"]) {
    assert.equal(source.split(`\"${label}\"`).length - 1, 1, `${label} 必须且只能定义一次`);
  }
});

test("source contains no fake owner, placeholder contact, remote font, or tracking script", async () => {
  const files = await filesUnder(srcRoot);
  const source = (await Promise.all(files.map((file) => readFile(file, "utf8")))).join("\n");
  assert(!/github\.com\/OWNER/i.test(source), "源码包含假 GitHub owner");
  assert(!/example\.invalid/i.test(source), "源码包含占位联系方式");
  assert(!/fonts\.(googleapis|gstatic)\.com/i.test(source), "禁止远程字体");
  assert(!/(google-analytics|googletagmanager|clarity\.ms|segment\.com)/i.test(source), "禁止未声明追踪脚本");
});

test("download filename and inaccessible state remain explicit", async () => {
  const guide = await readFile(path.join(srcRoot, "pages", "guide.astro"), "utf8");
  const component = await readFile(path.join(srcRoot, "components", "DownloadAction.astro"), "utf8");
  assert.match(guide, /OpenClawConsole\.exe/);
  assert.match(component, /button--unavailable/);
  assert.match(component, /disabled/);
});

test("responsive, focus, and reduced motion contracts are present", async () => {
  const css = await readFile(path.join(srcRoot, "styles", "global.css"), "utf8");
  assert.match(css, /:focus-visible/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /max-width:\s*767px/);
  assert.match(css, /min-height:\s*44px/);
});

test("GitHub project Pages base path is configurable and applied to public links", async () => {
  const config = await readFile(path.join(root, "astro.config.mjs"), "utf8");
  const workflow = await readFile(path.join(root, ".github", "workflows", "pages.yml"), "utf8");
  const pathHelper = await readFile(path.join(srcRoot, "lib", "paths.ts"), "utf8");
  const astroFiles = (await filesUnder(srcRoot)).filter((file) => file.endsWith(".astro"));
  const astroSource = (await Promise.all(astroFiles.map((file) => readFile(file, "utf8")))).join("\n");

  assert.match(config, /base:\s*basePath/);
  assert.match(workflow, /BASE_PATH:\s*\$\{\{ vars\.BASE_PATH \}\}/);
  assert.match(pathHelper, /import\.meta\.env\.BASE_URL/);
  assert(!/(?:href|src)="\/(?!\/)/.test(astroSource), "Astro 模板含绕过 BASE_PATH 的根路径链接");
});

test("published updater public key matches the release intake validator", async () => {
  const security = await readFile(path.join(srcRoot, "pages", "security.astro"), "utf8");
  const validator = await readFile(path.join(root, "scripts", "Test-ReleaseBundle.ps1"), "utf8");
  const keyPattern = /RW[A-Za-z0-9+/]{40,}/g;
  const securityKeys = security.match(keyPattern) ?? [];
  const validatorKeys = validator.match(keyPattern) ?? [];
  assert.equal(securityKeys.length, 1, "安全页必须只公布一把生产更新公钥");
  assert.equal(validatorKeys.length, 1, "发布校验器必须只固定一把生产更新公钥");
  assert.equal(securityKeys[0], validatorKeys[0], "安全页与发布校验器的生产公钥不一致");
});

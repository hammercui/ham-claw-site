import assert from "node:assert/strict";

const EXACT_ASSET = "OpenClawConsole.exe";
const MAX_EXE_BYTES = 256 * 1024 * 1024;
const FORBIDDEN_KEY = /(private.?key|password|credential|access.?token|refresh.?token|api.?key)/i;
const STABLE_SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const SHA256 = /^[a-f0-9]{64}$/;

function assertExactKeys(value, expected) {
  assert.deepEqual(Object.keys(value).sort(), [...expected].sort(), "发布数据包含未声明字段或缺少字段");
}

function scanForbiddenKeys(value, path = "release") {
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    assert(!FORBIDDEN_KEY.test(key), `${path}.${key} 不允许出现在公开发布数据中`);
    scanForbiddenKeys(child, `${path}.${key}`);
  }
}

function assertPlainObject(value) {
  assert(value && typeof value === "object" && !Array.isArray(value), "发布数据必须是 JSON 对象");
}

function assertMessage(value, name) {
  assert.equal(typeof value, "string", `${name} 必须是字符串`);
  assert(value.trim().length > 0 && value.length <= 4000, `${name} 必须为 1–4000 字符`);
  assert(!/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value), `${name} 含控制字符`);
}

export function assertValidPublicRelease(value) {
  assertPlainObject(value);
  scanForbiddenKeys(value);
  assert.equal(value.schemaVersion, 1, "schemaVersion 必须为 1");
  assert.equal(value.platform, "windows-x86_64", "首发只允许 windows-x86_64");
  assert(["preparing", "available", "suspended"].includes(value.status), "发布状态不受支持");

  if (value.status === "preparing") {
    assertExactKeys(value, ["schemaVersion", "status", "platform", "message"]);
    assertMessage(value.message, "message");
    return value;
  }

  if (value.status === "suspended") {
    assertExactKeys(value, ["schemaVersion", "status", "platform", "message", "reason"]);
    assertMessage(value.message, "message");
    assertMessage(value.reason, "reason");
    return value;
  }

  assertExactKeys(value, [
    "schemaVersion",
    "status",
    "platform",
    "version",
    "publishedAt",
    "bytes",
    "downloadUrl",
    "sha256",
    "notes"
  ]);
  assert.match(value.version, STABLE_SEMVER, "version 必须是稳定 SemVer，不能使用 prerelease 后缀");
  assert(Number.isFinite(Date.parse(value.publishedAt)), "publishedAt 必须是有效日期");
  assert(Number.isSafeInteger(value.bytes) && value.bytes > 0 && value.bytes <= MAX_EXE_BYTES, "bytes 超出允许范围");
  assert.match(value.sha256, SHA256, "sha256 必须是 64 位小写十六进制");
  assertMessage(value.notes, "notes");

  const url = new URL(value.downloadUrl);
  assert.equal(url.protocol, "https:", "downloadUrl 必须使用 HTTPS");
  assert.equal(url.hostname, "github.com", "首版 downloadUrl 必须指向 github.com");
  assert(!url.pathname.includes("OWNER"), "downloadUrl 仍包含占位 owner");
  const expectedSuffix = `/releases/download/v${value.version}/${EXACT_ASSET}`;
  assert(url.pathname.endsWith(expectedSuffix), `downloadUrl 必须指向不可变 Tag 下的 ${EXACT_ASSET}`);
  assert.equal(url.search, "", "downloadUrl 禁止查询参数");
  assert.equal(url.hash, "", "downloadUrl 禁止片段");
  return value;
}

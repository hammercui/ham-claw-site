import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { assertValidPublicRelease } from "./release-contract.mjs";

const current = JSON.parse(await readFile(new URL("../src/data/release.json", import.meta.url), "utf8"));
const available = {
  schemaVersion: 1,
  status: "available",
  platform: "windows-x86_64",
  version: "1.2.3",
  publishedAt: "2026-08-05T01:02:03Z",
  bytes: 23_000_000,
  downloadUrl: "https://github.com/example/ham-claw-site/releases/download/v1.2.3/OpenClawConsole.exe",
  sha256: "a".repeat(64),
  notes: "稳定性改进"
};

test("current public release data satisfies the fail-closed contract", () => {
  assert.equal(assertValidPublicRelease(current), current);
});

test("a complete immutable GitHub release is accepted", () => {
  assert.equal(assertValidPublicRelease(available), available);
});

test("preparing state cannot carry a fake download", () => {
  assert.throws(() => assertValidPublicRelease({ ...current, downloadUrl: available.downloadUrl }), /未声明字段/);
});

test("mutable latest URL and renamed executable are rejected", () => {
  assert.throws(
    () => assertValidPublicRelease({ ...available, downloadUrl: "https://github.com/example/ham-claw-site/releases/latest/download/OpenClawConsole-v1.2.3.exe" }),
    /不可变 Tag/
  );
});

test("prerelease versions are rejected because the current client comparator is not prerelease-safe", () => {
  assert.throws(() => assertValidPublicRelease({ ...available, version: "1.2.3-preview.1" }), /稳定 SemVer/);
});

test("secret-shaped public fields are rejected", () => {
  assert.throws(() => assertValidPublicRelease({ ...available, apiKey: "canary" }), /不允许出现在公开发布数据/);
});

test("oversized and malformed artifacts are rejected", () => {
  assert.throws(() => assertValidPublicRelease({ ...available, bytes: 300 * 1024 * 1024 }), /bytes/);
  assert.throws(() => assertValidPublicRelease({ ...available, sha256: "ABC" }), /sha256/);
});

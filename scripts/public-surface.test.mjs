import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";

const root = path.resolve(import.meta.dirname, "..");
const tracked = execFileSync("git", ["ls-files", "-z"], {
  cwd: root,
  encoding: "utf8",
}).split("\0").filter(Boolean);

const forbiddenPaths = [
  /^(?:AGENTS\.md|docs\/|design\/)/i,
  /^(?:release-input|release-output|private-backups)\//i,
  /\.(?:pfx|p12|pem|key|bundle|minisig|exe|msi|dmg|pkg)$/i,
];

const forbiddenText = [
  new RegExp(["BEGIN", "PRIVATE", "KEY"].join("[ -]+"), "i"),
  new RegExp(["ghp", "[A-Za-z0-9]{30,}"].join("_")),
  new RegExp(["github", "pat", "[A-Za-z0-9_]{20,}"].join("_")),
  new RegExp(["sk", "[A-Za-z0-9_-]{20,}"].join("-")),
  new RegExp(["AKIA", "[A-Z0-9]{16}"].join("")),
  new RegExp(["[A-Z]", ":\\\\", "Users\\\\"].join(""), "i"),
  new RegExp(["[A-Z]", ":\\\\", "moneyProject\\\\"].join(""), "i"),
  new RegExp(["atechoi", "site"].join("\\."), "i"),
  new RegExp(["ham", "claw", "git"].join("[-\\.]"), "i"),
  new RegExp(["source", "commit"].join(""), "i"),
  new RegExp(["内部", "决策"].join("")),
  new RegExp(["实施", "计划"].join("")),
  new RegExp(["当前", "状态"].join("")),
  new RegExp(["AI", "协作"].join("\\s*"), "i"),
];

test("tracked files stay inside the public repository boundary", async () => {
  const badPaths = tracked.filter((file) => forbiddenPaths.some((rule) => rule.test(file)));
  assert.deepEqual(badPaths, [], `forbidden tracked files:\n${badPaths.join("\n")}`);

  const findings = [];
  for (const file of tracked) {
    const bytes = await readFile(path.join(root, file));
    if (bytes.includes(0)) continue;
    const content = bytes.toString("utf8");
    for (const rule of forbiddenText) {
      if (rule.test(content)) findings.push(`${file}: ${rule}`);
    }
  }
  assert.deepEqual(findings, [], `non-public text found:\n${findings.join("\n")}`);
});

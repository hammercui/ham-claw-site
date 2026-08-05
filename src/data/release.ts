import rawRelease from "./release.json";

type PreparingRelease = {
  schemaVersion: 1;
  status: "preparing";
  platform: "windows-x86_64";
  message: string;
};

type AvailableRelease = {
  schemaVersion: 1;
  status: "available";
  platform: "windows-x86_64";
  version: string;
  publishedAt: string;
  bytes: number;
  downloadUrl: string;
  sha256: string;
  notes: string;
};

type SuspendedRelease = {
  schemaVersion: 1;
  status: "suspended";
  platform: "windows-x86_64";
  message: string;
  reason: string;
};

export type PublicRelease = PreparingRelease | AvailableRelease | SuspendedRelease;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parsePublicRelease(value: unknown): PublicRelease {
  if (!isRecord(value) || value.schemaVersion !== 1 || value.platform !== "windows-x86_64") {
    throw new Error("公开发布数据的 schema 或平台不受支持");
  }

  if (value.status === "preparing" && typeof value.message === "string" && value.message.trim()) {
    return value as PreparingRelease;
  }

  if (
    value.status === "suspended" &&
    typeof value.message === "string" && value.message.trim() &&
    typeof value.reason === "string" && value.reason.trim()
  ) {
    return value as SuspendedRelease;
  }

  if (
    value.status === "available" &&
    typeof value.version === "string" &&
    typeof value.publishedAt === "string" &&
    typeof value.bytes === "number" &&
    typeof value.downloadUrl === "string" &&
    typeof value.sha256 === "string" &&
    typeof value.notes === "string"
  ) {
    return value as AvailableRelease;
  }

  throw new Error("公开发布数据不完整");
}

export const currentRelease = parsePublicRelease(rawRelease);

export function formatBytes(bytes: number): string {
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

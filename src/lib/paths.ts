const configuredBase = import.meta.env.BASE_URL.endsWith("/")
  ? import.meta.env.BASE_URL.slice(0, -1)
  : import.meta.env.BASE_URL;

export function withBase(path: string): string {
  const absolutePath = path.startsWith("/") ? path : `/${path}`;
  return configuredBase ? `${configuredBase}${absolutePath}` : absolutePath;
}

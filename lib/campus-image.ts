const ALLOWED_ORIGINS = new Set([
  "https://campus.andy-y.cn",
  "http://84.54.2.93:8620",
  "http://139.224.71.200:8620",
]);

const LEGACY_MEDIA_PATH =
  /^\/media\/[a-z]:\/AstrBot\/data\/plugin_data\/astrbot_plugin_campus_inbox\/media\/([a-f0-9]{32}\.[a-z0-9]+)$/i;

/** Resolve Campus media URLs, including paths saved before Windows basenames were fixed. */
export function campusImageUrl(source: string): string | null {
  try {
    const url = new URL(source);
    if (!ALLOWED_ORIGINS.has(url.origin) || url.username || url.password) return null;
    if (url.pathname.startsWith("/media/")) {
      const path = decodeURIComponent(url.pathname).replaceAll("\\", "/");
      const filename = LEGACY_MEDIA_PATH.exec(path)?.[1];
      if (filename) url.pathname = "/media/" + filename;
    }
    return url.toString();
  } catch {
    return null;
  }
}

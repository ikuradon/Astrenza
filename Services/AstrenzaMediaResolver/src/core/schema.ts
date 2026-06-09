export type ResolveImagePreset = "timeline" | "thumb" | "blurhash-source";

export type ResolveItem = {
  id: string;
  url: string;
  kind: "auto" | "html" | "image";
};

export type ResolveBatchRequest = {
  items: ResolveItem[];
  imagePreset?: ResolveImagePreset;
};

export type ResolvedImage = {
  url: string;
  optimizedUrl: string | null;
  mimeType: string | null;
  width: number | null;
  height: number | null;
  blurhash: string | null;
};

export type ResolveResult = {
  id: string;
  status: "resolved" | "failed";
  kind: "html" | "image" | "unknown";
  url: string;
  finalUrl: string;
  title: string | null;
  description: string | null;
  siteName: string | null;
  thumbnailStyle: "summary" | "summary_large_image" | null;
  image: ResolvedImage | null;
  cacheTtlSeconds: number;
  warnings: string[];
  error: string | null;
};

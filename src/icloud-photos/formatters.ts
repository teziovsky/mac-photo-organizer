import type { ICloudPhotoAlbum } from "@/icloud-photos/types";

export function formatAlbumMediaSummary(album: ICloudPhotoAlbum): string {
  const parts: string[] = [];
  if (album.photoCount > 0) parts.push(`${album.photoCount} ${album.photoCount === 1 ? "photo" : "photos"}`);
  if (album.videoCount > 0) parts.push(`${album.videoCount} ${album.videoCount === 1 ? "video" : "videos"}`);
  return parts.length > 0 ? parts.join(", ") : `${album.mediaCount} media`;
}

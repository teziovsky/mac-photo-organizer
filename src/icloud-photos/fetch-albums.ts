import type { ICloudPhotoAlbum } from "@/icloud-photos/types";

import { runAppleScript } from "@raycast/utils";

import { FETCH_ALBUMS_SCRIPT } from "@/icloud-photos/apple-scripts";
import { ALBUM_FIELD_DELIMITER, VIDEO_EXTENSIONS } from "@/icloud-photos/constants";
import { parseAlbumsOutput } from "@/icloud-photos/parsers";

export async function fetchICloudPhotoAlbums(): Promise<ICloudPhotoAlbum[]> {
  const result = await runAppleScript(FETCH_ALBUMS_SCRIPT, [ALBUM_FIELD_DELIMITER, VIDEO_EXTENSIONS.join(",")]);

  return parseAlbumsOutput(result);
}

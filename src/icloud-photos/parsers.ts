import { ALBUM_FIELD_DELIMITER } from "@/icloud-photos/constants";
import { ICloudPhotoAlbum } from "@/icloud-photos/types";
import { devLog } from "@/utils/dev-log";

export function parseAlbumsOutput(output: string): ICloudPhotoAlbum[] {
  const trimmed = output.trim();
  if (!trimmed) return [];

  return trimmed.split("\n").flatMap(line => {
    const fields = line.split(ALBUM_FIELD_DELIMITER);
    devLog({ fields });
    if (fields.length < 4) return [];

    const videoCount = Number(fields.at(-1));
    const photoCount = Number(fields.at(-2));
    const mediaCount = Number(fields.at(-3));
    const name = fields.slice(0, -3).join(ALBUM_FIELD_DELIMITER);

    if (!name || [mediaCount, photoCount, videoCount].some(Number.isNaN)) return [];

    return [{ name, mediaCount, photoCount, videoCount }];
  });
}

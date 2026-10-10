import { ApiError } from '../errors.ts';

export const AVATAR_MAX_BYTES = 512 * 1024;
const MIN_DIM = 64;
const MAX_DIM = 1024;

/**
 * Validates a baseline/progressive JPEG and returns a copy with every APPn segment except JFIF
 * (APP0), and every comment, removed: EXIF (GPS, device, timestamps), XMP, ICC, IPTC.
 * The app resizes and re-renders before upload, so orientation is already baked into the pixels.
 */
export const sanitizeJpeg = (buf: Buffer): { data: Buffer; width: number; height: number } => {
  const bad = (m: string) => new ApiError(400, 'invalid_image', m);
  if (buf.length > AVATAR_MAX_BYTES) throw new ApiError(413, 'image_too_large', 'Image must be at most 512 KB.');
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) throw bad('Image must be a JPEG.');
  const out: Buffer[] = [buf.subarray(0, 2)];
  let i = 2;
  let width = 0;
  let height = 0;
  while (i < buf.length) {
    if (buf[i] !== 0xff) throw bad('Corrupt JPEG.');
    const marker = buf[i + 1]!;
    if (marker === 0xff) {
      i++; // fill byte
      continue;
    }
    if (marker === 0xd9) break; // EOI before SOS
    if (marker >= 0xd0 && marker <= 0xd7) throw bad('Corrupt JPEG.');
    if (i + 4 > buf.length) throw bad('Corrupt JPEG.');
    const len = buf.readUInt16BE(i + 2);
    const end = i + 2 + len;
    if (len < 2 || end > buf.length) throw bad('Corrupt JPEG.');
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      if (len < 7) throw bad('Corrupt JPEG.');
      height = buf.readUInt16BE(i + 5);
      width = buf.readUInt16BE(i + 7);
    }
    const strip = (marker >= 0xe1 && marker <= 0xef) || marker === 0xfe;
    if (!strip) out.push(buf.subarray(i, end));
    if (marker === 0xda) {
      // Start of scan: entropy-coded data + remaining markers to EOI are image data; keep as is.
      out.push(buf.subarray(end));
      if (!width || !height) throw bad('Corrupt JPEG.');
      if (width < MIN_DIM || height < MIN_DIM || width > MAX_DIM || height > MAX_DIM)
        throw bad(`Image must be between ${MIN_DIM} and ${MAX_DIM} px per side.`);
      return { data: Buffer.concat(out), width, height };
    }
    i = end;
  }
  throw bad('Corrupt JPEG.');
};

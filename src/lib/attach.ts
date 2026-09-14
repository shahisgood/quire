import { uid } from './db';
import type { Attachment } from './types';

const MAX_EDGE = 1600;
const MAX_FILE = 8 * 1024 * 1024;

function readAsDataUrl(file: Blob): Promise<string> {
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(new Error('Could not read file')); r.readAsDataURL(file); });
}

async function downscale(file: File): Promise<{ dataUrl: string; size: number; mime: string }> {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('Not an image')); i.src = url; });
    const scale = Math.min(1, MAX_EDGE / Math.max(img.naturalWidth, img.naturalHeight));
    if (scale === 1 && file.size < 1.5 * 1024 * 1024 && (file.type === 'image/jpeg' || file.type === 'image/png' || file.type === 'image/webp')) {
      return { dataUrl: await readAsDataUrl(file), size: file.size, mime: file.type };
    }
    const c = document.createElement('canvas');
    c.width = Math.round(img.naturalWidth * scale);
    c.height = Math.round(img.naturalHeight * scale);
    const ctx = c.getContext('2d');
    if (!ctx) throw new Error('Canvas unavailable');
    ctx.drawImage(img, 0, 0, c.width, c.height);
    const mime = file.type === 'image/png' && scale === 1 ? 'image/png' : 'image/jpeg';
    const dataUrl = c.toDataURL(mime, 0.86);
    return { dataUrl, size: Math.round((dataUrl.length - dataUrl.indexOf(',') - 1) * 0.75), mime };
  } finally { URL.revokeObjectURL(url); }
}

export async function toAttachment(file: File): Promise<Attachment> {
  if (file.type.startsWith('image/')) {
    const { dataUrl, size, mime } = await downscale(file);
    return { id: uid(), kind: 'image', mime, name: file.name || 'image', size, dataUrl };
  }
  if (file.size > MAX_FILE) throw new Error(`${file.name} is larger than 8 MB`);
  return { id: uid(), kind: 'file', mime: file.type || 'application/octet-stream', name: file.name || 'file', size: file.size, dataUrl: await readAsDataUrl(file) };
}

export const prerender = false;

import type { APIRoute } from "astro";
import { createReadStream, existsSync, statSync } from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";

export const GET: APIRoute = async () => {
  const filePath = resolveDmg();
  if (!filePath) {
    return new Response("The download is not available yet.", { status: 404 });
  }

  const { size } = statSync(filePath);
  return new Response(Readable.toWeb(createReadStream(filePath)) as ReadableStream, {
    headers: {
      "Content-Type": "application/x-apple-diskimage",
      "Content-Disposition": 'attachment; filename="CharmDrop.dmg"',
      "Content-Length": String(size),
    },
  });
};

function resolveDmg(): string | null {
  const candidates = [
    process.env.CHARMDROP_DMG_PATH,
    path.resolve(process.cwd(), "private/downloads/CharmDrop.dmg"),
    path.resolve(process.cwd(), "public/downloads/CharmDrop.dmg"),
    path.resolve(process.cwd(), "../build/CharmDrop-0.1.0.dmg"),
  ].filter((value): value is string => Boolean(value));

  return candidates.find((candidate) => existsSync(candidate)) ?? null;
}

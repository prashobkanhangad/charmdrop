export const prerender = false;

import type { APIRoute } from "astro";

export const GET: APIRoute = ({ redirect }) => {
  return redirect("/downloads/CharmDrop.dmg");
};

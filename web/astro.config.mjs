// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import vercel from "@astrojs/vercel";

export default defineConfig({
  site: "https://charmdrop.app",
  trailingSlash: "never",
  output: "static",

  i18n: {
    defaultLocale: "en",
    locales: ["en", "hi", "es"],
    routing: {
      prefixDefaultLocale: false,
    },
  },

  vite: {
    plugins: [tailwindcss()],
  },

  adapter: vercel(),
});

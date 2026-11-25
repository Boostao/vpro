import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type PluginOption, type UserConfig } from "vite";
import desktopConfig from "./vite.config";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRuntimePath = path.resolve(__dirname, "src/web/wailsWebRuntime.ts");

function isWailsTypedEventsPlugin(plugin: PluginOption): boolean {
  if (
    !plugin ||
    typeof plugin !== "object" ||
    Array.isArray(plugin) ||
    "then" in plugin
  ) {
    return false;
  }
  return plugin.name === "wails-typed-events";
}

const baseConfig = desktopConfig as UserConfig;
const desktopPlugins = Array.isArray(baseConfig.plugins)
  ? baseConfig.plugins
  : [];
const webPlugins = desktopPlugins.filter(
  (plugin) => !isWailsTypedEventsPlugin(plugin),
);

const existingAliases = baseConfig.resolve?.alias;
const normalizedAliases = Array.isArray(existingAliases)
  ? existingAliases
  : existingAliases
    ? Object.entries(existingAliases).map(([find, replacement]) => ({
        find,
        replacement,
      }))
    : [];

export default defineConfig({
  ...baseConfig,
  define: {
    ...(baseConfig.define ?? {}),
    __VPRO_WEB_READONLY__: true,
  },
  resolve: {
    ...baseConfig.resolve,
    alias: [
      ...normalizedAliases,
      { find: /^@wailsio\/runtime$/, replacement: webRuntimePath },
    ],
  },
  plugins: webPlugins,
  build: {
    ...baseConfig.build,
    outDir: "dist-web",
  },
});

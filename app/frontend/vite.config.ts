import { readFileSync } from "node:fs";
import path from "node:path";
import { defineConfig, type Plugin } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "@tailwindcss/vite";
import wails from "@wailsio/runtime/plugins/vite";

const explicitPort = process.env.WAILS_VITE_PORT?.trim();

const USED_CONTROL_PROPS = new Set([
  "Left",
  "Top",
  "Width",
  "Height",
  "LayoutCachedWidth",
  "LayoutCachedHeight",
  "FontSize",
  "FontName",
  "TextAlign",
  "FontBold",
  "FontWeight",
  "FontItalic",
  "Locked",
  "Enabled",
  "Visible",
  "TabIndex",
  "Caption",
  "ControlTipText",
  "ControlSource",
  "OptionValue",
  "SourceObject",
  "LimitToList",
]);

const USED_FIELD_PROPS = new Set(["OptionValue", "LimitToList"]);

interface LayoutCompactRule {
  readonly rootOnly: boolean;
  readonly keepControls: boolean;
  readonly keepButtonEvents: boolean;
}

const COMPACT_LAYOUT_RULES: Readonly<Record<string, LayoutCompactRule>> = {
  "fs882-xl-layout.json": {
    rootOnly: false,
    keepControls: true,
    keepButtonEvents: false,
  },
  "fs882-two-page-layout.json": {
    rootOnly: true,
    keepControls: true,
    keepButtonEvents: true,
  },
  "fs882-two-page-chars-layout.json": {
    rootOnly: true,
    keepControls: true,
    keepButtonEvents: true,
  },
  "fs1333-sivi-layout.json": {
    rootOnly: true,
    keepControls: false,
    keepButtonEvents: false,
  },
  "project-metadata-layout.json": {
    rootOnly: true,
    keepControls: false,
    keepButtonEvents: false,
  },
};

interface RawSourceValue {
  value?: string;
  line: number;
}

function compactProperties(
  props: Record<string, RawSourceValue | undefined> | undefined,
  allowSet: ReadonlySet<string>,
): Record<string, RawSourceValue> {
  const out: Record<string, RawSourceValue> = {};
  if (!props) return out;
  for (const [key, item] of Object.entries(props)) {
    if (allowSet.has(key) && item !== undefined) {
      out[key] =
        item.value !== undefined
          ? { value: item.value, line: item.line }
          : { line: item.line };
    }
  }
  return out;
}

export function compactAccessLayoutJson(
  fileName: string,
  rawJson: string,
): string {
  const rule = COMPACT_LAYOUT_RULES[fileName];
  if (!rule) return rawJson;
  const raw = JSON.parse(rawJson) as {
    root: string;
    geometryUnit: string;
    forms: Array<Record<string, any>>;
  };
  const selectedForms = rule.rootOnly ? raw.forms.slice(0, 1) : raw.forms;
  const compacted = {
    root: raw.root,
    geometryUnit: raw.geometryUnit,
    forms: selectedForms.map((form) => {
      const nextForm: Record<string, unknown> = {
        name: form.name,
        source: form.source,
        sha256: form.sha256,
        pages: Array.isArray(form.pages)
          ? form.pages.map((page: Record<string, any>) => ({
              controlId: page.controlId,
              ...(page.name !== undefined ? { name: page.name } : {}),
              ...(page.caption !== undefined ? { caption: page.caption } : {}),
              properties: compactProperties(page.properties, USED_CONTROL_PROPS),
            }))
          : [],
        embedded: Array.isArray(form.embedded) ? form.embedded : [],
        controls:
          rule.keepControls && Array.isArray(form.controls)
            ? form.controls.map((control: Record<string, any>) => {
                const nextControl: Record<string, unknown> = {
                  controlId: control.controlId,
                  type: control.type,
                  line: control.line,
                  properties: compactProperties(
                    control.properties,
                    USED_CONTROL_PROPS,
                  ),
                };
                if (control.parentId !== undefined)
                  nextControl.parentId = control.parentId;
                if (control.controlName !== undefined)
                  nextControl.controlName = control.controlName;
                if (control.pageId !== undefined)
                  nextControl.pageId = control.pageId;
                if (
                  rule.keepButtonEvents &&
                  control.type === "CommandButton" &&
                  Array.isArray(control.events)
                ) {
                  nextControl.events = control.events;
                }
                return nextControl;
              })
            : [],
        fields: Array.isArray(form.fields)
          ? form.fields.map((field: Record<string, any>) => {
              const nextField: Record<string, unknown> = {
                controlId: field.controlId,
                type: field.type,
                properties: compactProperties(
                  field.properties,
                  USED_FIELD_PROPS,
                ),
              };
              if (field.parentId !== undefined)
                nextField.parentId = field.parentId;
              if (field.controlName !== undefined)
                nextField.controlName = field.controlName;
              if (field.column !== undefined) nextField.column = field.column;
              if (field.binding !== undefined)
                nextField.binding = field.binding;
              if (field.caption !== undefined)
                nextField.caption = field.caption;
              if (field.pageId !== undefined) nextField.pageId = field.pageId;
              if (field.readOnly !== undefined)
                nextField.readOnly = field.readOnly;
              if (field.implementation !== undefined)
                nextField.implementation = field.implementation;
              return nextField;
            })
          : [],
      };
      if (form.recordSource !== undefined)
        nextForm.recordSource = form.recordSource;
      return nextForm;
    }),
  };
  return JSON.stringify(compacted);
}

function compactAccessLayoutJsonPlugin(): Plugin {
  return {
    name: "vpro-compact-access-layout-json",
    enforce: "pre",
    load(id) {
      const cleanId = id.split("?", 1)[0].replaceAll("\\", "/");
      if (!cleanId.includes("/resources/") || !cleanId.endsWith("-layout.json"))
        return null;
      const fileName = path.posix.basename(cleanId);
      if (!Object.hasOwn(COMPACT_LAYOUT_RULES, fileName)) return null;
      const rawJson = readFileSync(id.split("?", 1)[0], "utf8");
      return compactAccessLayoutJson(fileName, rawJson);
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: Number(explicitPort) || 9245,
    strictPort: Boolean(explicitPort),
  },
  plugins: [
    compactAccessLayoutJsonPlugin(),
    tailwindcss(),
    svelte(),
    wails("./bindings"),
  ],
  build: {
    chunkSizeWarningLimit: 1120,
    rollupOptions: {
      output: {
        manualChunks(id) {
          const normalized = id.replaceAll("\\", "/");
          if (
            id.includes("vite/preload-helper") ||
            id.includes("commonjsHelpers") ||
            normalized.includes("/node_modules/tslib/")
          ) {
            return "preload-helper";
          }
          if (
            normalized.includes("/node_modules/maplibre-gl/") ||
            normalized.includes("/node_modules/pmtiles/") ||
            normalized.includes("/node_modules/fflate/")
          ) {
            return "vendor-maplibre";
          }
          if (
            normalized.includes("/node_modules/@deck.gl/") ||
            normalized.includes("/node_modules/@luma.gl/") ||
            normalized.includes("/node_modules/@math.gl/") ||
            normalized.includes("/node_modules/@loaders.gl/") ||
            normalized.includes("/node_modules/@probe.gl/") ||
            normalized.includes("/node_modules/mjolnir.js/")
          ) {
            return "vendor-deckgl";
          }
          if (normalized.endsWith("/resources/fs882-xl-layout.json")) {
            return "layout-fs882-xl";
          }
          if (normalized.endsWith("/resources/fs882-two-page-layout.json")) {
            return "layout-fs882-two-page";
          }
          if (
            normalized.endsWith("/resources/fs882-two-page-chars-layout.json")
          ) {
            return "layout-fs882-two-page-chars";
          }
          if (normalized.endsWith("/resources/fs1333-sivi-layout.json")) {
            return "layout-fs1333-sivi";
          }
          if (normalized.endsWith("/resources/project-metadata-layout.json")) {
            return "layout-project-metadata";
          }
          return undefined;
        },
      },
    },
  },
});

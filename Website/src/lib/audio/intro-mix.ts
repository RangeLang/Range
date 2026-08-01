export type IntroMixChannel =
  | "identity"
  | "forms"
  | "enums"
  | "properties"
  | "keyboard";

export type IntroMixSettings = {
  master: number;
  identity: number;
  forms: number;
  enums: number;
  properties: number;
  keyboard: number;
  transpose: number;
};

export type IntroMixPresetStore = {
  version: 1;
  selected: string | undefined;
  presets: Record<string, IntroMixSettings>;
};

export const INTRO_MIX_STORAGE_KEY = "range:intro-score:v1";

export const DEFAULT_INTRO_MIX: Readonly<IntroMixSettings> = Object.freeze({
  master: 0.92,
  identity: 1,
  forms: 1,
  enums: 1,
  properties: 1,
  keyboard: 0.82,
  transpose: 0,
});

const clamp = (value: number, minimum: number, maximum: number) =>
  Math.min(maximum, Math.max(minimum, value));

function level(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? clamp(value, 0, 1.25)
    : fallback;
}

function transpose(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.round(clamp(value, -12, 12))
    : fallback;
}

export function normalizeIntroMix(
  value: Partial<IntroMixSettings> | null | undefined,
): IntroMixSettings {
  return {
    master: level(value?.master, DEFAULT_INTRO_MIX.master),
    identity: level(value?.identity, DEFAULT_INTRO_MIX.identity),
    forms: level(value?.forms, DEFAULT_INTRO_MIX.forms),
    enums: level(value?.enums, DEFAULT_INTRO_MIX.enums),
    properties: level(value?.properties, DEFAULT_INTRO_MIX.properties),
    keyboard: level(value?.keyboard, DEFAULT_INTRO_MIX.keyboard),
    transpose: transpose(value?.transpose, DEFAULT_INTRO_MIX.transpose),
  };
}

export function cloneIntroMix(
  mix?: Readonly<IntroMixSettings>,
): IntroMixSettings {
  return { ...(mix ?? DEFAULT_INTRO_MIX) };
}

export function readIntroMixPresets(): IntroMixPresetStore {
  if (typeof localStorage === "undefined") {
    return { version: 1, selected: undefined, presets: {} };
  }

  try {
    const value = JSON.parse(localStorage.getItem(INTRO_MIX_STORAGE_KEY) ?? "null") as {
      selected?: unknown;
      presets?: unknown;
    } | null;
    if (!value || typeof value.presets !== "object" || value.presets === null) {
      return { version: 1, selected: undefined, presets: {} };
    }

    const presets: Record<string, IntroMixSettings> = {};
    for (const [name, mix] of Object.entries(value.presets)) {
      if (!name.trim() || typeof mix !== "object" || mix === null) continue;
      presets[name] = normalizeIntroMix(mix as Partial<IntroMixSettings>);
    }
    const selected = typeof value.selected === "string" && presets[value.selected]
      ? value.selected
      : undefined;
    return { version: 1, selected, presets };
  } catch {
    return { version: 1, selected: undefined, presets: {} };
  }
}

export function writeIntroMixPresets(store: IntroMixPresetStore) {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(INTRO_MIX_STORAGE_KEY, JSON.stringify(store));
  } catch {
    // Presets are an optional local convenience; unavailable storage is fine.
  }
}

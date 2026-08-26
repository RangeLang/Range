import type { Action } from "svelte/action";
import {
  createDesignKnotVoices,
  KNOT_BEAT_SECONDS,
  type DesignKnotVoices,
} from "$lib/audio/design-knot-voices";

export type MusicVoice = keyof DesignKnotVoices;

/** One stroke in a bar: which voice, where, how hard, and in which form. */
export type MusicHit = {
  beat: number;
  voice: MusicVoice;
  level: number;
  /** The lighter form: half a chaka or tsam, a light dam. */
  light?: boolean;
};

export type SoundProfile = {
  /** Also the layer name published on the presence bus. */
  name: string;
  /** Beats in one bar; the bar repeats for as long as the element is present. */
  bar: number;
  hits: MusicHit[];
};

export type MusicOptions = {
  profile: SoundProfile;
  /**
   * The level the layer settles to once it has stated itself, 0..1. A profile
   * arrives at full weight and recedes to this over a few bars.
   */
  background?: number;
};

/*
 * One conductor for the whole document. Components do not own observers or
 * schedulers; they tag themselves with `use:music` and the conductor reads
 * their scroll position off the shared layout tracker, turns it into a
 * presence, publishes that on the sound manager's layer bus, and plays every
 * registered profile against a single grid. Adding a second scored element
 * anywhere costs one attribute, not another timer.
 */
type Registration = {
  profile: SoundProfile;
  background: number;
  presence: number;
  nextBar: number;
  barIndex: number;
  stop?: () => void;
};

const registry = new Map<HTMLElement, Registration>();
let voices: DesignKnotVoices | undefined;
let route: ReturnType<NonNullable<Window["__rangeSoundManager"]>["register"]>;
let timer: ReturnType<typeof setInterval> | undefined;

/** Full at the viewport's centre line, gone by six tenths of a screen away. */
function presenceFromViewport(normalizedY: number, visible: boolean) {
  if (!visible) return 0;
  return Math.max(0, Math.min(1, 1 - Math.abs(normalizedY - 0.5) / 0.6));
}

function ensureConductor() {
  const manager = window.__rangeSoundManager;
  if (!manager || timer !== undefined) return;
  route ??= manager.register("range-music", 0.7);
  if (!route) return;
  voices ??= createDesignKnotVoices(route);

  timer = setInterval(() => {
    const current = route;
    if (!current || !voices || !manager.isEnabled()) return;
    const now = current.audioContext.currentTime;
    for (const registration of registry.values()) {
      const { profile, presence } = registration;
      const bar = profile.bar * KNOT_BEAT_SECONDS;
      if (presence <= 0.02) {
        // Silent layers restate themselves next time they come back.
        registration.barIndex = 0;
        registration.nextBar = 0;
        continue;
      }
      // Land on the shared grid rather than wherever the scroll stopped.
      if (registration.nextBar === 0) {
        registration.nextBar = Math.ceil(now / bar) * bar;
      }
      const floor = registration.background;
      while (registration.nextBar < now + 0.4) {
        const settle = floor + (1 - floor) * 0.45 ** registration.barIndex;
        for (const hit of profile.hits) {
          voices[hit.voice](
            registration.nextBar + hit.beat * KNOT_BEAT_SECONDS,
            hit.level * presence * settle,
            hit.light ?? false,
          );
        }
        registration.nextBar += bar;
        registration.barIndex += 1;
      }
    }
  }, 150);
}

function releaseConductor() {
  if (registry.size > 0 || timer === undefined) return;
  clearInterval(timer);
  timer = undefined;
  route?.dispose();
  route = undefined;
  voices = undefined;
}

/**
 * Tag an element with a sound profile:
 *
 *   <li use:music={{ profile: knotPulse, background: 0.5 }}>
 *
 * Presence follows the element up the page, so the layer is loudest when the
 * element is what you are looking at and fades out as it leaves.
 */
export const music: Action<HTMLElement, MusicOptions> = (node, options) => {
  const tracker = window.__rangeLayoutTracker;
  const manager = window.__rangeSoundManager;

  const registration: Registration = {
    profile: options.profile,
    background: options.background ?? 0.5,
    presence: 0,
    nextBar: 0,
    barIndex: 0,
  };
  registry.set(node, registration);
  ensureConductor();

  registration.stop = tracker?.observe(node, (snapshot) => {
    const presence = presenceFromViewport(
      snapshot.normalizedViewportY,
      snapshot.visible,
    );
    if (presence === registration.presence) return;
    registration.presence = presence;
    manager?.setLayerPresence(registration.profile.name, presence);
  });

  return {
    update(next: MusicOptions) {
      registration.profile = next.profile;
      registration.background = next.background ?? 0.5;
    },
    destroy() {
      registration.stop?.();
      manager?.setLayerPresence(registration.profile.name, 0);
      registry.delete(node);
      releaseConductor();
    },
  };
};

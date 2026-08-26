export const RANGE_ONBOARDING_MACHINE_CONTEXT = Symbol(
  "range-onboarding-machine",
);

export type OnboardingPhase =
  | "booting"
  | "prompting"
  | "entering"
  | "exploring"
  | "dragging"
  | "leaving"
  | "complete";

export type OnboardingInput = "mouse" | "touch" | "keyboard";

export type OnboardingStage = "small" | "medium" | "fullscreen";

export type OnboardingSnapshot = {
  readonly phase: OnboardingPhase;
  readonly stage: OnboardingStage;
  readonly input: OnboardingInput | undefined;
  readonly reveal: number;
  readonly startedAt: number;
};

export type OnboardingEvent =
  | { type: "RESTORE"; completed: boolean; force?: boolean }
  | { type: "ACTIVATE"; input: OnboardingInput; now: number }
  | { type: "ENTRY_FINISHED" }
  | { type: "START_DRAG" }
  | { type: "END_DRAG" }
  | { type: "REVEAL"; amount: number; now: number }
  | { type: "BEGIN_LEAVE" }
  | { type: "REACH_FULLSCREEN"; remaining: number }
  | { type: "LEAVE_FINISHED" }
  | { type: "RESET" };

export type OnboardingEffect =
  | { type: "PLAY_ACTIVATION_TONE"; input: OnboardingInput }
  | { type: "SCHEDULE_ENTRY_FINISH"; delay: number }
  | { type: "SCHEDULE_COMPLETION"; delay: number }
  | { type: "SCHEDULE_LEAVE_FINISH"; delay: number }
  | { type: "PERSIST_COMPLETION" };

export type OnboardingTransition = {
  readonly snapshot: OnboardingSnapshot;
  readonly effects: readonly OnboardingEffect[];
};

export type RangeOnboardingMachine = {
  getSnapshot: () => OnboardingSnapshot;
  send: (event: OnboardingEvent) => OnboardingTransition;
  subscribe: (
    listener: (snapshot: OnboardingSnapshot) => void,
  ) => () => void;
};

const entryDuration = 4_200;
// Exit is one composited handoff: the sky sphere and its centered inner
// website cutout grow together while the page resolves underneath them.
const exitDuration = 600;
const fullscreenHoldDuration = 80;

const initialSnapshot: OnboardingSnapshot = {
  phase: "booting",
  stage: "small",
  input: undefined,
  reveal: 0,
  startedAt: 0,
};

export function createRangeOnboardingMachine(): RangeOnboardingMachine {
  let snapshot = initialSnapshot;
  const listeners = new Set<(snapshot: OnboardingSnapshot) => void>();
  let completionScheduled = false;

  function publish(next: OnboardingSnapshot) {
    if (next === snapshot) return;
    snapshot = next;
    for (const listener of listeners) listener(snapshot);
  }

  function send(event: OnboardingEvent): OnboardingTransition {
    const effects: OnboardingEffect[] = [];
    let next = snapshot;

    switch (event.type) {
      case "RESTORE":
        if (snapshot.phase !== "booting") break;
        next = {
          ...initialSnapshot,
          phase: event.completed && !event.force ? "complete" : "prompting",
          stage: event.completed && !event.force ? "fullscreen" : "small",
        };
        break;
      case "ACTIVATE":
        if (snapshot.phase !== "prompting") break;
        completionScheduled = false;
        next = {
          phase: "entering",
          input: event.input,
          reveal: 0,
          startedAt: event.now,
        };
        effects.push({ type: "PLAY_ACTIVATION_TONE", input: event.input });
        effects.push({ type: "SCHEDULE_ENTRY_FINISH", delay: entryDuration });
        break;
      case "ENTRY_FINISHED":
        if (snapshot.phase !== "entering") break;
        next = { ...snapshot, phase: "exploring", stage: "medium" };
        break;
      case "START_DRAG":
        if (snapshot.phase !== "exploring") break;
        next = { ...snapshot, phase: "dragging" };
        break;
      case "END_DRAG":
        if (snapshot.phase !== "dragging") break;
        next = { ...snapshot, phase: "exploring" };
        break;
      case "REVEAL": {
        if (snapshot.phase !== "exploring" && snapshot.phase !== "dragging") {
          break;
        }
        const reveal = Math.min(1, snapshot.reveal + Math.max(0, event.amount));
        if (reveal !== snapshot.reveal) next = { ...snapshot, reveal };
        if (reveal >= 1 && !completionScheduled) {
          completionScheduled = true;
          effects.push({
            type: "SCHEDULE_COMPLETION",
            delay: Math.max(
              0,
              exitDuration - (event.now - snapshot.startedAt),
            ),
          });
        }
        break;
      }
      case "BEGIN_LEAVE":
        if (snapshot.phase !== "exploring" && snapshot.phase !== "dragging") {
          break;
        }
        effects.push({ type: "PERSIST_COMPLETION" });
        effects.push({ type: "SCHEDULE_LEAVE_FINISH", delay: exitDuration });
        next = { ...snapshot, phase: "leaving", stage: "medium" };
        break;
      case "REACH_FULLSCREEN":
        if (snapshot.phase !== "leaving" || snapshot.stage === "fullscreen") {
          break;
        }
        effects.push({
          type: "SCHEDULE_LEAVE_FINISH",
          delay: Math.max(0, event.remaining) + fullscreenHoldDuration,
        });
        next = { ...snapshot, stage: "fullscreen" };
        break;
      case "LEAVE_FINISHED":
        if (snapshot.phase !== "leaving" || snapshot.stage !== "fullscreen") break;
        next = { ...snapshot, phase: "complete", stage: "fullscreen" };
        break;
      case "RESET":
        completionScheduled = false;
        next = { ...initialSnapshot, phase: "prompting" };
        break;
    }

    publish(next);
    return { snapshot, effects };
  }

  function subscribe(listener: (snapshot: OnboardingSnapshot) => void) {
    listeners.add(listener);
    listener(snapshot);
    return () => listeners.delete(listener);
  }

  return {
    getSnapshot: () => snapshot,
    send,
    subscribe,
  };
}

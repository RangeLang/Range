# Concurrency Checklist

Use this checklist to evaluate what Neat's concurrency model must support, from low-level runtime/system coordination to reactive/UI-facing async state.

## Systems Level

- [ ] Worker pool
  Many workers consume jobs from a queue.

- [ ] Fan-out
  One producer distributes work to many concurrent workers.

- [ ] Fan-in
  Many workers send results back to one collector.

- [ ] Pipeline
  Stage A produces, Stage B transforms, Stage C writes.

- [ ] Multiplexing
  Many inputs merged into one stream or one dispatcher.

- [ ] Demultiplexing
  One input split by message type, destination, or shard.

- [ ] Load balancing
  Requests distributed across workers or peers.

- [ ] Backpressure
  Slow consumers force producers to wait, buffer, or drop.

- [ ] Request/response over peers
  Send request, await reply, handle timeout or failure.

- [ ] Long-lived connection handling
  Socket, session, or task per client or per peer.

- [ ] Event loop integration
  React to IO readiness, timers, or signals.

- [ ] Cancellation and shutdown
  Stop workers, drain queues, close resources cleanly.

## Service / Backend Level

- [ ] Background job processing
  Email sending, image processing, indexing.

- [ ] Scheduled jobs
  Cron-like or delayed tasks.

- [ ] Retry with failure policy
  Retry network or queue work with limits or backoff.

- [ ] Aggregation
  Query several services concurrently, merge best, first, or all results.

- [ ] Cache refresh
  Refresh stale state without blocking callers.

- [ ] Pub/sub
  Many listeners observe one changing source.

- [ ] Streaming responses
  Server emits chunks or events over time.

## App / Reactive Level

- [ ] One-shot async load
  Fetch user, profile, settings.

- [ ] Derived async state
  One state change triggers async recomputation elsewhere.

- [ ] Stale-while-revalidate
  Show cached value while background refresh runs.

- [ ] Search-as-you-type
  New query cancels or supersedes prior request.

- [ ] Debounced background work
  Wait briefly before firing async task.

- [ ] Latest-wins
  Ignore older in-flight results when newer request exists.

- [ ] Optimistic update
  Update UI first, reconcile or fail later.

- [ ] Incremental loading
  Pagination, infinite scroll, prefetching.

- [ ] Observation streams
  Live feed, notifications, chat messages.

- [ ] Resource binding to view lifetime
  Start on mount or appear, cancel on disappear.

## UI Level

- [ ] Loading state
  Idle, loading, success, failure.

- [ ] Transition state
  Disabled button while work is in flight.

- [ ] Progressive rendering
  Render partial sections as data arrives.

- [ ] Multi-source screen
  Several independent async regions on one screen.

- [ ] Form submission
  Submit once, prevent duplicate concurrent submissions.

- [ ] Pull-to-refresh
  Preserve displayed value while refresh runs.

- [ ] Background sync
  UI remains interactive while data updates behind the scenes.

## Design Pass

- [ ] Identify which cases are best modeled by `Promise`.
- [ ] Identify which cases are best modeled by `Channel`.
- [ ] Identify which cases are best modeled by `Stream`.
- [ ] Identify which cases should be graph policies rather than explicit primitives.
- [ ] Decide which cases must be first-class in the language versus library-level helpers.

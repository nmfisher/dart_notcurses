#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#ifndef _WIN32
// The real input pump is POSIX (pthreads + poll + pipe). Native Windows/ConPTY
// input is a follow-up (see the TODO in the #else branch below); until then
// this TU compiles a no-op stub on Windows so that notcurses_merged.dll links
// and the @Native cocoon_input_pump_* externs resolve. The Dart side falls back
// to AnsiInputBackend on Windows in the meantime.
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#endif // !_WIN32

#include <notcurses/notcurses.h>

// NOTCURSES_FFI deliberately rewrites `static` while emitting notcurses'
// inline symbols from ffi.c. Restore the C keyword for this independent TU.
#ifdef static
#undef static
#endif

// Phase 6: batched native burst input.
//
// Previously the pump thread invoked a Dart NativeCallable.listener once per
// dequeued notcurses event — N native→Dart transitions for an N-event paste or
// mouse burst. This file now queues events in a fixed-capacity ring buffer and
// notifies Dart exactly once on the empty→non-empty transition. Dart then calls
// the synchronous cocoon_input_pump_drain to copy a batch of records into
// Dart-owned memory in one transition, looping until the queue is empty.
//
// Concurrency contract:
//  - Producer (pump thread) pushes under mtx. On the 0→1 transition it sets
//    notify_armed and invokes the zero-arg listener ("queue is non-empty").
//    If the queue is full it blocks on not_full (no event is dropped).
//  - Consumer (Dart isolate, via pump_drain) takes mtx, copies min(count,max)
//    records out FIFO, clears notify_armed iff the queue drained to empty,
//    signals not_full for any blocked producer, returns the copied count.
//  - Lost-wakeup-free: an event arriving after drain returns 0 but before the
//    listener returns hits the 0→1 transition again (notify_armed was cleared
//    by the drain that emptied the queue), so the listener fires once more.
//  - Stop: write the cancel pipe, pthread_join the thread, then destroy the
//    mutex/condvar and free the queue. No listener fires after stop returns
//    because the thread is joined before the NativeCallable is closed (Dart).

/// One queued input event. Mirrors the Dart PumpedInput record shape.
typedef struct {
  uint32_t id;
  uint32_t modifiers;
  int64_t monotonic_ns;
} cocoon_input_record;

/// Zero-arg "queue is non-empty" notification invoked on the empty→non-empty
/// transition. The Dart side responds by calling cocoon_input_pump_drain.
typedef void (*cocoon_input_notify)(void);

#ifndef _WIN32
#define COCOON_INPUT_QUEUE_CAP 256

typedef struct cocoon_input_pump {
  struct notcurses* nc;
  cocoon_input_notify notify;
  pthread_t thread;
  int cancel_pipe[2];

  pthread_mutex_t mtx;
  pthread_cond_t not_full;
  cocoon_input_record* queue;
  size_t cap;
  size_t head; // next push slot
  size_t tail; // next pop slot
  size_t count;
  bool notify_armed;
  bool stopping;
} cocoon_input_pump;

static int64_t monotonic_ns(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/// Push one record onto the ring under the mutex. Blocks while the queue is
/// full (no event is dropped); returns false if the pump is stopping.
static bool pump_push(cocoon_input_pump* pump, uint32_t id,
                      uint32_t modifiers, int64_t ns) {
  pthread_mutex_lock(&pump->mtx);
  while (pump->count == pump->cap && !pump->stopping) {
    pthread_cond_wait(&pump->not_full, &pump->mtx);
  }
  if (pump->stopping) {
    pthread_mutex_unlock(&pump->mtx);
    return false;
  }
  const bool was_empty = (pump->count == 0);
  cocoon_input_record* slot = &pump->queue[pump->head];
  slot->id = id;
  slot->modifiers = modifiers;
  slot->monotonic_ns = ns;
  pump->head = (pump->head + 1) % pump->cap;
  pump->count++;
  // Edge-triggered notification: only the 0→1 transition arms + fires. Later
  // pushes while Dart hasn't drained leave notify_armed set and stay silent.
  if (was_empty) {
    pump->notify_armed = true;
    pthread_mutex_unlock(&pump->mtx);
    pump->notify();
    return true;
  }
  pthread_mutex_unlock(&pump->mtx);
  return true;
}

static void* pump_main(void* opaque) {
  cocoon_input_pump* pump = opaque;
  const int readyfd = notcurses_inputready_fd(pump->nc);
  if (readyfd < 0) return NULL;
  struct pollfd fds[2] = {
    { .fd = readyfd, .events = POLLIN },
    { .fd = pump->cancel_pipe[0], .events = POLLIN },
  };
  for (;;) {
    int rc;
    do {
      rc = poll(fds, 2, -1);
    } while (rc < 0 && errno == EINTR);
    if (rc < 0 || (fds[1].revents & POLLIN)) break;
    if (!(fds[0].revents & POLLIN)) continue;
    for (;;) {
      ncinput input = {0};
      const uint32_t id = notcurses_get_nblock(pump->nc, &input);
      if (id == 0 || id == (uint32_t)-1) break;
      // Under the kitty/extended-keyboard protocol a single physical key
      // produces a PRESS and a RELEASE ncinput. We only ever want presses
      // (REPEAT is kept so held-key auto-repeat still scrolls/types), so drop
      // releases here — the one place that owns the ncinput, since evtype
      // isn't propagated to Dart (PumpedInput carries only id/modifiers).
      if (input.evtype == NCTYPE_RELEASE) continue;
      if (!pump_push(pump, id, input.modifiers, monotonic_ns())) {
        // Stopping: drain remaining kernel events is not safe once the queue
        // is rejecting; bail out of the inner loop so stop can join us.
        goto done;
      }
    }
  }
done:
  return NULL;
}

void* cocoon_input_pump_start(struct notcurses* nc,
                              cocoon_input_notify notify) {
  if (!nc || !notify) return NULL;
  cocoon_input_pump* pump = calloc(1, sizeof(*pump));
  if(!pump) return NULL;
  pump->nc = nc;
  pump->notify = notify;
  pump->cap = COCOON_INPUT_QUEUE_CAP;
  pump->queue = calloc(pump->cap, sizeof(cocoon_input_record));
  if(!pump->queue) { free(pump); return NULL; }
  if(pthread_mutex_init(&pump->mtx, NULL) != 0) {
    free(pump->queue); free(pump); return NULL;
  }
  if(pthread_cond_init(&pump->not_full, NULL) != 0) {
    pthread_mutex_destroy(&pump->mtx);
    free(pump->queue); free(pump); return NULL;
  }
  if(pipe(pump->cancel_pipe) != 0) {
    pthread_cond_destroy(&pump->not_full);
    pthread_mutex_destroy(&pump->mtx);
    free(pump->queue); free(pump); return NULL;
  }
  if(pthread_create(&pump->thread, NULL, pump_main, pump) != 0) {
    close(pump->cancel_pipe[0]);
    close(pump->cancel_pipe[1]);
    pthread_cond_destroy(&pump->not_full);
    pthread_mutex_destroy(&pump->mtx);
    free(pump->queue); free(pump); return NULL;
  }
  return pump;
}

size_t cocoon_input_pump_drain(void* opaque, cocoon_input_record* out,
                               size_t max) {
  cocoon_input_pump* pump = opaque;
  if(!pump || !out || max == 0) return 0;
  pthread_mutex_lock(&pump->mtx);
  size_t n = pump->count < max ? pump->count : max;
  for(size_t i = 0; i < n; i++) {
    out[i] = pump->queue[pump->tail];
    pump->tail = (pump->tail + 1) % pump->cap;
    pump->count--;
  }
  if(pump->count == 0) {
    // Drained to empty: clear the armed flag so the next 0→1 transition
    // re-fires the listener (the lost-wakeup-free invariant).
    pump->notify_armed = false;
  }
  if(n > 0) {
    // Free any producer blocked on a full queue.
    pthread_cond_signal(&pump->not_full);
  }
  pthread_mutex_unlock(&pump->mtx);
  return n;
}

void cocoon_input_pump_stop(void* opaque) {
  cocoon_input_pump* pump = opaque;
  if(!pump) return;
  // Mark stopping under the mutex so a blocked producer (queue-full) wakes and
  // returns false instead of pushing into a being-torn-down queue.
  pthread_mutex_lock(&pump->mtx);
  pump->stopping = true;
  pthread_cond_broadcast(&pump->not_full);
  pthread_mutex_unlock(&pump->mtx);

  const uint8_t byte = 1;
  (void)write(pump->cancel_pipe[1], &byte, sizeof(byte));
  (void)pthread_join(pump->thread, NULL);
  close(pump->cancel_pipe[0]);
  close(pump->cancel_pipe[1]);
  pthread_cond_destroy(&pump->not_full);
  pthread_mutex_destroy(&pump->mtx);
  free(pump->queue);
  free(pump);
}

#else // _WIN32 ---------------------------------------------------------------
// TODO(windows): replace this stub with a real ConPTY input pump. The POSIX
// pump above runs a thread that polls notcurses_inputready_fd(nc) + a cancel
// pipe, dequeues with notcurses_get_nblock, and notifies Dart via the
// cocoon_input_notify callback on the empty->non-empty queue transition. The
// Windows port should mirror that using WaitForMultipleObjects on the
// inputready handle and a cancel event, batch-drain into the same ring, and
// call the listener through a NativeCallable. Until that lands these stubs
// return "no events ever": notcurses_merged.dll still links, the @Native
// cocoon_input_pump_* externs (notcurses.dart) resolve, output rendering works,
// and native input is supplied by AnsiInputBackend on the Dart side.

void* cocoon_input_pump_start(struct notcurses* nc,
                              cocoon_input_notify notify) {
  (void)nc;
  (void)notify;
  // Non-null sentinel: the Dart side treats construction as success. The pump
  // owns no resources and produces no events, so drain() always reports zero.
  return (void*)1;
}

size_t cocoon_input_pump_drain(void* opaque, cocoon_input_record* out,
                               size_t max) {
  (void)opaque;
  (void)out;
  (void)max;
  return 0;
}

void cocoon_input_pump_stop(void* opaque) {
  (void)opaque;
}
#endif // _WIN32

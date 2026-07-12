#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include <notcurses/notcurses.h>

// NOTCURSES_FFI deliberately rewrites `static` while emitting notcurses'
// inline symbols from ffi.c. Restore the C keyword for this independent TU.
#ifdef static
#undef static
#endif

typedef void (*cocoon_input_callback)(uint32_t id, uint32_t modifiers,
                                      int64_t monotonic_ns);

typedef struct cocoon_input_pump {
  struct notcurses* nc;
  cocoon_input_callback callback;
  pthread_t thread;
  int cancel_pipe[2];
} cocoon_input_pump;

static int64_t monotonic_ns(void) {
  struct timespec ts;
  if(clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void* pump_main(void* opaque) {
  cocoon_input_pump* pump = opaque;
  const int readyfd = notcurses_inputready_fd(pump->nc);
  if(readyfd < 0) return NULL;
  struct pollfd fds[2] = {
    { .fd = readyfd, .events = POLLIN },
    { .fd = pump->cancel_pipe[0], .events = POLLIN },
  };
  for(;;) {
    int rc;
    do {
      rc = poll(fds, 2, -1);
    } while(rc < 0 && errno == EINTR);
    if(rc < 0 || (fds[1].revents & POLLIN)) break;
    if(!(fds[0].revents & POLLIN)) continue;
    for(;;) {
      ncinput input = {0};
      const uint32_t id = notcurses_get_nblock(pump->nc, &input);
      if(id == 0 || id == (uint32_t)-1) break;
      pump->callback(id, input.modifiers, monotonic_ns());
    }
  }
  return NULL;
}

void* cocoon_input_pump_start(struct notcurses* nc,
                              cocoon_input_callback callback) {
  if(!nc || !callback) return NULL;
  cocoon_input_pump* pump = calloc(1, sizeof(*pump));
  if(!pump) return NULL;
  pump->nc = nc;
  pump->callback = callback;
  if(pipe(pump->cancel_pipe) != 0) {
    free(pump);
    return NULL;
  }
  if(pthread_create(&pump->thread, NULL, pump_main, pump) != 0) {
    close(pump->cancel_pipe[0]);
    close(pump->cancel_pipe[1]);
    free(pump);
    return NULL;
  }
  return pump;
}

void cocoon_input_pump_stop(void* opaque) {
  cocoon_input_pump* pump = opaque;
  if(!pump) return;
  const uint8_t byte = 1;
  (void)write(pump->cancel_pipe[1], &byte, sizeof(byte));
  (void)pthread_join(pump->thread, NULL);
  close(pump->cancel_pipe[0]);
  close(pump->cancel_pipe[1]);
  free(pump);
}

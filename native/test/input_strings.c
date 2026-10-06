// Include the actual parser so its static callbacks can be exercised without
// a terminal. The response ends at a protected page: an overread fails even
// when neighboring heap data would otherwise contain a convenient ESC byte.
#include "lib/in.c"
#include <sys/mman.h>

static unsigned char*
guarded_response(const char* response, void** mapping, size_t* mapping_size){
  const size_t page = (size_t)sysconf(_SC_PAGESIZE);
  const size_t len = strlen(response);
  assert(len < page);
  *mapping_size = page * 2;
  *mapping = mmap(NULL, *mapping_size, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANON, -1, 0);
  assert(*mapping != MAP_FAILED);
  assert(mprotect((char*)*mapping + page, page, PROT_NONE) == 0);
  unsigned char* bytes = (unsigned char*)*mapping + page - len;
  memcpy(bytes, response, len);
  return bytes;
}

static void
check_palette(const char* response, unsigned idx, uint32_t expected){
  void* mapping;
  size_t mapping_size;
  unsigned char* bytes = guarded_response(response, &mapping, &mapping_size);
  inputctx ictx = {0};
  struct initial_responses initial = { .maxpaletteread = -1 };
  ictx.initdata = &initial;
  assert(inputctx_add_cflow(&ictx.amata, "]4;\\N;rgb:\\S", palette_cb) == 0);
  walk_escape_automaton(&ictx, bytes);
  assert(process_escape(&ictx, bytes, (int)strlen(response)) == (int)strlen(response));
  if(idx < NCPALETTESIZE){
    assert(initial.palette.chans[idx] == expected);
    assert(initial.maxpaletteread == (int)idx);
  }else{
    // Index 256 used to overwrite maxpaletteread immediately after chans[].
    assert(initial.maxpaletteread == -1);
    for(unsigned i = 0; i < NCPALETTESIZE; ++i){
      assert(initial.palette.chans[i] == 0);
    }
  }
  input_free_esctrie(&ictx.amata);
  assert(munmap(mapping, mapping_size) == 0);
}

static void
check_default(const char* response, bool background){
  void* mapping;
  size_t mapping_size;
  inputctx ictx = {0};
  struct initial_responses initial = {0};
  ictx.initdata = &initial;
  ictx.amata.matchstart = guarded_response(response, &mapping, &mapping_size);
  assert((background ? bgdef_cb(&ictx) : fgdef_cb(&ictx)) == 2);
  assert(background ? initial.got_bg : initial.got_fg);
  assert((background ? initial.bg : initial.fg) == 0x123456);
  assert(munmap(mapping, mapping_size) == 0);
}

static void
check_input_after_partial_reply(void){
  inputctx ictx = {0};
  ncsharedstats stats = {0};
  ncinput inputs[256] = {0};
  ictx.inputs = inputs;
  ictx.isize = 256;
  ictx.stats = &stats;
  assert(pthread_mutex_init(&stats.lock, NULL) == 0);
  assert(pthread_mutex_init(&ictx.ilock, NULL) == 0);
  assert(pthread_cond_init(&ictx.icond, NULL) == 0);
  assert(getpipes(ictx.readypipes) == 0);
  assert(inputctx_add_cflow(&ictx.amata, "]4;\\N;rgb:\\S", palette_cb) == 0);
  assert(inputctx_add_input_escape(&ictx.amata, "\x1b[D", NCKEY_LEFT, 0) == 0);
  const unsigned char partial[] = "\x1b]4;41;rgb:0000/d7d7/5f5f";
  int remaining = sizeof(partial) - 1;
  process_melange(&ictx, partial, &remaining);
  assert(remaining == 0);
  remaining = 1;
  process_melange(&ictx, (const unsigned char*)"\x07", &remaining);
  assert(remaining == 0);
  assert(inputs[ictx.iwrite - 1].id == 'G');
  assert(inputs[ictx.iwrite - 1].modifiers == NCKEY_MOD_CTRL);
  remaining = 3;
  process_melange(&ictx, (const unsigned char*)"\x1b[D", &remaining);
  assert(remaining == 0);
  assert(inputs[ictx.iwrite - 1].id == NCKEY_LEFT);
  input_free_esctrie(&ictx.amata);
  endpipes(ictx.readypipes);
  assert(pthread_cond_destroy(&ictx.icond) == 0);
  assert(pthread_mutex_destroy(&ictx.ilock) == 0);
  assert(pthread_mutex_destroy(&stats.lock) == 0);
}

int main(void){
  check_palette("\x1b]4;41;rgb:0000/d7d7/5f5f\x07", 41, 0x00d75f);
  check_palette("\x1b]4;41;rgb:0000/d7d7/5f5f\x1b\\", 41, 0x00d75f);
  check_palette("\x1b]4;0;rgb:12/34/56\x07", 0, 0x123456);
  check_palette("\x1b]4;255;rgb:ffff/ffff/ffff\x07", 255, 0xffffff);
  check_palette("\x1b]4;256;rgb:1234/5678/9abc\x07", 256, 0);
  check_palette("\x1b]4;257;rgb:1234/5678/9abc\x1b\\", 257, 0);
  check_default("\x1b]10;rgb:1234/3456/5678\x07", false);
  check_default("\x1b]11;rgb:1234/3456/5678\x07", true);
  check_default("\x1b]10;rgb:12/34/56\x1b\\", false);
  check_default("\x1b]11;rgb:12/34/56\x1b\\", true);
  check_input_after_partial_reply();
  puts("PASS native input: BEL, ST, palette bounds, recovery after partial replies");
  return 0;
}

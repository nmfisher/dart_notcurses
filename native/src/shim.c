// Minimal shim providing ncdirect_init and notcurses_init wrappers.
// These simply delegate to the _core_init variants from libnotcurses-core.
// The full versions in libnotcurses.a set up FFmpeg-based visual support,
// which we don't include to avoid the FFmpeg dependency.

#include <stdio.h>
#include <notcurses/notcurses.h>
#include <notcurses/direct.h>

struct ncdirect* ncdirect_init(const char* termtype, FILE* fp, uint64_t flags){
  return ncdirect_core_init(termtype, fp, flags);
}

struct notcurses* notcurses_init(const struct notcurses_options* opts, FILE* fp){
  return notcurses_core_init(opts, fp);
}

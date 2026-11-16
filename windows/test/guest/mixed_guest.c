// mixed_guest.c -- an x86_64 app with one library only its arm64 set has
// (winapk-linker-test). AppInstall installs the arm64 set in lib/arm64 beside
// the x86_64 one then, and the arm64 library's dependencies must be the arm64
// copies next to it, although x86_64 libraries of the same names are loaded.
//
//   WINAPK_MIXED_DEP   libwinapk_mixed_dep.so   built for x86_64 and for arm64
//   WINAPK_MIXED_ROOT  libwinapk_mixed_root.so  arm64, needs libwinapk_mixed_dep.so
//
// No constructors: the test only links them, it runs no arm64 code.

#define EXPORT __attribute__((visibility("default")))

#if defined(WINAPK_MIXED_DEP)

// The ABI it was built for, as e_machine: 62 for x86_64, 183 for arm64.
EXPORT int mixed_dep_abi(void) {
#if defined(__aarch64__)
    return 183;
#else
    return 62;
#endif
}

#elif defined(WINAPK_MIXED_ROOT)

int mixed_dep_abi(void);
EXPORT int mixed_root_dep_abi(void) { return mixed_dep_abi(); }

#endif

// pdprof.c - Blueprint profiler for Pacific Drive (UE 4.27), loaded as a dwmapi.dll proxy.
// Hooks UObject::ProcessInternal and ProcessLocalScriptFunction (every Blueprint function call), times each
// UFunction on the game thread (calls, inclusive and exclusive TSC ticks) and writes cumulative totals to
// pd_prof.txt every 10 s. Addresses are for PenDriverPro-Win64-Shipping.exe sha1 21a0e88d.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <x86intrin.h>

typedef void (*Thunk)(void *ctx, void *stack, void *res);

#define RVA_PROCESS_INTERNAL 0x158b5e0
#define LEN_PROCESS_INTERNAL 20 // mov [rsp+8],rbx; mov [rsp+10],rbp; mov [rsp+18],rsi; push rdi; push r14; push r15
#define RVA_PROCESS_LOCAL 0x158b6f0
#define LEN_PROCESS_LOCAL 15 // mov [rsp+8],rbx; mov [rsp+20],rsi; push rdi; sub rsp,70
#define FFRAME_NODE 0x10     // FFrame::Node (the UFunction being executed)
#define RVA_FNAME_TOSTRING 0x1382f80 // void FName::ToString(FString& Out) const
#define UOBJECT_NAME 0x18    // UObjectBase::NamePrivate
#define UOBJECT_OUTER 0x20   // UObjectBase::OuterPrivate

static DWORD game_thread;
static Thunk t_internal, t_local;

typedef struct { void *fn; unsigned long long calls, incl, excl; char *name; } Entry;
#define NENT 65536
static Entry table[NENT];
#define MAXD 512
static unsigned long long child[MAXD];
static int depth;

static Entry *lookup(void *fn) {
    unsigned i = (unsigned)(((ULONG_PTR)fn >> 4) * 2654435761u) & (NENT - 1);
    while (table[i].fn && table[i].fn != fn) i = (i + 1) & (NENT - 1);
    table[i].fn = fn;
    return &table[i];
}

typedef struct { wchar_t *data; int num, max; } FString;
typedef void (*ToStringFn)(void *name, FString *out);
static ToStringFn fname_tostring;

static void append_name(char *buf, size_t cap, void *obj) {
    FString s = {0};
    fname_tostring((char *)obj + UOBJECT_NAME, &s); // leaks the engine-allocated buffer; each name is resolved once
    size_t n = strlen(buf);
    for (int i = 0; s.data && s.data[i] && n + 1 < cap; i++) buf[n++] = (char)s.data[i];
    buf[n] = 0;
}

// "Class:Function" for a UFunction (its Outer is the owning class)
static char *func_name(void *fn) {
    char buf[256] = "";
    void *outer = *(void **)((char *)fn + UOBJECT_OUTER);
    if (outer) { append_name(buf, sizeof buf, outer); strcat(buf, ":"); }
    append_name(buf, sizeof buf, fn);
    return _strdup(buf);
}

static inline void prof(Thunk orig, void *ctx, void *stack, void *res) {
    if (__readgsdword(0x48) != game_thread || depth >= MAXD) { orig(ctx, stack, res); return; }
    void *fn = *(void **)((char *)stack + FFRAME_NODE);
    int d = depth++;
    child[d] = 0;
    unsigned long long t0 = __rdtsc();
    orig(ctx, stack, res);
    unsigned long long dt = __rdtsc() - t0;
    depth--;
    Entry *e = lookup(fn);
    if (!e->name) e->name = func_name(fn); // game thread: the UFunction is alive while it runs
    e->calls++; e->incl += dt; e->excl += dt - child[d];
    if (d > 0) child[d - 1] += dt;
}

static void hook_internal(void *ctx, void *stack, void *res) { prof(t_internal, ctx, stack, res); }
static void hook_local(void *ctx, void *stack, void *res) { prof(t_local, ctx, stack, res); }

// jmp [rip+0]; dq target
static void put_jmp(unsigned char *at, void *target) {
    at[0] = 0xff; at[1] = 0x25; memset(at + 2, 0, 4);
    memcpy(at + 6, &target, 8);
}

static Thunk install(unsigned char *fn, int len, void *hook) {
    unsigned char *tramp = VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    memcpy(tramp, fn, len);
    put_jmp(tramp + len, fn + len);
    DWORD old;
    VirtualProtect(fn, len, PAGE_EXECUTE_READWRITE, &old);
    put_jmp(fn, hook);
    memset(fn + 14, 0x90, len - 14);
    VirtualProtect(fn, len, old, &old);
    FlushInstructionCache(GetCurrentProcess(), fn, len);
    return (Thunk)tramp;
}

static DWORD WINAPI reporter(LPVOID unused) {
    LARGE_INTEGER f, q;
    QueryPerformanceFrequency(&f);
    for (;;) {
        Sleep(10000);
        FILE *o = fopen("pd_prof.tmp", "w");
        if (!o) continue;
        QueryPerformanceCounter(&q);
        fprintf(o, "qpc %lld %lld tsc %llu\n", q.QuadPart, f.QuadPart, __rdtsc());
        for (int i = 0; i < NENT; i++)
            if (table[i].name)
                fprintf(o, "%llx %llu %llu %llu %s\n", (unsigned long long)table[i].fn, table[i].calls, table[i].incl, table[i].excl, table[i].name);
        fclose(o);
        MoveFileExA("pd_prof.tmp", "pd_prof.txt", MOVEFILE_REPLACE_EXISTING);
    }
    return 0;
}

// dwmapi.dll exports the game imports, forwarded to the real system dll
static HMODULE real;
static FARPROC real_proc(const char *name) {
    if (!real) real = LoadLibraryA("C:\\windows\\system32\\dwmapi.dll");
    return GetProcAddress(real, name);
}
__declspec(dllexport) HRESULT WINAPI DwmFlush(void) {
    return ((HRESULT(WINAPI *)(void))real_proc("DwmFlush"))();
}
__declspec(dllexport) HRESULT WINAPI DwmGetCompositionTimingInfo(HWND h, void *info) {
    return ((HRESULT(WINAPI *)(HWND, void *))real_proc("DwmGetCompositionTimingInfo"))(h, info);
}
__declspec(dllexport) HRESULT WINAPI DwmSetWindowAttribute(HWND h, DWORD a, LPCVOID v, DWORD n) {
    return ((HRESULT(WINAPI *)(HWND, DWORD, LPCVOID, DWORD))real_proc("DwmSetWindowAttribute"))(h, a, v, n);
}
__declspec(dllexport) HRESULT WINAPI DwmIsCompositionEnabled(BOOL *e) {
    return ((HRESULT(WINAPI *)(BOOL *))real_proc("DwmIsCompositionEnabled"))(e);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    // Loaded while the exe's imports resolve: this is the main thread (UE's game thread) and no game code runs yet
    game_thread = GetCurrentThreadId();
    unsigned char *base = (unsigned char *)GetModuleHandleA(NULL);
    fname_tostring = (ToStringFn)(base + RVA_FNAME_TOSTRING);
    t_internal = install(base + RVA_PROCESS_INTERNAL, LEN_PROCESS_INTERNAL, hook_internal);
    t_local = install(base + RVA_PROCESS_LOCAL, LEN_PROCESS_LOCAL, hook_local);
    CreateThread(NULL, 0, reporter, NULL, 0, NULL);
    return TRUE;
}

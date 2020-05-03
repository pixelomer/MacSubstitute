// The MIT License (MIT)
// 
// Copyright (c) 2013 Stanley Cen
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// Source: https://github.com/scen/osxinj

#include <cstdio>
#include <cstring>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/mach_init.h>
#include <pthread.h>
#include <pwd.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <sys/types.h>
#include <mach/error.h>
#include <mach/vm_types.h>
#include <stddef.h>

#define DLLEXPORT __attribute__((visibility("default")))

#if __MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_12
#define PTHREAD_SET_SELF _pthread_set_self
#else
#define PTHREAD_SET_SELF __pthread_set_self
#endif

extern "C" void PTHREAD_SET_SELF(void*);
extern "C" void bootstrap(ptrdiff_t offset, void *param, size_t psize, void *dummy) DLLEXPORT;

static void *loaderThread(void *param)
{
    fprintf(stderr, "Bootstrap.dylib has loaded. Now loading TweakLoader (%s).\n", (char*)param);
    void *bundle = dlopen((char *)param, RTLD_NOW);
    if (!bundle) {
        fprintf(stderr, "An error occurred, which prevented the bootstrap from loading the tweak loader.\n%s\n", dlerror());
    }
    return (void*)0;
}

void bootstrap(ptrdiff_t offset, void *param, size_t psize, void *dummy)
{
    PTHREAD_SET_SELF(dummy);

    pthread_attr_t attr;
    pthread_attr_init(&attr); 
    
    int policy;
    pthread_attr_getschedpolicy(&attr, &policy);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_setinheritsched(&attr, PTHREAD_EXPLICIT_SCHED);
    
    struct sched_param sched;
    sched.sched_priority = sched_get_priority_max(policy);
    pthread_attr_setschedparam(&attr, &sched);

    pthread_t thread;
    pthread_create(&thread, &attr,
            (void * (*)(void *))((long)loaderThread),
            (void*)param);
    pthread_attr_destroy(&attr);
    
    thread_suspend(mach_thread_self());
}

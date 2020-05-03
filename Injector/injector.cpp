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

#include "injector.h"

#include <cstdio>
#include <cstring>

#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/mach_init.h>
#include <pthread.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/proc_info.h>
#include <libproc.h>    

Injector::Injector() : module(0), bootstrapfn(0)
{
    module = dlopen("/usr/local/MacSubstitute/Bootstrap.dylib",
        RTLD_NOW | RTLD_LOCAL);

    printf("module: %p\n", module);
    if (!module)
    {
        fprintf(stderr, "dlopen error: %s\n", dlerror());
        return;
    }

    bootstrapfn = dlsym(module, "bootstrap");
    printf("bootstrapfn: %p\n", bootstrapfn);

    if (!bootstrapfn)
    {
        fprintf(stderr, "could not locate bootstrap fn\n");
        return;
    }
}

Injector::~Injector()
{
    if (module)
    {
        dlclose(module);
        module = NULL;
    }
}

void Injector::inject(pid_t pid, const char* lib)
{
    if (!module || !bootstrapfn)
    {
        fprintf(stderr, "failed to inject: module:%p bootstrapfn:%p\n", module, bootstrapfn);
        return;
    }
    mach_error_t err = mach_inject((mach_inject_entry)bootstrapfn, lib, strlen(lib) + 1, pid, 0);
}

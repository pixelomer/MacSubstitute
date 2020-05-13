#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "injector.h"
#import <sys/sysctl.h>
#import <pwd.h>
#import <errno.h>
#import <libproc.h>

static int _GetBSDProcessList(kinfo_proc **procList, size_t *procCount)
// Returns a list of all BSD processes on the system.  This routine
// allocates the list and puts it in *procList and a count of the
// number of entries in *procCount.  You are responsible for freeing
// this list (use "free" from System framework).
// On success, the function returns 0.
// On error, the function returns a BSD errno value.
{
	int                 err;
	kinfo_proc *        result;
	bool                done;
	static const int    name[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
	// Declaring name as const requires us to cast it when passing it to
	// sysctl because the prototype doesn't include the const modifier.
	size_t              length;

	//    assert( procList != NULL);
	//    assert(*procList == NULL);
	//    assert(procCount != NULL);

	*procCount = 0;

	// We start by calling sysctl with result == NULL and length == 0.
	// That will succeed, and set length to the appropriate length.
	// We then allocate a buffer of that size and call sysctl again
	// with that buffer.  If that succeeds, we're done.  If that fails
	// with ENOMEM, we have to throw away our buffer and loop.  Note
	// that the loop causes use to call sysctl with NULL again; this
	// is necessary because the ENOMEM failure case sets length to
	// the amount of data returned, not the amount of data that
	// could have been returned.

	result = NULL;
	done = false;
	do {
		assert(result == NULL);

		// Call sysctl with a NULL buffer.

		length = 0;
		err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);
		if (err == -1) {
			err = errno;
		}

		// Allocate an appropriately sized buffer based on the results
		// from the previous call.

		if (err == 0) {
			result = (typeof(result))malloc(length);
			if (result == NULL) {
				err = ENOMEM;
			}
		}

		// Call sysctl again with the new buffer.  If we get an ENOMEM
		// error, toss away our buffer and start again.

		if (err == 0) {
			err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, result, &length, NULL, 0);
			if (err == -1) {
				err = errno;
			}
			if (err == 0) {
				done = true;
			} else if (err == ENOMEM) {
				assert(result != NULL);
				free(result);
				result = NULL;
				err = 0;
			}
		}
	} while (err == 0 && ! done);

	// Clean up and establish post conditions.

	if (err != 0 && result != NULL) {
		free(result);
		result = NULL;
	}
	*procList = result;
	if (err == 0) {
		*procCount = length / sizeof(kinfo_proc);
	}

	assert( (err == 0) == (*procList != NULL) );

	return err;
}

static NSMutableDictionary *oldPIDs = nil;

static NSArray *GetNewProcesses() {
	kinfo_proc *list = NULL;
	size_t count = 0;
	_GetBSDProcessList(&list, &count);
	if (!list || !count) return @[];
	NSMutableDictionary *newPIDs = [NSMutableDictionary dictionaryWithCapacity:count];
	NSMutableArray *processes = [NSMutableArray arrayWithCapacity:count];
	if (!processes || !newPIDs) return nil;
	for (NSUInteger i=0; i<count; i++) { @autoreleasepool {
		struct kinfo_proc *currentProcess = &list[i];
		NSNumber *pid = @(currentProcess->kp_proc.p_pid);
		if (!pid) continue;
		NSMutableDictionary *processDict = [NSMutableDictionary dictionaryWithCapacity:5];
		char procPathBuffer[PROC_PIDPATHINFO_MAXSIZE];
		if (proc_pidpath(currentProcess->kp_proc.p_pid, procPathBuffer, sizeof(procPathBuffer))) {
			NSString *path = @(procPathBuffer);
			if (!path) continue;
			processDict[@"path"] = path;
		}
		else continue;
		newPIDs[pid] = processDict[@"path"];
		if (!oldPIDs || [oldPIDs[pid] isEqualToString:processDict[@"path"]]) continue;
		struct passwd *passwd = getpwuid(currentProcess->kp_eproc.e_ucred.cr_uid);
		if (!passwd) continue;
		NSNumber *uid = @(passwd->pw_uid);
		NSNumber *gid = @(passwd->pw_gid);
		NSString *homeDirectory = passwd->pw_dir ? @(passwd->pw_dir) : nil;
		if (!uid || !gid) continue;
		if (homeDirectory) processDict[@"home"] = homeDirectory;
		processDict[@"pid"] = pid;
		processDict[@"uid"] = uid;
		processDict[@"gid"] = gid;
		NSDictionary *processDictCopy = [processDict copy];
		if (!processDictCopy) continue;
		[processes addObject:processDictCopy];
	}}
	oldPIDs = [newPIDs copy];
	free(list);
	return [processes copy];
}

static Injector injector;

@interface MSDelegate : NSObject
@end

@implementation MSDelegate

static NSMutableArray<NSString *> *deletablePaths;

+ (void)load {
	if ([MSDelegate class] == self) {
		deletablePaths = [NSMutableArray new];
	}
}

+ (void)handleCleanupNotification:(NSNotification *)notif {
	NSString *path = notif.object;
	printf("Received a cleanup notification for path: %s\n", [notif.object UTF8String]);
	if (![path.lastPathComponent isEqualToString:@"\x01SubstituteLink"]) {
		printf("Ignoring notification since this folder is not a hard link folder.\n\n");
		return;
	}
	if (![deletablePaths containsObject:path]) {
		printf("This folder was not created by this process. This does not mean that this folder wasn't created by substituted.\n\n");
		return;
	}
	for (NSUInteger i=0; i<deletablePaths.count; i++) {
		if ([deletablePaths[i] isEqualToString:path]) {
			[deletablePaths removeObjectAtIndex:i];
			break;
		}
	}
	if ([deletablePaths containsObject:path]) {
		printf("Not deleting folder since this folder could still be in use by another process.\n\n");
		return;
	}
	printf("Deleting folder... ");
	if ([NSFileManager.defaultManager removeItemAtPath:path error:nil]) printf("success");
	else printf("failed");
	printf("\n\n");
}

+ (void)timerTick {
	NSArray *currentArr = GetNewProcesses();
	if (currentArr) if (currentArr.count) for (NSDictionary *dict in currentArr) {
		if (!dict[@"pid"] || !dict[@"uid"]) continue;
		printf("[+] PID %s (%s)\n", 
			[dict[@"pid"] description].UTF8String,
			[dict[@"path"] UTF8String]
		);
		pid_t pid = [dict[@"pid"] unsignedIntValue];
		uid_t uid = [dict[@"uid"] unsignedIntValue];
		gid_t gid = [dict[@"gid"] unsignedIntValue];
		char tweakLoaderPathForApp[PATH_MAX];
		tweakLoaderPathForApp[0] = 0;
		NSString *execPath = dict[@"path"];
		// "/"  "aaa.app"  "Contents"   "MacOS"  "Executable"
		// -5       -4         -3         -2         -1
		NSString *bundleIdentifier = nil;
		NSURL *URL = nil;
		if ([dict[@"home"] length] &&
			(execPath.pathComponents.count > 4+!![execPath.pathComponents[0] isEqualToString:@"/"]) &&
			([execPath.pathComponents[execPath.pathComponents.count-2] isEqualToString:@"MacOS"]) &&
			([execPath.pathComponents[execPath.pathComponents.count-3] isEqualToString:@"Contents"]) &&
			((execPath = [[[execPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent])) &&
			((URL = [NSURL fileURLWithPath:execPath])) &&
			((bundleIdentifier = [(__bridge NSDictionary *)CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)URL) objectForKey:@"CFBundleIdentifier"])))
		{
			NSString *hardLinkPath = [NSString
				stringWithFormat:@"%@/Library/Containers/%@/Data/Documents/\x01SubstituteLink",
				dict[@"home"],
				bundleIdentifier
			];
			if ([NSFileManager.defaultManager fileExistsAtPath:[hardLinkPath stringByDeletingLastPathComponent]]) {
				[NSFileManager.defaultManager
					removeItemAtPath:hardLinkPath
					error:nil
				];
				[NSFileManager.defaultManager
					linkItemAtPath:@"/usr/local/MacSubstitute"
					toPath:hardLinkPath
					error:nil
				];
				chown(hardLinkPath.UTF8String, uid, gid);
				NSArray<NSString *> *subpaths = [NSFileManager.defaultManager subpathsAtPath:hardLinkPath];
				if (subpaths) for (NSString *subpath in subpaths) {
					NSString *fullPath = [hardLinkPath stringByAppendingPathComponent:subpath];
					chown(fullPath.UTF8String, uid, gid);
				}
				[deletablePaths addObject:hardLinkPath];
				strcpy(tweakLoaderPathForApp, [hardLinkPath stringByAppendingPathComponent:@"TweakLoader.dylib"].UTF8String);
			}
		}
		else continue;
		if (!tweakLoaderPathForApp[0]) strcpy(tweakLoaderPathForApp, "/usr/local/MacSubstitute/TweakLoader.dylib");
		injector.inject(pid, tweakLoaderPathForApp);
	}
}

@end

int main(int argc, char **argv) {
	if ((getuid()  && setuid(0))  ||
		(getgid()  && setgid(0))  ||
		(getegid() && setegid(0)) ||
		(geteuid() && seteuid(0)))
	{
		fprintf(stderr, "Could not get root privileges.\n");
		return 1;
	}
	[[NSDistributedNotificationCenter defaultCenter]
		addObserver:[MSDelegate class]
		selector:@selector(handleCleanupNotification:)
		name:@"com.pixelomer.MacSubstitute/Cleanup"
		object:nil
		suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately
	];
	NSTimer *__unused timer = [NSTimer
		scheduledTimerWithTimeInterval:0.05
		target:[MSDelegate class]
		selector:@selector(timerTick)
		userInfo:nil
		repeats:YES
	];
	while (1) [[NSRunLoop currentRunLoop] run];
	return 0;
}
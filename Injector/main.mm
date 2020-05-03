#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "injector.h"
#import <sys/sysctl.h>
#import <pwd.h>
#import <errno.h>

// Source: https://stackoverflow.com/a/20169895/7085621
static uid_t MSGetUIDFromPID(pid_t pid)
{
    uid_t uid = -1;

    struct kinfo_proc process;
    size_t procBufferSize = sizeof(process);

    // Compose search path for sysctl. Here you can specify PID directly.
    const u_int pathLenth = 4;
    int path[pathLenth] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};

    int sysctlResult = sysctl(path, pathLenth, &process, &procBufferSize, NULL, 0);

    // If sysctl did not fail and process with PID available - take UID.
    if ((sysctlResult == 0) && (procBufferSize != 0))
    {
        uid = process.kp_eproc.e_ucred.cr_uid;
    }

    return uid;
}

static Injector injector;

@interface MSDelegate : NSObject
+ (void)observeValueForKeyPath:(NSString *)keyPath
	ofObject:(id)object 
	change:(NSDictionary<NSKeyValueChangeKey, id> *)change 
	context:(void *)context;
@end

@implementation MSDelegate

static NSMutableArray<NSString *> *deletablePaths;

+ (void)load {
	if ([MSDelegate class] == self) {
		deletablePaths = [NSMutableArray new];
	}
}

+ (void)observeValueForKeyPath:(NSString *)keyPath
	ofObject:(id)object 
	change:(NSDictionary<NSKeyValueChangeKey, id> *)change 
	context:(void *)context
{
	for (NSRunningApplication *app in change[NSKeyValueChangeNewKey]) {
		pid_t pid = app.processIdentifier;
		uid_t uid = MSGetUIDFromPID(pid);
		printf("App: %s\n", app.bundleIdentifier.UTF8String);
		printf("UID: %d\n", uid);
		char tweakLoaderPathForApp[PATH_MAX+1];
		if (uid != -1) {
			struct passwd *passwd = getpwuid(uid);
			printf("passwd struct: %p\n", (void*)passwd);
			if (passwd) {
				const char *homeDirectoryCString = passwd->pw_dir;
				printf("Home directory: %s\n", homeDirectoryCString);
				if (homeDirectoryCString) {
					NSString *hardLinkPath = [NSString
						stringWithFormat:@"%s/Library/Containers/%@/Data/Documents/\x01SubstituteLink",
						homeDirectoryCString,
						app.bundleIdentifier
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
						chown(hardLinkPath.UTF8String, uid, passwd->pw_gid);
						NSArray<NSString *> *subpaths = [NSFileManager.defaultManager subpathsAtPath:hardLinkPath];
						if (subpaths) for (NSString *subpath in subpaths) {
							NSString *fullPath = [hardLinkPath stringByAppendingPathComponent:subpath];
							chown(fullPath.UTF8String, uid, passwd->pw_gid);
						}
						[deletablePaths addObject:hardLinkPath];
						strcpy(tweakLoaderPathForApp, [hardLinkPath stringByAppendingPathComponent:@"TweakLoader.dylib"].UTF8String);
					}
					else {
						strcpy(tweakLoaderPathForApp, "/usr/local/MacSubstitute/TweakLoader.dylib");
					}
				}
			}
		}
		injector.inject(app.processIdentifier, tweakLoaderPathForApp);
		printf("\n");
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
	[[NSWorkspace sharedWorkspace]
		addObserver:[MSDelegate class]
		forKeyPath:@"runningApplications"
		options:NSKeyValueObservingOptionNew
		context:NULL
	];
	while (1) [[NSRunLoop currentRunLoop] run];
	return 0;
}
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <pwd.h>

__attribute__((constructor))
int substitute_constructor(int argc, char **argv) {
	struct passwd *passwd = getpwuid(getuid());
	if (!NSBundle.mainBundle.bundleIdentifier || !passwd || !passwd->pw_dir || !strlen(passwd->pw_dir)) return 1;
	NSString *tweakDir = [NSString
		stringWithFormat:@"%s/Library/Containers/%@/Data/Documents/\x01SubstituteLink/DynamicLibraries",
		passwd->pw_dir,
		NSBundle.mainBundle.bundleIdentifier
	];
	fprintf(stderr, "Tweak directory in container: %s\n", tweakDir.UTF8String);
	if (![NSFileManager.defaultManager fileExistsAtPath:tweakDir]) {
		tweakDir = @"/usr/local/MacSubstitute/DynamicLibraries";
	}
	fprintf(stderr, "Tweak directory: %s\n", tweakDir.UTF8String);
	NSArray<NSString *> *tweaks = [NSFileManager.defaultManager
		contentsOfDirectoryAtPath:tweakDir
		error:nil
	];
	if (tweaks) for (NSString *filename in tweaks) { @autoreleasepool {
		if (![filename.pathExtension isEqualToString:@"plist"]) continue;
		NSString *fullPlistPath = [tweakDir stringByAppendingPathComponent:filename];
		NSString *fullDylibPath = [tweakDir stringByAppendingPathComponent:[[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"dylib"]];
		if (![NSFileManager.defaultManager fileExistsAtPath:fullDylibPath]) continue;
		NSDictionary *filterPlist = [NSDictionary dictionaryWithContentsOfFile:fullPlistPath];
		NSDictionary *filter = filterPlist[@"Filter"];
		if (![filter isKindOfClass:[NSDictionary class]]) continue;
		NSString *mode = filter[@"Mode"];
		BOOL mustMatchEveryFilter = YES;
		if (mode) {
			if (![mode isEqualToString:@"Any"]) continue;
			mustMatchEveryFilter = NO;
		}
		BOOL success = NO;
		for (NSString *filterKey in filter) {
			NSArray *filterValue = filter[filterKey]; 
			if (![filterValue isKindOfClass:[NSArray class]]) {
				success = NO;
				break;
			}
			else if ([filterKey isEqualToString:@"Bundles"]) {
				success = NO;
				for (NSString *bundleID in filterValue) {
					if ([bundleID isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
						success = YES;
					}
					else for (NSBundle *bundle in NSBundle.allFrameworks) {
						if ([bundle.bundleIdentifier isEqualToString:bundleID]) {
							success = YES;
							break;
						}
					}
					if (success) break;
				}
			}
			else if ([filterKey isEqualToString:@"Executables"]) {
				success = NO;
				NSString *procname = [NSProcessInfo processInfo].processName;
				for (NSString *execName in filterValue) {
					if ([procname isEqualToString:execName]) {
						success = YES;
						break;
					}
				}
			}
			else if ([filterKey isEqualToString:@"Classes"]) {
				success = NO;
				for (NSString *className in filterValue) {
					if (NSClassFromString(className)) {
						success = YES;
						break;
					}
				}
			}
			else if ([filterKey isEqualToString:@"CoreFoundationVersion"]) {
				if (filterValue.count < 1) {
					success = NO;
					break;
				}
				NSNumber *minimum = filterValue[0];
				NSNumber *maximum;
				if (filterValue.count <= 2) {
					maximum = filterValue[1];
					if (![maximum isKindOfClass:[NSNumber class]]) {
						success = NO;
						break;
					}
					success = !([maximum doubleValue] > kCFCoreFoundationVersionNumber);
				}
				if (success) {
					if (![minimum isKindOfClass:[NSNumber class]]) {
						success = NO;
						break;
					}
					success = !([minimum doubleValue] < kCFCoreFoundationVersionNumber);
				}
			}
			else continue;
			if (success && !mustMatchEveryFilter) break;
			else if (!success && mustMatchEveryFilter) break;
		}
		if (!success) continue;
		dlopen(fullDylibPath.UTF8String, RTLD_NOW);
	} }
	[[NSDistributedNotificationCenter defaultCenter]
		postNotificationName:@"com.pixelomer.MacSubstitute/Cleanup"
		object:[tweakDir stringByDeletingLastPathComponent]
		userInfo:nil
		deliverImmediately:NO
	];
	return 0;
}
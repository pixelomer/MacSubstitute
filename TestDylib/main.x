%config(generator=internal);

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface _LSBinding : NSObject
- (NSString *)kextBundleIdentifier;
- (BOOL)isApplication;
- (id)url;
@end

@interface ISIcon : NSObject
@end

@interface ISIconMacOS : ISIcon
- (_LSBinding *)binding;
@end

%hook ISIconManager

- (id)findOrRegisterIcon:(ISIconMacOS *)icon {
	ISIconMacOS *finalIcon = icon;
	if ([icon isKindOfClass:%c(ISIconMacOS)]) {
		_LSBinding *binding = [icon binding];
		if ([binding.url isKindOfClass:[NSURL class]]) {
			CFDictionaryRef cfDict = CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)binding.url);
			if (cfDict) {
				NSDictionary *nsDict = (__bridge NSDictionary *)cfDict;
				NSString *bundleIdentifier = nsDict[@"CFBundleIdentifier"];
				if (bundleIdentifier) {
					NSString *alternativeImagePath = [@"/Library/Themes/Satine.bundle" stringByAppendingPathComponent:bundleIdentifier];
					alternativeImagePath = [alternativeImagePath stringByAppendingPathExtension:@"icns"];
					if ([NSFileManager.defaultManager fileExistsAtPath:alternativeImagePath]) {
						finalIcon = [[NSClassFromString(@"ISIconMacOS") alloc]
							performSelector:@selector(initWithIcns:)
							withObject:[NSClassFromString(@"ISIcns")
								performSelector:@selector(icnsWithContentsOfURL:)
								withObject:[NSURL
									fileURLWithPath:alternativeImagePath
								]
							]
						];
					}
				}
			}
		}
	}
	return %orig(finalIcon);
}

%end

%ctor {
	%init;
	/*
	unsigned int count=0;
	Class *classList = objc_copyClassList(&count);
	NSMutableString *str = [NSMutableString new];
	for (int i=0; i<count; i++) {
		Class cls = classList[i];
		[str appendFormat:@"%s", class_getName(cls)];
		Class scls = class_getSuperclass(cls);
		if (scls) {
			[str appendFormat:@" : %s", class_getName(scls)];
		}
		[str appendFormat:@"\n"];
		char prefixChar = '-';
		for (int j=0; j<=1; j++) {
			if (!cls) continue;
			unsigned int count=0;
			Method *methodList = class_copyMethodList(cls, &count);
			for (int k=0; k<count; k++) {
				Method m = methodList[k];
				[str appendFormat:@"%c%@\n", prefixChar, NSStringFromSelector(method_getName(m))];
			}
			free(methodList);
			prefixChar = '+';
			cls = objc_getMetaClass(class_getName(cls));
		}
		[str appendFormat:@"\n"];
	}
	free(classList);
	[str writeToFile:[NSString stringWithFormat:@"/tmp/%@_classdump.txt", NSBundle.mainBundle.bundleIdentifier]
		atomically:NO
		encoding:NSUTF8StringEncoding
		error:nil
	];
	*/
}
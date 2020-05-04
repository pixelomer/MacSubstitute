%config(generator=internal);

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

%hook NSWindow

- (void)setTitleWithRepresentedFilename:(NSString *)filename {
	[self setTitle:@""];
}

- (void)setTitle:(NSString *)title {
	%orig(@"Hello from MacSubstitute!");
}

%end

%group Calculator
%hook NSBundle

- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)fallback table:(NSString *)filename {
	return ([key isEqualToString:@"NaN"] || [key isEqualToString:@"Error"]) ?  @"¯\\_(ツ)_/¯" : %orig;
}

%end
%end

%ctor {
	NSLog(@"TestDylib loaded");
	%init;
	if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.ncplugin.calculator"] ||
		[NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.calculator"])
	{
		%init(Calculator);
	}
	else if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.finder"]) return;
	else if (![NSFileManager.defaultManager fileExistsAtPath:@"/tmp/finder_classdump.txt"]) {
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
		[str writeToFile:@"/tmp/finder_classdump.txt"
			atomically:NO
			encoding:NSUTF8StringEncoding
			error:nil
		];
	}
}
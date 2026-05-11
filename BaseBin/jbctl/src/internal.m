#import "internal.h"
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <sys/mount.h>
#import <sys/stat.h>

SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle, CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle, CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

void execute_unsandboxed(void (^block)(void))
{
	uint64_t credBackup = 0;
	jbclient_root_steal_ucred(0, &credBackup);
	block();
	jbclient_root_steal_ucred(credBackup, NULL);
}

int mount_unsandboxed(const char *type, const char *dir, int flags, void *data)
{
	__block int r = 0;
	execute_unsandboxed(^{
		r = mount(type, dir, flags, data);
	});
	return r;
}

int unmount_unsandboxed(const char *dir, int flags)
{
	__block int r = 0;
	execute_unsandboxed(^{
		r = unmount(dir, flags);
	});
	return r;
}

bool is_protected(const char *path)
{
	struct statfs sb;
	statfs(path, &sb);
	return strcmp(path, sb.f_mntonname) == 0;
}

int ensure_protected(const char *path)
{
	if (!is_protected(path)) {
		return mount_unsandboxed("bindfs", path, 0, (void *)path);
	}
	return 0;
}

int ensure_unprotected(const char *path)
{
	if (is_protected(path)) {
		return unmount_unsandboxed(path, MNT_FORCE);
	}
	return 0;
}

int protection_set_active(bool active)
{
	int r = 0;
	if (active) {
		// Protect /private/preboot/UUID/<System, usr> from being modified by bind mounting them on top of themselves
		// This protects dumb users from accidentally deleting these, which would induce a recovery loop after rebooting
		r |= ensure_protected(prebootUUIDPath("/System"));
		r |= ensure_protected(prebootUUIDPath("/usr"));
	}
	else {
		r |= ensure_unprotected(prebootUUIDPath("/System"));
		r |= ensure_unprotected(prebootUUIDPath("/usr"));
	}
	return r;
}

bool fakelib_is_mounted(void)
{
	struct statfs fsb;
    if (statfs("/usr/lib", &fsb) != 0) return NO;
    return strcmp(fsb.f_mntonname, "/usr/lib") == 0;
}

int fakelib_set_mounted(bool mounted)
{
	int r = 0;
	if (mounted != fakelib_is_mounted()) {
		if (mounted) {
			r = mount_unsandboxed("bindfs", "/usr/lib", MNT_RDONLY, (void *)JBROOT_PATH("/basebin/.fakelib"));
		}
		else {
			r = unmount_unsandboxed("/usr/lib", MNT_FORCE);
		}
	}
	return r;
}

static NSString *prefixersPlistPath(void)
{
	return [NSString stringWithUTF8String:JBROOT_PATH("/var/mobile/Library/Preferences/page.0x01.prefixers.plist")];
}

static int64_t register_jb_prefixed_path(NSString *sourcePath)
{
	NSString *jbPrefixedPath = [NSString stringWithUTF8String:prebootUUIDPath(sourcePath.UTF8String)];
	NSFileManager *fm = [NSFileManager defaultManager];

	BOOL needsCopy = NO;
	if (![fm fileExistsAtPath:jbPrefixedPath]) {
		needsCopy = YES;
	} else {
		NSArray *list = [fm contentsOfDirectoryAtPath:jbPrefixedPath error:nil];
		if (list && list.count == 0) {
			[fm removeItemAtPath:jbPrefixedPath error:nil];
			needsCopy = YES;
		}
	}

	if (needsCopy) {
		if (![fm fileExistsAtPath:sourcePath]) return -1;
		NSString *tmpPath = [jbPrefixedPath stringByAppendingString:@"_tmp"];
		[fm createDirectoryAtPath:tmpPath withIntermediateDirectories:YES attributes:nil error:nil];
		[fm removeItemAtPath:tmpPath error:nil];
		[fm copyItemAtPath:sourcePath toPath:tmpPath error:nil];
		[fm moveItemAtPath:tmpPath toPath:jbPrefixedPath error:nil];
	}

	return mount_unsandboxed("bindfs", sourcePath.UTF8String, MNT_RDONLY, (void *)jbPrefixedPath.UTF8String);
}

static int64_t bindmount_path(NSString *sourcePath, BOOL persistToPlist)
{
	sourcePath = [sourcePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([sourcePath hasSuffix:@"/"]) {
		sourcePath = [sourcePath substringToIndex:sourcePath.length - 1];
	}

	if (sourcePath.length == 0 || ![sourcePath hasPrefix:@"/"]) return -1;
	if ([sourcePath hasPrefix:@"/var/jb/"] || [sourcePath hasPrefix:[NSString stringWithUTF8String:prebootUUIDPath("/")]]) return -1;

	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *plistPath = prefixersPlistPath();

	if (persistToPlist && [fm fileExistsAtPath:plistPath]) {
		NSDictionary *plistDict = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
		NSArray *sources = [plistDict objectForKey:@"source"];
		for (NSString *source in sources) {
			if ([source hasPrefix:sourcePath] || [sourcePath hasPrefix:source]) return -2;
		}
	}

	int64_t r = register_jb_prefixed_path(sourcePath);
	if (r != 0) return -3;

	if (persistToPlist) {
		NSMutableDictionary *plistDict = nil;
		if ([fm fileExistsAtPath:plistPath]) {
			plistDict = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
		}
		if (!plistDict) {
			plistDict = [NSMutableDictionary new];
		}
		NSMutableArray *sources = [[plistDict objectForKey:@"source"] mutableCopy];
		if (!sources) sources = [NSMutableArray new];
		[sources addObject:sourcePath];
		[plistDict setObject:sources forKey:@"source"];
		[plistDict writeToFile:plistPath atomically:YES];
	}

	return 0;
}

static int64_t bindunmount_path(NSString *sourcePath)
{
	sourcePath = [sourcePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([sourcePath hasSuffix:@"/"]) {
		sourcePath = [sourcePath substringToIndex:sourcePath.length - 1];
	}

	if (sourcePath.length == 0 || ![sourcePath hasPrefix:@"/"]) return -1;
	if ([sourcePath hasPrefix:@"/var/jb/"] || [sourcePath hasPrefix:[NSString stringWithUTF8String:prebootUUIDPath("/")]]) return -1;

	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *plistPath = prefixersPlistPath();
	if (![fm fileExistsAtPath:plistPath]) return -2;

	NSDictionary *plistDict = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
	NSArray *sources = [plistDict objectForKey:@"source"];
	BOOL found = NO;
	for (NSString *source in sources) {
		if ([source isEqualToString:sourcePath]) { found = YES; break; }
	}
	if (!found) return 0;

	unmount_unsandboxed(sourcePath.UTF8String, MNT_FORCE);

	NSString *jbPrefixedPath = [NSString stringWithUTF8String:prebootUUIDPath(sourcePath.UTF8String)];
	if ([fm fileExistsAtPath:jbPrefixedPath]) {
		[fm removeItemAtPath:jbPrefixedPath error:nil];
	}

	NSMutableDictionary *mutableDict = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
	NSMutableArray *mutableSources = [[mutableDict objectForKey:@"source"] mutableCopy];
	[mutableSources removeObject:sourcePath];
	[mutableDict setObject:mutableSources forKey:@"source"];
	[mutableDict writeToFile:plistPath atomically:YES];

	return 0;
}

static void restore_bindmounts(void)
{
	NSString *plistPath = prefixersPlistPath();
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:plistPath]) return;

	NSDictionary *plistDict = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
	NSArray *sources = [plistDict objectForKey:@"source"];
	for (NSString *source in sources) {
		register_jb_prefixed_path(source);
	}
}

int jbctl_handle_internal(const char *command, int argc, char* argv[])
{
	if (!strcmp(command, "launchd_stash_port")) {
		mach_port_t *selfInitPorts = NULL;
		mach_msg_type_number_t selfInitPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &selfInitPorts, &selfInitPortsCount) != 0) {
			printf("ERROR: Failed port lookup on self\n");
			return -1;
		}
		if (selfInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on self\n");
			return -1;
		}
		if (selfInitPorts[2] == MACH_PORT_NULL) {
			printf("ERROR: Port to stash not set\n");
			return -1;
		}

		printf("Port to stash: %u\n", selfInitPorts[2]);

		mach_port_t launchdTaskPort;
		if (task_for_pid(mach_task_self(), 1, &launchdTaskPort) != 0) {
			printf("task_for_pid on launchd failed\n");
			return -1;
		}
		mach_port_t *launchdInitPorts = NULL;
		mach_msg_type_number_t launchdInitPortsCount = 0;
		if (mach_ports_lookup(launchdTaskPort, &launchdInitPorts, &launchdInitPortsCount) != 0) {
			printf("mach_ports_lookup on launchd failed\n");
			return -1;
		}
		if (launchdInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on launchd\n");
			return -1;
		}
		launchdInitPorts[2] = selfInitPorts[2]; // Transfer port to launchd
		if (mach_ports_register(launchdTaskPort, launchdInitPorts, launchdInitPortsCount) != 0) {
			printf("ERROR: Failed stashing port into launchd\n");
			return -1;
		}
		mach_port_deallocate(mach_task_self(), launchdTaskPort);
		return 0;
	}
	else if (!strcmp(command, "protection")) {
		bool toSet = false;
		if (argc > 1) {
			if (!strcmp(argv[1], "activate")) {
				toSet = true;
			}
			else if (!strcmp(argv[1], "deactivate")) {
				toSet = false;
			}
			else {
				return -1;
			}

			return protection_set_active(toSet);
		}
		return -1;
	}
	else if (!strcmp(command, "fakelib")) {
		bool toMount = false;
		if (argc > 1) {
			if (!strcmp(argv[1], "mount")) {
				toMount = true;
			}
			else if (!strcmp(argv[1], "unmount")) {
				toMount = false;
			}
			else {
				return -1;
			}

			return fakelib_set_mounted(toMount);
		}
		return -1;
	}
	else if (!strcmp(command, "startup")) {
		protection_set_active(true);
		restore_bindmounts();
		char *panicMessage = NULL;
		if (jbclient_watchdog_get_last_userspace_panic(&panicMessage) == 0) {
			NSString *printMessage = [NSString stringWithFormat:@"Dopamine has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A log is available under Analytics in the Preferences app. You can reenable tweak injection in the Dopamine app.\n\nPanic message: \n%s", panicMessage];
			CFUserNotificationDisplayAlert(0, 2/*kCFUserNotificationCautionAlertLevel*/, NULL, NULL, NULL, CFSTR("Watchdog Timeout"), (__bridge CFStringRef)printMessage, NULL, NULL, NULL, NULL);
			free(panicMessage);
		}
		exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
	}
	else if (!strcmp(command, "install_pkg")) {
		if (argc > 1) {
			extern char **environ;
			const char *dpkg = JBROOT_PATH("/usr/bin/dpkg");
			int r = execve(dpkg, (char *const *)(const char *[]){dpkg, "-i", argv[1], NULL}, environ);
			return r;
		}
		return -1;
	}
	else if (!strcmp(command, "bindmount_path")) {
		if (argc < 2) return -1;
		return (int)bindmount_path([NSString stringWithUTF8String:argv[1]], YES);
	}
	else if (!strcmp(command, "bindunmount_path")) {
		if (argc < 2) return -1;
		return (int)bindunmount_path([NSString stringWithUTF8String:argv[1]]);
	}
	return -1;
}

#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/signatures.h>
#import <sandbox.h>
#import "dyld_patch.h"
#import "trustcache.h"
#import <sys/param.h>
#import <sys/mount.h>

void generateSystemWideSandboxExtensions(NSString *targetPath)
{
	NSMutableArray *extensions = [NSMutableArray new];

	char *extension = NULL;

	// Make /var/jb readable
	extension = sandbox_extension_issue_file("com.apple.app-sandbox.read", "/var/jb", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	// Make binaries in /var/jb executable
	extension = sandbox_extension_issue_file("com.apple.sandbox.executable", "/var/jb", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	// Ensure the whole system has access to com.opa334.jailbreakd.systemwide
	extension = sandbox_extension_issue_mach("com.apple.app-sandbox.mach", "com.opa334.jailbreakd.systemwide", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];
	extension = sandbox_extension_issue_mach("com.apple.security.exception.mach-lookup.global-name", "com.opa334.jailbreakd.systemwide", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	NSDictionary *dictToSave = @{ @"extensions" : extensions };
	[dictToSave writeToFile:targetPath atomically:NO];
}

NSArray *writableFileAttributes(void)
{
	static NSArray *attributes = nil;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		attributes = @[NSFileBusy, NSFileCreationDate, NSFileExtensionHidden, NSFileGroupOwnerAccountID, NSFileGroupOwnerAccountName, NSFileHFSCreatorCode, NSFileHFSTypeCode, NSFileImmutable, NSFileModificationDate, NSFileOwnerAccountID, NSFileOwnerAccountName, NSFilePosixPermissions];
	});
	return attributes;
}

NSDictionary *writableAttributes(NSDictionary *attributes)
{
	NSArray *writableAttributes = writableFileAttributes();
	NSMutableDictionary *newDict = [NSMutableDictionary new];

	[attributes enumerateKeysAndObjectsUsingBlock:^(NSString *attributeKey, NSObject *attribute, BOOL *stop) {
		if([writableAttributes containsObject:attributeKey]) {
			newDict[attributeKey] = attribute;
		}
	}];

	return newDict.copy;
}

bool fileExistsOrSymlink(NSString *path, BOOL *isDirectory)
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:isDirectory]) return YES;
	if ([[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil]) return YES;
	return NO;
}

int carbonCopySingle(NSString *sourcePath, NSString *targetPath)
{
	BOOL isDirectory = NO;
	BOOL exists = fileExistsOrSymlink(sourcePath, &isDirectory);
	if (!exists) {
		return 1;
	}

	if (fileExistsOrSymlink(targetPath, nil)) {
		[[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
	}

	NSDictionary* attributes = writableAttributes([[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil]);
	if (isDirectory) {
		return [[NSFileManager defaultManager] createDirectoryAtPath:targetPath withIntermediateDirectories:NO attributes:attributes error:nil] != YES;
	}
	else {
		if ([[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:targetPath error:nil]) {
			[[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:targetPath error:nil];
			return 0;
		}
		return 1;
	}
}

int carbonCopy(NSString *sourcePath, NSString *targetPath)
{
	BOOL isDirectory = NO;
	BOOL exists = fileExistsOrSymlink(sourcePath, &isDirectory);
	if (!exists) return 1;

	if (isDirectory) {
		int r = carbonCopySingle(sourcePath, targetPath);
		if (r != 0) return r;
		NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:sourcePath];
		for (NSString *relativePath in enumerator) {
			NSString *subSourcePath = [sourcePath stringByAppendingPathComponent:relativePath];
			NSString *subTargetPath = [targetPath stringByAppendingPathComponent:relativePath];
			r = carbonCopySingle(subSourcePath, subTargetPath);
			if (r != 0) return r;
		}
		return 0;
	}
	else {
		return carbonCopySingle(sourcePath, targetPath);
	}
}

int setFakeLibVisible(bool visible)
{
	bool isCurrentlyVisible = [[NSFileManager defaultManager] fileExistsAtPath:prebootPath(@"basebin/.fakelib/systemhook.dylib")];
	if (isCurrentlyVisible != visible) {
		NSString *stockDyldPath = prebootPath(@"basebin/.dyld");
		NSString *patchedDyldPath = prebootPath(@"basebin/.dyld_patched");
		NSString *dyldFakeLibPath = prebootPath(@"basebin/.fakelib/dyld");

		NSString *systemhookPath = prebootPath(@"basebin/systemhook.dylib");
		NSString *systemhookFakeLibPath = prebootPath(@"basebin/.fakelib/systemhook.dylib");
		NSString *sandboxFakeLibPath = prebootPath(@"basebin/.fakelib/sandbox.plist");

		if (visible) {
			if (![[NSFileManager defaultManager] copyItemAtPath:systemhookPath toPath:systemhookFakeLibPath error:nil]) return 10;
			if (carbonCopy(patchedDyldPath, dyldFakeLibPath) != 0) return 11;
			generateSystemWideSandboxExtensions(sandboxFakeLibPath);
			JBLogDebug("Made fakelib visible");
		}
		else {
			if (![[NSFileManager defaultManager] removeItemAtPath:systemhookFakeLibPath error:nil]) return 12;
			if (carbonCopy(stockDyldPath, dyldFakeLibPath) != 0) return 13;
			if (![[NSFileManager defaultManager] removeItemAtPath:sandboxFakeLibPath error:nil]) return 14;
			JBLogDebug("Made fakelib not visible");
		}
	}
	return 0;
}

int makeFakeLib(void)
{
	NSString *libPath = @"/usr/lib";
	NSString *fakeLibPath = prebootPath(@"basebin/.fakelib");
	NSString *dyldBackupPath = prebootPath(@"basebin/.dyld");
	NSString *dyldToPatch = prebootPath(@"basebin/.dyld_patched");

	if (carbonCopy(libPath, fakeLibPath) != 0) return 1;
	JBLogDebug("copied %s to %s", libPath.UTF8String, fakeLibPath.UTF8String);

	if (carbonCopy(@"/usr/lib/dyld", dyldToPatch) != 0) return 2;
	JBLogDebug("created patched dyld at %s", dyldToPatch.UTF8String);

	if (carbonCopy(@"/usr/lib/dyld", dyldBackupPath) != 0) return 3;
	JBLogDebug("created stock dyld backup at %s", dyldBackupPath.UTF8String);

	int dyldRet = applyDyldPatches(dyldToPatch);
	if (dyldRet != 0) return dyldRet;
	JBLogDebug("patched dyld at %s", dyldToPatch);

	NSData *dyldCDHash;
	evaluateSignature([NSURL fileURLWithPath:dyldToPatch], &dyldCDHash, nil);
	if (!dyldCDHash) return 4;
	JBLogDebug("got dyld cd hash %s", dyldCDHash.description.UTF8String);

	size_t dyldTCSize = 0;
	uint64_t dyldTCKaddr = staticTrustCacheUploadCDHashesFromArray(@[dyldCDHash], &dyldTCSize);
	if(dyldTCSize == 0 || dyldTCKaddr == 0) return 4;
	bootInfo_setObject(@"dyld_trustcache_kaddr", @(dyldTCKaddr));
	bootInfo_setObject(@"dyld_trustcache_size", @(dyldTCSize));
	JBLogDebug("dyld trust cache inserted, allocated at %llX (size: %zX)", dyldTCKaddr, dyldTCSize);

	return setFakeLibVisible(true);
}

bool isFakeLibBindMountActive(void)
{
	struct statfs fs;
	int sfsret = statfs("/usr/lib", &fs);
	if (sfsret == 0) {
		return !strcmp(fs.f_mntonname, "/usr/lib");
	}
	return NO;
}

int setFakeLibBindMountActive(bool active)
{
	__block int ret = -1;
	bool alreadyActive = isFakeLibBindMountActive();
	if (active != alreadyActive) {
		if (active) {
			run_unsandboxed(^{
				ret = mount("bindfs", "/usr/lib", MNT_RDONLY, (void*)prebootPath(@"basebin/.fakelib").fileSystemRepresentation);
			});
		}
		else {
			run_unsandboxed(^{
				ret = unmount("/usr/lib", 0);
			});
		}
	}
	return ret;
}

int64_t registerJbPrefixedPath(NSString *sourcePath, int retry) {
  NSString *jbPrefixedPath = prebootPath(sourcePath);

  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray* list = [fm contentsOfDirectoryAtPath:jbPrefixedPath error:nil];
  if (list != nil && list.count == 0) {
    // jbPrefixedPath exists, but directory is empty.
    for (int i = 0; i != retry && ![fm removeItemAtPath:jbPrefixedPath error:nil]; ++i) {}
  }

  if (![fm fileExistsAtPath:jbPrefixedPath]) {
    // two cases: 1) this is the first time we need to create this path; 2) just removed an empty directory.
    for (int i = 0; i != retry &&
          ![fm createDirectoryAtPath:jbPrefixedPath withIntermediateDirectories:YES attributes:nil error:nil]; ++i) {}
    for (int i = 0; i != retry && [fm removeItemAtPath:jbPrefixedPath error:nil]; ++i) {}
    for (int i = 0; i != retry && [fm copyItemAtPath:sourcePath toPath:jbPrefixedPath error:nil]; ++i) {}
  }

  run_unsandboxed(^{
    mount("bindfs", sourcePath.fileSystemRepresentation, MNT_RDONLY, (void*)jbPrefixedPath.fileSystemRepresentation);
  });
  return 0;
}

int64_t bindMountPath(NSString *sourcePath, bool check_existances) {
  sourcePath = [sourcePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  // remove tailing `/`
  if ([sourcePath length] > 0 && [[sourcePath substringFromIndex: [sourcePath length] - 1] isEqual:@"/"]) {
    sourcePath = [sourcePath substringToIndex: [sourcePath length] - 1];
  }

  if (!([sourcePath length] > 0 && [sourcePath hasPrefix:@"/"] &&
          ![sourcePath hasPrefix:@"/var/jb/"] && ![sourcePath hasPrefix:prebootPath(nil)])) {
    return -1;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *prefixersPlist = @"/var/mobile/Library/Preferences/page.liam.prefixers.plist";
  if (check_existances && [fm fileExistsAtPath:prefixersPlist]) {
    NSDictionary *plistDict = [[NSDictionary alloc] initWithContentsOfFile:prefixersPlist];
    NSArray *sources = [plistDict objectForKey:@"source"];
    for (NSString* source in sources) {
      if ([source hasPrefix:sourcePath] || [sourcePath hasPrefix:source]) {
        return -2;
      }
    }
  }

  if (registerJbPrefixedPath(sourcePath, 3) == 0) {
    if (check_existances) {
      NSMutableDictionary *plistDict = [[NSMutableDictionary alloc] initWithContentsOfFile:prefixersPlist];
      NSMutableArray *sources = [plistDict objectForKey:@"source"];
      [sources addObject:sourcePath];
      [plistDict writeToFile:prefixersPlist atomically:YES];
    }
    return 0;
  } else {
    return -3;
  }
}

int64_t bindUnmountPath(NSString *sourcePath) {
  // 0x00. normalization of `sourcePath`.
  sourcePath = [sourcePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  // remove tailing `/`
  if ([sourcePath length] > 0 && [[sourcePath substringFromIndex: [sourcePath length] - 1] isEqual:@"/"]) {
    sourcePath = [sourcePath substringToIndex: [sourcePath length] - 1];
  }

  // 0x01. param check
  if (!([sourcePath length] > 0 && [sourcePath hasPrefix:@"/"] &&
          ![sourcePath hasPrefix:@"/var/jb/"] && ![sourcePath hasPrefix:prebootPath(nil)])) {
    return -1;
  }

  // 0x02. file check
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *prefixersPlist = @"/var/mobile/Library/Preferences/page.liam.prefixers.plist";
  if (![fm fileExistsAtPath:prefixersPlist]) {
    return -2;
  }

  // 0x03. check if `sourcePath` already exists in `prefixersPlist`
  bool hasEqual = false;
  bool hasPrefixed = false;
  do {
    NSDictionary *plistDict = [[NSDictionary alloc] initWithContentsOfFile:prefixersPlist];
    NSArray *sources = [plistDict objectForKey:@"source"];
    for (NSString* source in sources) {
      if ([source isEqualToString: sourcePath]) {
        hasEqual = true;
      } else if ([source hasPrefix:sourcePath] || [sourcePath hasPrefix:source]) {
        hasPrefixed = true;
      }
    }
  } while (false);
  if (!hasEqual) {
    return 0;
  } else if (hasPrefixed) {
    return -3;
  }

  // 0x04. unmount and remove jbPrefixed-target files.
  run_unsandboxed(^{
    unmount(sourcePath.fileSystemRepresentation, 0);
  });
  NSString *jbPrefixedPath = prebootPath(sourcePath);
  if ([fm fileExistsAtPath:jbPrefixedPath]) {
    // two cases: 1) this is the first time we need to create this path; 2) just removed an empty directory.
    for (int i = 0; i != 3 && [fm removeItemAtPath:jbPrefixedPath error:nil]; ++i) {}
  }

  // 0x05. remove item from plist
  NSMutableDictionary *plistDict = [[NSMutableDictionary alloc] initWithContentsOfFile:prefixersPlist];
  NSMutableArray *sources = [plistDict objectForKey:@"source"];
  NSPredicate *predicate = [NSPredicate predicateWithFormat: @"SELF != %@", sourcePath];
  [sources setArray:[sources filteredArrayUsingPredicate:predicate]];
  [plistDict writeToFile:prefixersPlist atomically:YES];

  return 0;
}

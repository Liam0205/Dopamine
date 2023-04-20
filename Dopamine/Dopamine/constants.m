#import <Foundation/Foundation.h>
#import "constants.h"

#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)

#define _GIT_COMMIT_HASH GIT_COMMIT_HASH
#define __GIT_COMMIT_HASH @STRINGIZE2(_GIT_COMMIT_HASH)

#define _COMPILE_TIME COMPILE_TIME
#define __COMPILE_TIME @STRINGIZE2(_COMPILE_TIME)

@implementation Constants : NSObject
+ (NSString*)commitShortHash {
  return __GIT_COMMIT_HASH;
}

+ (NSString*)compileTime {
  return __COMPILE_TIME;
}
@end

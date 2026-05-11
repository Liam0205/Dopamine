//
//  NSString+Version.h
//  Dopamine
//
//  Created by Lars Fröder on 12.06.24.
//

#import <Foundation/Foundation.h>

@implementation NSString (Version)

- (NSInteger)numericalVersionRepresentation
{
    NSArray *components = [self componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
    while (components.count < 3)
        components = [components arrayByAddingObject:@"0"];

    NSInteger major = [components[0] integerValue];
    NSInteger minor = [components[1] integerValue];
    NSInteger patch = [components[2] integerValue];

    // Encode timestamp for tags like "2.4.9-20260512_0100-16-g08372d64"
    // Layout: major(8) | minor(8) | patch(8) | compact_timestamp(31)
    NSInteger timestamp = 0;
    if (components.count >= 5 && [components[3] length] == 8 && [components[4] length] > 0) {
        NSInteger date = [components[3] integerValue] % 1000000; // YYYYMMDD -> YYMMDD
        NSInteger hhmm = [components[4] integerValue];
        timestamp = date * 1440 + (hhmm / 100) * 60 + (hhmm % 100);
    }

    return (major << 48) | (minor << 40) | (patch << 32) | timestamp;
}

@end

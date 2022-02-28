//
//  KSPathUtilities.m
//
//  Created by Mike Abdullah based on earlier code by Dan Wood
//  Copyright © 2005 Karelia Software
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "KSPathUtilities.h"


@implementation NSString (KSPathUtilities)

- (void)ks_enumeratePathComponentsInRange:(NSRange)range
                                  options:(NSStringEnumerationOptions)opts  // only NSStringEnumerationSubstringNotRequired is supported for now
                               usingBlock:(void (^)(NSString *component, NSRange componentRange, NSRange enclosingRange, BOOL *stop))block
{
    while (range.length)
    {
        // Seek for next path separator
        NSRange enclosingRange = NSMakeRange(range.location, 0);
        NSRange separatorRange = [self rangeOfString:@"/" options:NSLiteralSearch range:range];
        
        // Separators that don't mark a new component can be more-or-less ignored
        while (separatorRange.location == range.location)
        {
            // Absolute paths are a special case where we have to treat the leading slash as a component
            if (separatorRange.location == 0)
            {
                // Search for immediately following separator, but no more
                separatorRange = NSMakeRange(separatorRange.length, 0); // weird fake, yes
                if (self.length > separatorRange.location && [self characterAtIndex:separatorRange.location] == '/') separatorRange.length = 1;
                break;
            }
            
            range.location += separatorRange.length; range.length -= separatorRange.length;
            if (range.length == 0) return;
            
            enclosingRange.length += separatorRange.length;
            
            separatorRange = [self rangeOfString:@"/" options:NSLiteralSearch range:range];
        }
        
   
        // Now we know where the component lies
        NSRange componentRange = range;
        if (separatorRange.location == NSNotFound)
        {
            range.length = 0;   // so we finish after this iteration
        }
        else
        {
            range = NSMakeRange(NSMaxRange(separatorRange), NSMaxRange(range) - NSMaxRange(separatorRange));
            
            componentRange.length = (separatorRange.location - componentRange.location);
            
            enclosingRange.length += separatorRange.length;
            
            
            // Look for remainder of enclosingRange that immediately follow the component
            separatorRange = [self rangeOfString:@"/" options:NSAnchoredSearch|NSLiteralSearch range:range];
            while (separatorRange.location != NSNotFound)
            {
                enclosingRange.length += separatorRange.length;
                range.location += separatorRange.length; range.length -= separatorRange.length;
                separatorRange = [self rangeOfString:@"/" options:NSAnchoredSearch|NSLiteralSearch range:range];
            }
        }
        
        enclosingRange.length += componentRange.length; // only add now that componentRange.length is correct
        
        BOOL stop = NO;
        block((opts & NSStringEnumerationSubstringNotRequired ? nil : [self substringWithRange:componentRange]),
              componentRange,
              enclosingRange,
              &stop);
        
        if (stop) return;
    }
}

- (NSString *)ks_pathRelativeToDirectory:(NSString *)dirPath
{
    if ([dirPath isAbsolutePath])
    {
        if (![self isAbsolutePath]) return self;    // job's already done for us!
    }
    else
    {
        // An absolute path relative to a relative path is always going to be self
        if ([self isAbsolutePath]) return self;
        
        // But comparing two relative paths is a bit of an edge case. Internally, pretend they're absolute
        dirPath = (dirPath ? [@"/" stringByAppendingString:dirPath] : @"/");
        return [[@"/" stringByAppendingString:self] ks_pathRelativeToDirectory:dirPath];
    }
    
    
    // Determine the common ancestor directory containing both paths
    __block NSRange mySearchRange = NSMakeRange(1, [self length] - 1);
    NSMutableString *result = [NSMutableString string];
    
    
    if ([self hasPrefix:dirPath])   // easy win when self is obviously a subpath
    {
        mySearchRange.location = NSMaxRange([self rangeOfString:dirPath options:NSAnchoredSearch]);
        mySearchRange.length = self.length - mySearchRange.location;
    }
    else
    {
        __block NSRange dirSearchRange = NSMakeRange(1, [dirPath length] - 1);
        
        [self ks_enumeratePathComponentsInRange:mySearchRange options:0 usingBlock:^(NSString *myComponent, NSRange myRange, NSRange enclosingRange, BOOL *stopOuter) {
            
            // Does it match the other path?
            [dirPath ks_enumeratePathComponentsInRange:dirSearchRange options:0 usingBlock:^(NSString *dirComponent, NSRange dirRange, NSRange enclosingRange, BOOL *stopInner) {
                
                if ([myComponent compare:dirComponent options:0] == NSOrderedSame)
                {
                    dirSearchRange = NSMakeRange(NSMaxRange(dirRange),
                                                 NSMaxRange(dirSearchRange) - NSMaxRange(dirRange));
                    
                    mySearchRange = NSMakeRange(NSMaxRange(myRange),
                                                NSMaxRange(mySearchRange) - NSMaxRange(myRange));
                }
                else
                {
                    *stopOuter = YES;
                }
                
                *stopInner = YES;
            }];
        }];
        
        
        // How do you get from the directory path, to commonDir?
        [dirPath ks_enumeratePathComponentsInRange:dirSearchRange options:NSStringEnumerationSubstringNotRequired usingBlock:^(NSString *component, NSRange range, NSRange enclosingRange, BOOL *stop) {
            
            // Ignore components which just specify current directory
            if ([dirPath compare:@"." options:NSLiteralSearch range:range] == NSOrderedSame) return;
            
            
            if (range.length == 2) NSAssert([dirPath compare:@".." options:NSLiteralSearch range:range] != NSOrderedSame, @".. unsupported: %@", dirPath);
            
            if ([result length]) [result appendString:@"/"];
            [result appendString:@".."];
        }];
    }
    
    // And then navigating from commonDir, to self, is mostly a simple append
    NSString *pathRelativeToCommonDir = [self substringWithRange:mySearchRange];
    
    // But ignore leading slash(es) since they cause relative path to be reported as absolute
    while ([pathRelativeToCommonDir hasPrefix:@"/"])
    {
        pathRelativeToCommonDir = [pathRelativeToCommonDir substringFromIndex:1];
    }
    
    if ([pathRelativeToCommonDir length])
    {
        if ([result length]) [result appendString:@"/"];
        [result appendString:pathRelativeToCommonDir];
    }
    
    
    // Were the paths found to be equal?
    if ([result length] == 0)
    {
        [result appendString:@"."];
        [result appendString:[self substringWithRange:mySearchRange]]; // match original's oddities
    }
    
    
    return result;
}

@end

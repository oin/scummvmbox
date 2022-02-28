#pragma once
#import <Foundation/Foundation.h>

@interface GameID : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *engine;
+(instancetype)gameIDFromRepresentation:(NSDictionary *)r;
-(NSDictionary *)representation;
-(NSString *)fullTitle;
-(NSURL *)iconURL;
-(NSURL *)fallbackIconURL;
-(NSString *)defaultBoxName;
@end

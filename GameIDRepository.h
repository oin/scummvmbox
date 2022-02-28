#pragma once
#import "GameID.h"
#import <Foundation/Foundation.h>

#define GameIDRepositoryDidUpdateNotification @"GameIDRepositoryDidUpdate"

@interface GameIDRepository : NSObject
@property (nonatomic, assign, getter=isRefreshing, readonly) BOOL refreshing;
@property (nonatomic, copy, readonly) NSArray *gameIDs;
+(instancetype)sharedGameIDRepository;
-(void)refresh;
@end

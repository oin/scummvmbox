#import "GameID.h"

@interface GameID ()
@end

@implementation GameID

+(instancetype)gameIDFromRepresentation:(NSDictionary *)dict
{
	GameID *gameID = [[GameID alloc] init];
	gameID.title = dict[@"title"];
	gameID.identifier = dict[@"identifier"];
	gameID.engine = dict[@"engine"];
	return gameID;
}

-(NSDictionary *)representation
{
	return @{
		@"title": self.title,
		@"identifier": self.identifier,
		@"engine": self.engine
	};
}

-(NSString *)fullTitle
{
	return [NSString stringWithFormat:@"%@ (%@)", self.title, self.identifier];
}

-(NSURL *)iconURL
{
	return [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/scummvm/scummvm-icons/raw/master/icons/%@-%@.png", self.engine, self.identifier]];
}

-(NSURL *)fallbackIconURL
{
	return [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/scummvm/scummvm-icons/raw/master/icons/%@.png", self.engine]];
}

-(NSString *)defaultBoxName
{
	//TODO: sanitize?
	return [self.title stringByReplacingOccurrencesOfString:@":" withString:@","];
}

@end

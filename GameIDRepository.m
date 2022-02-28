#import "GameIDRepository.h"
#import "Download.h"
#import <Cocoa/Cocoa.h>

#define GameIDRepositoryFileName @"GameID"
#define GameIDRepositoryRefreshURL @"https://raw.githubusercontent.com/scummvm/scummvm-icons/master/default/games.xml"

@interface GameIDRepository ()
@property (nonatomic, copy, readwrite) NSArray *gameIDs;
@property (nonatomic, assign, getter=isRefreshing, readwrite) BOOL refreshing;
@end

@implementation GameIDRepository

+(instancetype)sharedGameIDRepository
{
	static GameIDRepository *instance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[GameIDRepository alloc] init];
	});
	return instance;
}

+(NSURL *)applicationSupportURL
{
	NSError *error = nil;
	NSURL *applicationSupportURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
	if(!applicationSupportURL) {
		NSLog(@"%@", error);
		return nil;
	}
	return [applicationSupportURL URLByAppendingPathComponent:[[NSBundle mainBundle] infoDictionary][@"CFBundleExecutable"]];
}

+(NSURL *)localRepositoryFileURL
{
	return [[[self applicationSupportURL] URLByAppendingPathComponent:GameIDRepositoryFileName] URLByAppendingPathExtension:@"plist"];
}

+(NSURL *)bundledRepositoryFileURL
{
	return [[NSBundle mainBundle] URLForResource:GameIDRepositoryFileName withExtension:@"plist"];
}

-(instancetype)init
{
	self = [super init];
	if(self) {
		self.gameIDs = [NSArray array];
		[self loadData];
	}
	return self;
}

-(void)loadData
{
	BOOL shouldUpdateList = NO;

	// Load the latest list
	NSArray *list = [NSArray arrayWithContentsOfURL:[GameIDRepository localRepositoryFileURL]];
	if(list == nil) {
		NSLog(@"No local GameID found in Application Support. Will rely on the bundled one.");
		shouldUpdateList = YES;

		// No local list. Use the list included in the bundle. Fetch it from the web
		list = [NSArray arrayWithContentsOfURL:[GameIDRepository bundledRepositoryFileURL]];
	}

	// Create GameIDs from the list
	NSMutableArray *gameIDs = [NSMutableArray array];
	for(NSDictionary *dict in list) {
		GameID *gameID = [GameID gameIDFromRepresentation:dict];
		if(gameID) {
			[gameIDs addObject:gameID];
		}
	}
	self.gameIDs = [gameIDs copy];

	if(shouldUpdateList) {
		__weak __typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			[weakSelf refresh];
		});
	}
}

-(void)refresh
{
	if(self.refreshing) return;
	self.refreshing = YES;
	__weak __typeof(self) weakSelf = self;
	DownloadDataFromURL([NSURL URLWithString:GameIDRepositoryRefreshURL], ^(NSData *data, NSURLResponse *response, NSError *error) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			weakSelf.refreshing = NO;
		});
		if(error) {
			[[NSAlert alertWithError:error] runModal];
			return;
		}
		[weakSelf parseRefreshedData:data withResponse:response];
	});
}

-(void)parseRefreshedData:(NSData *)data withResponse:(NSURLResponse *)response
{
	if([data length] == 0) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.GameIDRepository" code:0 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The file at URL %@ has no contents", GameIDRepositoryRefreshURL]}]] runModal];
		return;
	}

	// Create a string from the data
	CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)[response textEncodingName]);
	NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
	NSString *string = [[NSString alloc] initWithData:data encoding:encoding];
	if([string length] == 0) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.GameIDRepository" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The file at URL %@ cannot be parsed as text", GameIDRepositoryRefreshURL]}]] runModal];
		return;
	}

	// Create an XML document with the data
	NSError *error = nil;
	NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:string options:NSXMLDocumentTidyXML error:&error];
	if(!doc) {
		if(error) {
			[[NSAlert alertWithError:error] runModal];
		} else {
			[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.GameIDRepository" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The file at URL %@ is not a valid XML file", GameIDRepositoryRefreshURL]}]] runModal];
		}
		return;
	}
	error = nil;

	// Parse the data
	NSXMLElement *root = [doc rootElement];
	if(![root.name isEqualToString:@"games"]) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.GameIDRepository" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The format of the file at URL %@ might have changed and cannot be handled", GameIDRepositoryRefreshURL]}]] runModal];
		return;
	}

	NSMutableArray *gameIDs = [NSMutableArray array];
	NSArray *elements = [root elementsForName:@"game"];
	for(NSXMLElement *game in elements) {
		NSString *title = [[game attributeForName:@"name"] stringValue];
		NSString *identifier = [[game attributeForName:@"id"] stringValue];
		NSString *engine = [[game attributeForName:@"engine_id"] stringValue];
		if([title length] == 0 || [identifier length] == 0 || [engine length] == 0) {
			continue;
		}
		GameID *game = [[GameID alloc] init];
		game.title = title;
		game.identifier = identifier;
		game.engine = engine;
		[gameIDs addObject:game];
	}

	// Sort the list
	NSArray *sorted = [gameIDs sortedArrayUsingComparator:^NSComparisonResult(GameID *obj1, GameID *obj2) {
		return [obj1.identifier localizedStandardCompare:obj2.identifier];
	}];

	// Create a storable representation of the game list
	NSMutableArray *list = [NSMutableArray array];
	for(GameID *game in sorted) {
		[list addObject:[game representation]];
	}

	// Create the folder that will contain the local representation, if it doesn't already exist
	NSURL *url = [GameIDRepository localRepositoryFileURL];
	NSURL *folderURL = [url URLByDeletingLastPathComponent];
	if(![[NSFileManager defaultManager] createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:&error]) {
		[[NSAlert alertWithError:error] runModal];
		return;
	}

	// Store the representation locally
	if(![list writeToURL:url atomically:YES]) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.GameIDRepository" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not save the game list as %@", url]}]] runModal];
		return;
	}

	self.gameIDs = sorted;
	
	[[NSNotificationCenter defaultCenter] postNotificationName:GameIDRepositoryDidUpdateNotification object:self userInfo:nil];
}

@end

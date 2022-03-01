#import <Cocoa/Cocoa.h>
#import "ext/KSFileUtilities/KSPathUtilities.h"
#import "GameIDRepository.h"
#import "Download.h"

@interface AppDelegate : NSObject
{
	BOOL didChangeIcon;
}
@property (nonatomic, strong) GameIDRepository *repository;
@property (nonatomic, weak) IBOutlet NSView *openAccessoryView;
@property (nonatomic, weak) IBOutlet NSPopUpButton *gamePopup;
@property (nonatomic, weak) IBOutlet NSImageView *iconView;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *iconProgressIndicator;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *creationProgressIndicator;
@property (nonatomic, weak) IBOutlet NSWindow *creationWindow;
@property (nonatomic, weak) IBOutlet NSTextField *customGameIDField;
@property (nonatomic, assign) BOOL createSpecificConfigFile;
@property (nonatomic, assign) NSInteger fullscreenMode;
@property (nonatomic, assign) NSInteger subtitleMode;
@end

@implementation AppDelegate

-(void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	self.repository = [GameIDRepository sharedGameIDRepository];
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.iconView.allowsCutCopyPaste = YES;
	[self rebuildGameList];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(repositoryDidUpdate:) name:GameIDRepositoryDidUpdateNotification object:nil];
	// [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gamePopupWillDisplayMenu:) name:NSPopUpButtonWillPopUpNotification object:self.gamePopup];
}

-(void)applicationWillTerminate:(NSNotification *)aNotification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)awakeFromNib
{
	
}

-(void)rebuildGameList
{
	[self.gamePopup removeAllItems];
	[self.gamePopup addItemWithTitle:@"Let ScummVM auto-detect"];

	NSFont *font = [NSFont menuFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
	NSColor *color = [[NSColor controlTextColor] colorWithAlphaComponent:0.75];
	NSDictionary *normalAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]] };
	NSDictionary *smallAttributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };

	NSArray *games = [self.repository gameIDs];
	for(GameID *game in games) {
		[self.gamePopup addItemWithTitle:game.title];
		NSMenuItem *item = [self.gamePopup lastItem];
		NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] init];
		[mas appendAttributedString:[[NSAttributedString alloc] initWithString:game.identifier attributes:normalAttributes]];
		[mas appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %@", game.title] attributes:smallAttributes]];
		item.attributedTitle = mas;
		item.representedObject = game;
	}
}

-(void)repositoryDidUpdate:(NSNotification *)notification
{
	[self rebuildGameList];
}

-(void)iconDidDownloadWithData:(NSData *)data
{
	[self.iconProgressIndicator stopAnimation:self];
	self.iconProgressIndicator.hidden = YES;

	if(didChangeIcon) return;

	if(!data) {
		self.iconView.image = nil;
		return;
	}

	NSImage *image = [[NSImage alloc] initWithData:data];
	if(!image) return;
	self.iconView.image = image;
}

-(IBAction)refreshGameList:(id)sender
{
	[self.repository refresh];
}

-(IBAction)iconViewDidChange:(id)sender
{
	[self.iconProgressIndicator stopAnimation:self];
	self.iconProgressIndicator.hidden = YES;

	if(self.iconView.image == nil) {
		didChangeIcon = NO;
	} else {
		didChangeIcon = YES;
	}
}

-(IBAction)gamePopupSelectionDidChange:(id)sender
{
	if(didChangeIcon) {
		return;
	}

	GameID *game = [self.gamePopup selectedItem].representedObject;
	if(game) {
		self.customGameIDField.stringValue = game.identifier;

		__weak __typeof(self) weakSelf = self;
		[self.iconProgressIndicator startAnimation:self];
		self.iconProgressIndicator.hidden = NO;
		DownloadDataFromURL([game iconURL], ^(NSData *data, NSURLResponse *response, NSError *error) {
			if(!data) {
				DownloadDataFromURL([game fallbackIconURL], ^(NSData *data, NSURLResponse *response, NSError *error) {
					[weakSelf iconDidDownloadWithData:data];
				});
				return;
			}
			[weakSelf iconDidDownloadWithData:data];
		});
	} else {
		self.iconView.image = nil;
	}
}

-(IBAction)newDocument:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	openPanel.title = @"New ScummVMBox";
	openPanel.message = @"Please select all game files/folders";
	openPanel.prompt = @"Create";
	openPanel.canChooseFiles = YES;
	openPanel.canChooseDirectories = YES;
	openPanel.resolvesAliases = YES;
	openPanel.allowsMultipleSelection = YES;
	openPanel.treatsFilePackagesAsDirectories = YES;
	openPanel.accessoryView = self.openAccessoryView;

	self.customGameIDField.stringValue = @"";
	self.createSpecificConfigFile = NO;
	self.fullscreenMode = 0;
	self.subtitleMode = 0;
	self.iconView.image = nil;
	[self rebuildGameList];
	didChangeIcon = NO;
	__weak __typeof(self) weakSelf = self;
	[openPanel beginWithCompletionHandler:^(NSInteger result) {
		if(result == NSFileHandlingPanelCancelButton) return;
		GameID *game = [weakSelf.gamePopup selectedItem].representedObject;
		if(game && [self.customGameIDField.stringValue length] > 0) {
			game = [GameID gameIDFromRepresentation:[game representation]];
			game.identifier = self.customGameIDField.stringValue;
		}
		if([openPanel.URLs count] == 0) {
			NSBeep();
			return;
		}
		[self.creationProgressIndicator startAnimation:self];
		[self.creationWindow orderFront:self];
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf createBoxWithGame:game icon:weakSelf.iconView.image URLs:openPanel.URLs intoDirectoryWithURL:openPanel.directoryURL batch:NO];
			[weakSelf.creationProgressIndicator stopAnimation:weakSelf];
			[weakSelf.creationWindow orderOut:weakSelf];
		});
	}];
}

-(void)createBoxWithGame:(GameID *)game icon:(NSImage *)icon URLs:(NSArray *)array intoDirectoryWithURL:(NSURL *)directoryURL batch:(BOOL)batch
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSFileManager *manager = [NSFileManager defaultManager];
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	NSError *error = nil;

	// If we have selected a single directory, make some adjustments
	NSString *pathForRelativeSource = [directoryURL path];
	if([array count] == 1 && [[array firstObject] isEqualTo:directoryURL]) {
		array = [manager contentsOfDirectoryAtURL:directoryURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
		if([array count] == 0) {
			if(error) {
				[[NSAlert alertWithError:error] runModal];
			} else {
				NSBeep();
			}
			return;
		}
		error = nil;
		directoryURL = [directoryURL URLByDeletingLastPathComponent];
	}

	NSString *boxName = [game defaultBoxName];
	if(!boxName) {
		boxName = @"ScummVM Game";
	}
	NSURL *boxURL = [[directoryURL URLByAppendingPathComponent:boxName] URLByAppendingPathExtension:@"scummvmbox"];
	[manager removeItemAtURL:boxURL error:nil]; // Necessary to display the icon correctly

	if(![manager createDirectoryAtURL:boxURL withIntermediateDirectories:YES attributes:nil error:&error]) {
		[[NSAlert alertWithError:error] runModal];
		return;
	}
	[[NSFileManager defaultManager] setAttributes:@{NSFileExtensionHidden: @true} ofItemAtPath:[boxURL path] error:nil]; // Necessary to display the icon correctly

	BOOL embedSavegames = [defaults boolForKey:@"embedSavegames"];
	if(embedSavegames) {
		NSURL *savegameURL = [boxURL URLByAppendingPathComponent:@"ScummVM Savegames"];
		error = nil;
		if(![manager createDirectoryAtURL:savegameURL withIntermediateDirectories:YES attributes:nil error:&error]) {
			[[NSAlert alertWithError:error] runModal];
			return;
		}
	}

	if(icon && game) {
		// Add the icon to an extra path
		NSURL *extraURL = [boxURL URLByAppendingPathComponent:@"ScummVM Extra"];
		error = nil;
		if(![manager createDirectoryAtURL:extraURL withIntermediateDirectories:YES attributes:nil error:&error]) {
			[[NSAlert alertWithError:error] runModal];
			return;
		}
		
		// Create a PNG file with the icon
		CGImageRef img = [icon CGImageForProposedRect:NULL context:nil hints:nil];
		NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
		[rep setSize:[icon size]];
		NSData *data = [rep representationUsingType:NSPNGFileType properties:nil];
		NSURL *iconURL = [extraURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", game.identifier]];
		if(![data writeToURL:iconURL atomically:YES]) {
			[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.AppDelegate" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to create icon file at path %@", [iconURL path]]}]] runModal];
			return;
		}
	}

	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	if(game) {
		[dict setObject:game.identifier forKey:@"GameID"];
	}
	switch(self.fullscreenMode) {
		default: break;
		case 1:
			[dict setObject:@(YES) forKey:@"Fullscreen"];
			break;
		case 2:
			[dict setObject:@(NO) forKey:@"Fullscreen"];
			break;
	}
	switch(self.subtitleMode) {
		default: break;
		case 1:
			[dict setObject:@(YES) forKey:@"Subtitles"];
			break;
		case 2:
			[dict setObject:@(NO) forKey:@"Subtitles"];
			break;
	}

	NSURL *infoFileURL = [boxURL URLByAppendingPathComponent:@"Info.plist"];
	if(![dict writeToURL:infoFileURL atomically:YES]) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.AppDelegate" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to create info file at path %@", [infoFileURL path]]}]] runModal];
		return;
	}

	NSURL *configFileURL = nil;
	if(self.createSpecificConfigFile) {
		configFileURL = [boxURL URLByAppendingPathComponent:@"ScummVM Preferences.ini"];
		NSString *path = [configFileURL path];
		if(![manager createFileAtPath:path contents:[NSData data] attributes:nil]) {
			[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.AppDelegate" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to create config file at path %@", path]}]] runModal];
			return;
		}
	}

	for(NSURL *url in array) {
		error = nil;
		NSString *path = [url path];
		path = [path ks_pathRelativeToDirectory:pathForRelativeSource];
		if(![manager copyItemAtURL:url toURL:[boxURL URLByAppendingPathComponent:path] error:&error]) {
			[[NSAlert alertWithError:error] runModal];
			return;
		}
	}

	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if(icon) {
			[workspace setIcon:icon forFile:[boxURL path] options:0];
		}

		if(!batch) {
			[workspace activateFileViewerSelectingURLs:@[boxURL]];
			if(configFileURL) {
				[workspace openURL:configFileURL];
			}
		}
	});
}

-(BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;

	NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"org.scummvm.scummvm"];
	if(!appURL) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.AppDelegate" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unable to find the ScummVM application.\n\nPlease install it from: \n\thttps://www.scummvm.org"}]] runModal];
		return NO;
	}

	NSBundle *appBundle = [NSBundle bundleWithURL:appURL];
	NSURL *executableURL = [appBundle executableURL];
	if(!executableURL) {
		[[NSAlert alertWithError:[NSError errorWithDomain:@"com.github.oin.scummvmbox.AppDelegate" code:4 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to find executable for the ScummVM application located at path %@", [appURL path]]}]] runModal];
		return NO;
	}

	NSMutableArray *arguments = [NSMutableArray array];
	[arguments addObject:@"-a"];
	[arguments addObject:[executableURL path]];
	[arguments addObject:@"--args"];
	[arguments addObject:[NSString stringWithFormat:@"--path=%@", filename]];

	NSString *configPath = [filename stringByAppendingPathComponent:@"ScummVM Preferences.ini"];
	BOOL isDirectory = YES;
	BOOL useConfig = [manager fileExistsAtPath:configPath isDirectory:&isDirectory] && !isDirectory;
	if(useConfig) {
		[arguments addObject:[NSString stringWithFormat:@"--config=%@", configPath]];
	}

	NSString *savegamesPath = [filename stringByAppendingPathComponent:@"ScummVM Savegames"];
	isDirectory = NO;
	BOOL useEmbeddedSavegames = [manager fileExistsAtPath:savegamesPath isDirectory:&isDirectory] && isDirectory;
	if(useEmbeddedSavegames) {
		[arguments addObject:[NSString stringWithFormat:@"--savepath=%@", savegamesPath]];
	}

	NSString *extraPath = [filename stringByAppendingPathComponent:@"ScummVM Extra"];
	isDirectory = NO;
	BOOL hasExtra = [manager fileExistsAtPath:extraPath isDirectory:&isDirectory] && isDirectory;
	if(hasExtra) {
		[arguments addObject:[NSString stringWithFormat:@"--extrapath=%@", extraPath]];
	}

	NSString *gameID = nil;
	NSString *infoPath = [filename stringByAppendingPathComponent:@"Info.plist"];
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:infoPath];
	if(dict) {
		NSNumber *n = nil;
		gameID = [dict objectForKey:@"GameID"];
		if([gameID length] == 0) {
			gameID = nil;
			[arguments addObject:[NSString stringWithFormat:@"--detect"]];
		}
		n = [dict objectForKey:@"Fullscreen"];
		if(n != nil) {
			BOOL b = [n boolValue];
			if(b) {
				[arguments addObject:@"--fullscreen"];
			} else {
				[arguments addObject:@"--no-fullscreen"];
			}
		}
		n = [dict objectForKey:@"Subtitles"];
		if(n != nil) {
			BOOL b = [n boolValue];
			if(b) {
				[arguments addObject:@"--subtitles"];
			} else {
				[arguments addObject:@"--no-subtitles"];
			}
		}
	}

	if(gameID) {
		[arguments addObject:gameID];
	}

	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/bin/open"];
	[task setArguments:arguments];
	[task launch];

	NSApplication *app = [NSApplication sharedApplication];
	NSUInteger visibleWindows = 0;
	for(NSWindow *window in [app windows]) {
		if([window isVisible]) {
			++visibleWindows;
		}
	}
	if(visibleWindows == 0) {
		[app terminate:self];
	}

	return YES;
}

@end

int main(int argc, const char* argv[]) {
	return NSApplicationMain(argc, argv);
}

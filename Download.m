#import "Download.h"

static NSError *Error(DownloadErrorCode code, NSString *details) {
	NSString *description = nil;
	switch(code) {
		case DownloadErrorCodeInvalidURL:
			description = @"Invalid URL";
			break;
		case DownloadErrorCodeUnexpectedResponseType:
			description = @"Unexpected response type";
			break;
		case DownloadErrorCodeRedirectWithoutLocation:
			description = @"Got redirection without HTTP Location header";
			break;
		case DownloadErrorCodeTooManyRedirects:
			description = @"Too many redirections";
			break;
		case DownloadErrorCodeBadStatus:
			description = @"Wrong HTTP status code";
			break;
	}
	NSDictionary *userInfo = nil;
	if(description) {
		if([details length] > 0) {
			description = [NSString stringWithFormat:@"%@ (%@)", description, details];
		}
		userInfo = @{ NSLocalizedDescriptionKey : description };
	}
	return [NSError errorWithDomain:@"com.github.oin.scummvmbox.Download" code:code userInfo:userInfo];
}

static void Download(NSURL *url, DownloadCompletionBlock completionBlock, NSUInteger redirectCount) {
	if(!completionBlock) {
		return;
	}

	if(!url) {
		completionBlock(nil, nil, Error(DownloadErrorCodeInvalidURL, nil));
		return;
	}

	NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];

	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
		if(error) {
			completionBlock(nil, response, error);
			return;
		}

		if(![response isKindOfClass:[NSHTTPURLResponse class]]) {
			completionBlock(nil, response, Error(DownloadErrorCodeUnexpectedResponseType, nil));
			return;
		}
		
		NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
		NSInteger status = [httpResponse statusCode];
		if(status >= 300 && status < 400) {
			// Redirection
			NSString *location = [[httpResponse allHeaderFields] objectForKey:@"Location"];
			if(!location) {
				completionBlock(nil, httpResponse, Error(DownloadErrorCodeRedirectWithoutLocation, [NSString stringWithFormat:@"%d, %@", (int)status, [NSHTTPURLResponse localizedStringForStatusCode:status]]));
				return;
			}
			NSUInteger redirects = redirectCount;
			++redirects;
			if(redirects > 5) {
				completionBlock(nil, httpResponse, Error(DownloadErrorCodeTooManyRedirects, nil));
				return;
			}
			// Follow redirection
			Download(url, completionBlock, redirects);
			return;
		} else if(status != 200) {
			// Other status
			completionBlock(nil, httpResponse, Error(DownloadErrorCodeBadStatus, [NSString stringWithFormat:@"%d, %@", (int)status, [NSHTTPURLResponse localizedStringForStatusCode:status]]));
			return;
		}

		completionBlock(data, httpResponse, nil);
	}];
}

void DownloadDataFromURL(NSURL *url, DownloadCompletionBlock completionBlock) {
	Download(url, completionBlock, 0);
}

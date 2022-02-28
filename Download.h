#pragma once
#import <Foundation/Foundation.h>

typedef enum {
	DownloadErrorCodeInvalidURL,
	DownloadErrorCodeUnexpectedResponseType,
	DownloadErrorCodeRedirectWithoutLocation,
	DownloadErrorCodeTooManyRedirects,
	DownloadErrorCodeBadStatus
} DownloadErrorCode;

typedef void (^DownloadCompletionBlock)(NSData *data, NSURLResponse *response, NSError *error);

void DownloadDataFromURL(NSURL *url, DownloadCompletionBlock completionBlock);

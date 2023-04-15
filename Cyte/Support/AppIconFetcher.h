//
//  AppIconFetcher.h
//  Cyte
//
//  Created by Shaun Narayan on 15/04/23.
//

#ifndef AppIconFetcher_h
#define AppIconFetcher_h

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppIconFetcher : NSObject

+ (nullable UIImage *)iconForBundleID:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
#endif

#endif /* AppIconFetcher_h */

//
//  AppIconFetcher.m
//  Cyte
//
//  Created by Shaun Narayan on 15/04/23.
//

#import <Foundation/Foundation.h>
#import "AppIconFetcher.h"
#import <objc/runtime.h>

@implementation AppIconFetcher

+ (nullable UIImage *)iconForBundleID:(NSString *)bundleID {
    Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
    if (!LSApplicationWorkspace_class) {
        return nil;
    }
    
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (![LSApplicationWorkspace_class respondsToSelector:defaultWorkspaceSelector]) {
        return nil;
    }
    
    NSObject *workspace = [LSApplicationWorkspace_class performSelector:defaultWorkspaceSelector];
    
    SEL applicationProxyForIdentifierSelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![workspace respondsToSelector:applicationProxyForIdentifierSelector]) {
        return nil;
    }
    
    NSObject *applicationProxy = [workspace performSelector:applicationProxyForIdentifierSelector withObject:bundleID];
    
    SEL iconDataForVariantSelector = NSSelectorFromString(@"iconDataForVariant:");
    if (![applicationProxy respondsToSelector:iconDataForVariantSelector]) {
        return nil;
    }
    
    NSData *iconData = [applicationProxy performSelector:iconDataForVariantSelector withObject:@(2)];
    UIImage *iconImage = [UIImage imageWithData:iconData];
    
    return iconImage;
}

@end

//
//  LivePhotoHelper.h
//  Image Downloader
//
//  Created by 埃苯泽 on 2025/1/11.
//  Copyright (c) 2025 iBenzene. All rights reserved.
//

#ifndef LivePhotoHelper_h
#define LivePhotoHelper_h

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <CoreMedia/CMMetadata.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NS_ASSUME_NONNULL_BEGIN

@interface LivePhotoHelper : NSObject

@property (nonatomic) AVAssetReader *reader;
@property (nonatomic) AVAssetWriter *writer;
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic) dispatch_group_t group;

- (void)saveLivePhoto:(NSURL *)coverUrl
             videoUrl:(NSURL *)videoUrl
           completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

#endif /* LivePhotoHelper_h */

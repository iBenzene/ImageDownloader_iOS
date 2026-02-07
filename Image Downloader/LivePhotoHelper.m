//
//  LivePhotoHelper.m
//  Image Downloader
//
//  Created by 埃苯泽 on 2025/1/11.
//  Copyright (c) 2025 iBenzene. All rights reserved.
//
//  References: https://github.com/DeviLeo/LivePhotoConverter
//

#import "LivePhotoHelper.h"

@implementation LivePhotoHelper

/**
 * 保存 Live Photo 至相册
 * @param coverUrl    静态封面的 URL
 * @param videoUrl    配套视频的 URL
 * @param completion  保存完成后的回调，包含是否成功和错误信息
 */
- (void)saveLivePhoto:(NSURL *)coverUrl
             videoUrl:(NSURL *)videoUrl
           completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    // 为 Live Photo 生成唯一标识符
    NSString *identifier = [NSUUID UUID].UUIDString;
    
    // 使用资源写入器处理静态封面和配套视频的元数据
    [self useAssetWriter:coverUrl oldVideoUrl:videoUrl identifier:identifier complete:^(BOOL success, NSString *newCoverPath, NSString *newVideoPath, NSError *error) {
        NSURL *coverUrl = [NSURL fileURLWithPath:newCoverPath];
        NSURL *videoUrl = [NSURL fileURLWithPath:newVideoPath];
        
        // 合并静态封面和配套视频, 并将所得的 Live Photo 保存至相册
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            [request addResourceWithType:PHAssetResourceTypePhoto fileURL:coverUrl options:nil];
            [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:videoUrl options:nil];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            // 删除临时文件
            [self deleteFile:newCoverPath];
            [self deleteFile:newVideoPath];
            NSLog(@"♻️ 已删除临时文件: %@", newCoverPath);
            NSLog(@"♻️ 已删除临时文件: %@", newVideoPath);
            
            if (completion) {
                if (success) {
                    completion(YES, nil);
                } else {
                    completion(NO, error);
                }
            }
        }];
    }];
}

/**
 * 使用资源数据写入管理器处理静态封面和配套视频
 * @param oldCoverUrl   原封面的 URL
 * @param oldVideoUrl   原视频的 URL
 * @param identifier    唯一标识符
 * @param complete  写入完成后的回调
 */
- (void)useAssetWriter:(NSURL *)oldCoverUrl oldVideoUrl:(NSURL *)oldVideoUrl identifier:(NSString *)identifier complete:(void (^)(BOOL success, NSString *newCoverUrl, NSString *newVideoUrl, NSError *error))complete {
    
    // 处理静态封面
    NSString *livePhotoName = [self getCurrentTime];
    NSString *newCoverUrl = [self createFile:[livePhotoName stringByAppendingString:@".jpg"]];
    [self addMetadataToCover:oldCoverUrl newCoverUrl:newCoverUrl identifier:identifier];
    
    // 处理配套视频
    NSString *newVideoUrl = [self createFile:[livePhotoName stringByAppendingString:@".mp4"]];
    [self addMetadataToVideo:oldVideoUrl newVideoUrl:newVideoUrl identifier:identifier];
    
    // 确保资源组存在
    if (!self.group) return;
    dispatch_group_notify(self.group, dispatch_get_main_queue(), ^{
        [self finishWritingTracksWithCover:newCoverUrl videoUrl:newVideoUrl complete:complete];
    });
}

/**
 * 获取当前时间，格式为「年-月-日_时-分-秒」，例如: 2025-01-04_15-07-14
 */
- (NSString *)getCurrentTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *time = [formatter stringFromDate:[NSDate date]];
    return time;
}


/**
 * 给静态封面添加元数据
 * @param oldCoverUrl   原封面的 URL
 * @param newCoverUrl   输出封面的 URL
 * @param identifier    唯一标识符
 */
- (void)addMetadataToCover:(NSURL *)oldCoverUrl newCoverUrl:(NSString *)newCoverUrl identifier:(NSString *)identifier {
    NSMutableData *data = [NSData dataWithContentsOfURL:oldCoverUrl].mutableCopy;
    UIImage *image = [UIImage imageWithData:data];
    CGImageRef imageRef = image.CGImage;
    NSDictionary *imageMetadata = @{(NSString *)kCGImagePropertyMakerAppleDictionary : @{@"17" : identifier}};
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((CFMutableDataRef)data, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, nil);
    CGImageDestinationAddImage(dest, imageRef, (CFDictionaryRef)imageMetadata);
    CGImageDestinationFinalize(dest);
    [data writeToFile:newCoverUrl atomically:YES];
}

/**
 * 给配套视频添加元数据
 * @param oldVideoUrl   原视频的 URL
 * @param newVideoUrl   输出视频的 URL
 * @param identifier    唯一标识符
 */

- (void)addMetadataToVideo:(NSURL *)oldVideoUrl newVideoUrl:(NSString *)newVideoUrl identifier:(NSString *)identifier {
    NSError *error = nil;
    
    // 创建视频数据读取管理器
    AVAsset *asset = [AVAsset assetWithURL:oldVideoUrl];
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (error) {
        NSLog(@"⚠️ Init reader error: %@", error);
        return;
    }
    NSMutableArray<AVMetadataItem *> *metadata = asset.metadata.mutableCopy;
    AVMetadataItem *item = [self createContentIdentifierMetadataItem:identifier];
    [metadata addObject:item];
    
    // 创建视频数据写入管理器
    NSURL *videoFileURL = [NSURL fileURLWithPath:newVideoUrl];
    [self deleteFile:newVideoUrl];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:videoFileURL fileType:AVFileTypeQuickTimeMovie error:&error];
    if (error) {
        NSLog(@"⚠️ Init writer error: %@", error);
        return;
    }
    [writer setMetadata:metadata];
    
    // 处理视频轨道
    NSArray<AVAssetTrack *> *tracks = [asset tracks];
    for (AVAssetTrack *track in tracks) {
        NSDictionary *readerOutputSettings = nil;
        NSDictionary *writerOuputSettings = nil;
        if ([track.mediaType isEqualToString:AVMediaTypeAudio]) {
            readerOutputSettings = @{AVFormatIDKey : @(kAudioFormatLinearPCM)};
            writerOuputSettings = @{AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                    AVSampleRateKey : @(44100),
                                    AVNumberOfChannelsKey : @(2),
                                    AVEncoderBitRateKey : @(128000)};
        }
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:readerOutputSettings];
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:track.mediaType outputSettings:writerOuputSettings];
        if ([reader canAddOutput:output] && [writer canAddInput:input]) {
            [reader addOutput:output];
            [writer addInput:input];
        }
    }
    
    // 添加元数据轨道
    AVAssetWriterInput *input = [self createStillImageTimeAssetWriterInput];
    AVAssetWriterInputMetadataAdaptor *adaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:input];
    if ([writer canAddInput:input]) {
        [writer addInput:input];
    }
    
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    [reader startReading];
    
    // 写入元数据轨道的元数据
    AVMetadataItem *timedItem = [self createStillImageTimeMetadataItem];
    CMTimeRange timedRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(1, 100));
    AVTimedMetadataGroup *timedMetadataGroup = [[AVTimedMetadataGroup alloc] initWithItems:@[timedItem] timeRange:timedRange];
    [adaptor appendTimedMetadataGroup:timedMetadataGroup];
    
    // 写入其他轨道
    self.reader = reader;
    self.writer = writer;
    self.queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    self.group = dispatch_group_create();
    for (NSInteger i = 0; i < reader.outputs.count; ++i) {
        dispatch_group_enter(self.group);
        [self writeTrack:i];
    }
}

/**
 * 写入单个轨道数据
 * @param trackIndex  轨道索引
 */
- (void)writeTrack:(NSInteger)trackIndex {
    AVAssetReaderOutput *output = self.reader.outputs[trackIndex];
    AVAssetWriterInput *input = self.writer.inputs[trackIndex];
    
    [input requestMediaDataWhenReadyOnQueue:self.queue usingBlock:^{
        while (input.readyForMoreMediaData) {
            AVAssetReaderStatus status = self.reader.status;
            CMSampleBufferRef buffer = NULL;
            if ((status == AVAssetReaderStatusReading) &&
                (buffer = [output copyNextSampleBuffer])) {
                BOOL success = [input appendSampleBuffer:buffer];
                CFRelease(buffer);
                if (!success) {
                    NSLog(@"⚠️ Track %d. Failed to append buffer.", (int)trackIndex);
                    [input markAsFinished];
                    dispatch_group_leave(self.group);
                    return;
                }
            } else {
                if (status == AVAssetReaderStatusReading) {
                    NSLog(@"✅ Track %d complete.", (int)trackIndex);
                } else if (status == AVAssetReaderStatusCompleted) {
                    NSLog(@"✅ Reader completed.");
                } else if (status == AVAssetReaderStatusCancelled) {
                    NSLog(@"❌ Reader cancelled.");
                } else if (status == AVAssetReaderStatusFailed) {
                    NSLog(@"⚠️ Reader failed.");
                }
                [input markAsFinished];
                dispatch_group_leave(self.group);
                return;
            }
        }
    }];
}

/**
 * 完成所有轨道的写入
 * @param coverUrl   静态封面的 URL
 * @param videoUrl   配套视频的 URL
 * @param complete    写入完成后的回调
 */
- (void)finishWritingTracksWithCover:(NSString *)coverUrl videoUrl:(NSString *)videoUrl complete:(void (^)(BOOL success, NSString *coverUrl, NSString *videoUrl, NSError *error))complete {
    [self.reader cancelReading];
    [self.writer finishWritingWithCompletionHandler:^{
        if (complete) complete(YES, coverUrl, videoUrl, nil);
    }];
}

/**
 * 创建内容标识符的元数据项
 * @param identifier  唯一标识符
 * @return 元数据项
 */
- (AVMetadataItem *)createContentIdentifierMetadataItem:(NSString *)identifier {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = AVMetadataQuickTimeMetadataKeyContentIdentifier;
    item.value = identifier;
    return item;
}

/**
 * 创建静态封面时间的元数据输入
 * @return 视频数据写入管理器
 */
- (AVAssetWriterInput *)createStillImageTimeAssetWriterInput {
    NSArray *spec = @[@{(NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : @"mdta/com.apple.quicktime.still-image-time",
                        (NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (NSString *)kCMMetadataBaseDataType_SInt8 }];
    CMFormatDescriptionRef desc = NULL;
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)spec, &desc);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata outputSettings:nil sourceFormatHint:desc];
    return input;
}

/**
 * 创建静态封面时间的元数据项
 * @return 元数据项
 */
- (AVMetadataItem *)createStillImageTimeMetadataItem {
    AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = @"com.apple.quicktime.still-image-time";
    item.value = @(-1);
    item.dataType = (NSString *)kCMMetadataBaseDataType_SInt8;
    return item;
}

/**
 * 根据指定文件名，在临时目录中「创建」文件，并返回其路径
 * @param fileName    文件名
 * @return 文件路径
 */
- (NSString *)createFile:(NSString *)fileName {
    NSString *tmpPath = NSTemporaryDirectory();
    NSString *filePath = [tmpPath stringByAppendingPathComponent:fileName];
    return filePath;
}

/**
 * 删除指定路径的文件
 * @param filePath    文件路径
 */
- (void)deleteFile:(NSString *)filePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:filePath]) {
        [fm removeItemAtPath:filePath error:nil];
    }
}

@end

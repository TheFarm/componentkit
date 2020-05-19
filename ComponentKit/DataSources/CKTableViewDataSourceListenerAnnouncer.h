/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <Foundation/Foundation.h>

#import <ComponentKit/CKComponentAnnouncerBase.h>
#import <ComponentKit/CKTableViewDataSourceListener.h>

@interface CKTableViewDataSourceListenerAnnouncer : CKComponentAnnouncerBase <CKTableViewDataSourceListener>

- (void)addListener:(id<CKTableViewDataSourceListener>)listener;
- (void)removeListener:(id<CKTableViewDataSourceListener>)listener;

@end

/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <ComponentKit/CKDefines.h>

#if CK_NOT_SWIFT

#import <ComponentKit/CKTableViewDataSource.h>

@class CKDataSource;
@class CKDataSourceState;
@protocol CKTableViewDataSourceListener;

@interface CKTableViewDataSource ()

/**
 The underlying `CKDataSource` that `CKTableViewDataSource` is holding. @see CKDataSource
 A new instance of `componentDataSource` will be created if a new state is set to `CKTableViewDataSource`.
 */
@property (nonatomic, readonly, strong) CKDataSource *componentDataSource;

/**
 Allow tap passthrough root view of table view cells.
 */
- (void)setAllowTapPassthroughForCells:(BOOL)allowTapPassthroughForCells;

/**
 Set a new `CKDataSourceState` and reload data of the underlying table view.
 A new instance of `componentDataSource` will be created.
 */
- (void)setState:(CKDataSourceState *)state;

/** Access the current state. Main thread affined */
- (CKDataSourceState *)currentState;

- (void)addListener:(id<CKTableViewDataSourceListener>)listener;
- (void)removeListener:(id<CKTableViewDataSourceListener>)listener;

@end

#endif

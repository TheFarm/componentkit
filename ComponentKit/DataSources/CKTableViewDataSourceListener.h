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

@class CKTableViewDataSource;
@class CKDataSourceAppliedChanges;
@class CKDataSourceState;

@protocol CKTableViewDataSourceListener

- (void)dataSourceWillBeginUpdates:(CKTableViewDataSource *)dataSource;

- (void)dataSourceDidEndUpdates:(CKTableViewDataSource *)dataSource
         didModifyPreviousState:(CKDataSourceState *)previousState
                      withState:(CKDataSourceState *)state
              byApplyingChanges:(CKDataSourceAppliedChanges *)changes;

- (void)dataSource:(CKTableViewDataSource *)dataSource
   willChangeState:(CKDataSourceState *)state;

- (void)dataSource:(CKTableViewDataSource *)dataSource
    didChangeState:(CKDataSourceState *)previousState
         withState:(CKDataSourceState *)state;

@end

#endif

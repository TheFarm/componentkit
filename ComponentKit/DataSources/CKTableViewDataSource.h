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

#import <UIKit/UIKit.h>

#import <ComponentKit/CKDataSource.h>
#import <ComponentKit/CKTableViewDataSourceDelegate.h>
#import <ComponentKit/CKGenericDataSource.h>

@interface CKTableViewDataSource : NSObject <CKGenericDataSource>
/**
 @param tableView The tableView is held strongly and its dataSource property will be set to the receiver.
 @param delegate Will be held weakly, pass nil if you don't need tableView delegate methods
 */
- (instancetype)initWithTableView:(UITableView *)tableView
                         delegate:(id<CKTableViewDataSourceDelegate>)delegate
                    configuration:(CKDataSourceConfiguration *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/**
 Applies a changeset either synchronously or asynchronously to the table view.
 If a synchronous changeset is applied while asynchronous changesets are still pending, then the pending changesets will be applied synchronously
 before the new changeset is applied.
 */
- (void)applyChangeset:(CKDataSourceChangeset *)changeset
                  mode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo;

/**
 @return The model associated with a certain index path in the table view.
 
 As stated above components are generated asynchronously and on a background thread. This means that a changeset is enqueued
 and applied asynchronously when the corresponding component tree is generated. For this reason always use this method when you
 want to retrieve the model associated to a certain index path in the table view (e.g in didSelectRowAtIndexPath: )
 */
- (id<NSObject>)modelForItemAtIndexPath:(NSIndexPath *)indexPath;

/**
 @return The index path associated with a certain object in the table view.
 
 As stated above components are generated asynchronously and on a background thread.
 */
- (NSIndexPath *)indexPathForModel:(id)model;

/**
 @return The layout size of the component tree at a certain index path. Use this to access the component sizes for instance in a
 `UICollectionViewLayout(s)` or in a `UICollectionViewDelegateFlowLayout`.
 */
- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath;

/** @see `CKDataSource` */
- (void)reloadWithMode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo;

/** @see `CKDataSource` */
- (void)updateConfiguration:(CKDataSourceConfiguration *)configuration
                       mode:(CKUpdateMode)mode
                   userInfo:(NSDictionary *)userInfo;

/**
 Sends -componentTreeWillAppear to all CKComponentControllers for the given cell.
 If needed, call this from -collectionView:willDisplayCell:forItemAtIndexPath:
 */
- (void)announceWillDisplayCell:(UITableViewCell *)cell;

/**
 Sends -componentTreeDidDisappear to all CKComponentControllers for the given cell.
 If needed, call this from -collectionView:didEndDisplayingCell:forItemAtIndexPath:
 */
- (void)announceDidEndDisplayingCell:(UITableViewCell *)cell;

@property (readonly, nonatomic, strong) UITableView *tableView;
/**
 */
@property (readonly, nonatomic, weak) id<CKTableViewDataSourceDelegate> delegate;
@end

#endif

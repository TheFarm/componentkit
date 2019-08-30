//
//  CKGenericDataSource.h
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#ifndef CKGenericDataSource_h
#define CKGenericDataSource_h

#import <ComponentKit/CKDataSourceChangeset.h>
#import <ComponentKit/CKDataSourceConfiguration.h>

@protocol CKGenericDataSource <NSObject>

/**
 Applies a changeset either synchronously or asynchronously to the collection view.
 If a synchronous changeset is applied while asynchronous changesets are still pending, then the pending changesets will be applied synchronously
 before the new changeset is applied.
 */
- (void)applyChangeset:(CKDataSourceChangeset *)changeset
                  mode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo;

/**
 @return The model associated with a certain index path in the collectionView or tableView.
 
 As stated above components are generated asynchronously and on a background thread. This means that a changeset is enqueued
 and applied asynchronously when the corresponding component tree is generated. For this reason always use this method when you
 want to retrieve the model associated to a certain index path in the table view (e.g in didSelectRowAtIndexPath: )
 */
- (id<NSObject>)modelForItemAtIndexPath:(NSIndexPath *)indexPath;

/**
 @return The index path associated with a certain object in the collectionView or tableView.
 
 As stated above components are generated asynchronously and on a background thread.
 */
- (NSIndexPath *)indexPathForModel:(id)object;

/**
 @return The layout size of the component tree at a certain indexPath. Use this to access the component sizes for instance in a
 `UICollectionViewLayout(s)` or in a `UICollectionViewDelegateFlowLayout`.
 */
- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath;

/**
 @return The layout height of the component tree at a certain indexPath. Use this to access the component heights.
 */
- (CGFloat)heightForItemAtIndexPath:(NSIndexPath *)indexPath;

/** @see `CKDataSourceChangeset` */
- (void)reloadWithMode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo;

/** @see `CKDataSourceChangeset` */
- (void)updateConfiguration:(CKDataSourceConfiguration *)configuration
                       mode:(CKUpdateMode)mode
                   userInfo:(NSDictionary *)userInfo;

@end

#endif /* CKGenericDataSource_h */

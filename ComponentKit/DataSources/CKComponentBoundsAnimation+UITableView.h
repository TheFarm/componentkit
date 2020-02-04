//
//  CKComponentBoundsAnimation+UITableView.h
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import <ComponentKit/CKDefines.h>

#if CK_NOT_SWIFT

#import <UIKit/UIKit.h>
#import <ComponentKit/CKComponentBoundsAnimation.h>

/**
 UITableView's builtin animations are quite limited:
 - You cannot customize the duration or delay.
 - You cannot use a spring animation.
 - Cells that were offscreen before the change and onscreen afterwards snap directly into place without animation.
 
 This function provides a way to perform custom animations for UITableView, with the following restrictions:
 - You **must not** call this function if the update includes inserts, deletes, or moves.
 In those cases, you must rely on UITableView's built-in animations.
 - It can only apply a single CKComponentBoundsAnimation. If there are multiple simultaneous updates with differing
 animations, you must choose only one.
 - It may not be well-suited to complex table view layouts.
 
 If you're implementing a table view data source, call this function just before you call
 [UITableView beginUpdates] wrapped with [UIView +performWithoutAnimation:]. For example:
 
 id context = CKComponentBoundsAnimationPrepareForTableViewBatchUpdates(tableView);
 [UIView performWithoutAnimation:^{ [tableView beginUpdates];[tableView endUpdates]; }];
 CKComponentBoundsAnimationApplyAfterTableViewBatchUpdates(context, boundsAnimation);
 
 @see CKCollectionViewDataSource for a sample implementation.
 
 @return A context that may be passed to CKComponentBoundsAnimationApplyAfterBatchUpdates. Calling it is optional;
 for example, if you determine that the update has no animation, or that all index paths to be animated are offscreen,
 you can skip calling CKComponentBoundsAnimationApplyAfterBatchUpdates entirely.
 */
id CKComponentBoundsAnimationPrepareForTableViewBatchUpdates(UITableView *tv, CGFloat heightChange);

/** @see CKComponentBoundsAnimationPrepareForTableViewBatchUpdates */
void CKComponentBoundsAnimationApplyAfterTableViewBatchUpdates(id context, const CKComponentBoundsAnimation &animation);

#endif

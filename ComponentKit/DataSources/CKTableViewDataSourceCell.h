//
//  CKTableViewDataSourceCell.h
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CKComponentRootView;

@interface CKTableViewDataSourceCell : UITableViewCell
@property (nonatomic, strong, readonly) CKComponentRootView *rootView;
@end

NS_ASSUME_NONNULL_END

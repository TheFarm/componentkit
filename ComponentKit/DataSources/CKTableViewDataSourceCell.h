//
//  CKTableViewDataSourceCell.h
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import <UIKit/UIKit.h>

#import <ComponentKit/CKNonNull.h>

@class CKComponentRootView;

@interface CKTableViewDataSourceCell : UITableViewCell
@property (nonatomic, assign, readonly) CK::NonNull<CKComponentRootView *> rootView;
@end

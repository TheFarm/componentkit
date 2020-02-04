//
//  CKTableViewDataSourceCell.m
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import "CKTableViewDataSourceCell.h"

#import <ComponentKit/CKDelayedNonNull.h>

#import <ComponentKit/CKComponentRootView.h>

@implementation CKTableViewDataSourceCell {
  CK::DelayedNonNull<CKComponentRootView *> _rootView;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    // Ideally we could simply cause the cell's existing contentView to be of type CKComponentRootView.
    // Alas the only way to do this is via private API (_contentViewClass) so we are forced to add a subview.
    _rootView = CK::makeNonNull([[CKComponentRootView alloc] initWithFrame:CGRectZero]);
    [[self contentView] addSubview:_rootView];
  }
  return self;
}

- (CK::NonNull<CKComponentRootView *>)rootView
{
  return _rootView;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  const CGSize size = [[self contentView] bounds].size;
  [_rootView setFrame:CGRectMake(0, 0, size.width, size.height)];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  UIView *hitView = [super hitTest:point withEvent:event];
  // `hitTest` should purely rely on `CKComponentRootView`.
  if (hitView == self || hitView == self.contentView) {
    return nil;
  }
  return hitView;
}

@end


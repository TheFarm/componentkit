/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKTableViewDataSourceCell.h"

#import <ComponentKit/CKDelayedNonNull.h>

#import "CKComponentRootView.h"

@implementation CKTableViewDataSourceCell {
  CK::DelayedNonNull<CKComponentRootView *> _rootView;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    [self commonInit];
  }
  return self;
}


- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (self) {
    [self commonInit];
  }
  return self;
}


- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    [self commonInit];
  }
  return self;
}


- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
  if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
    [self commonInit];
  }
  return self;
}


- (void)commonInit
{
  // Ideally we could simply cause the cell's existing contentView to be of type CKComponentRootView.
  // Alas the only way to do this is via private API (_contentViewClass) so we are forced to add a subview.
  _rootView = CK::makeNonNull([[CKComponentRootView alloc] initWithFrame:CGRectZero]);
  
  [[self contentView] addSubview:_rootView];
  
  UIColor *clear = [UIColor clearColor];
  [self setBackgroundColor:clear];
  [self.contentView setBackgroundColor:clear];
  [self.backgroundView setBackgroundColor:clear];
  [_rootView setBackgroundColor:clear];
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


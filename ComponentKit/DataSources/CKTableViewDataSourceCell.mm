//
//  CKTableViewDataSourceCell.m
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import "CKTableViewDataSourceCell.h"

#import <ComponentKit/CKComponentRootView.h>

@implementation CKTableViewDataSourceCell {
  CKComponentRootView *_rootView;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _rootView = [[CKComponentRootView alloc] initWithFrame:CGRectZero];
    [_rootView setBackgroundColor:[UIColor clearColor]];
    [[self contentView] addSubview:_rootView];
    [[self contentView] setBackgroundColor:[UIColor clearColor]];
    [self setBackgroundColor:[UIColor clearColor]];
  }
  return self;
}


- (void)awakeFromNib
{
  [super awakeFromNib];
  
  if (!_rootView) {
    // Ideally we could simply cause the cell's existing contentView to be of type CKComponentRootView.
    // Alas the only way to do this is via private API (_contentViewClass) so we are forced to add a subview.
    _rootView = [[CKComponentRootView alloc] initWithFrame:CGRectZero];
    [_rootView setBackgroundColor:[UIColor clearColor]];
    [[self contentView] addSubview:_rootView];
    [[self contentView] setBackgroundColor:[UIColor clearColor]];
    [self setBackgroundColor:[UIColor clearColor]];
  }
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    // Ideally we could simply cause the cell's existing contentView to be of type CKComponentRootView.
    // Alas the only way to do this is via private API (_contentViewClass) so we are forced to add a subview.
    _rootView = [[CKComponentRootView alloc] initWithFrame:CGRectZero];
    [_rootView setBackgroundColor:[UIColor clearColor]];
    [[self contentView] addSubview:_rootView];
    [[self contentView] setBackgroundColor:[UIColor clearColor]];
    [self setBackgroundColor:[UIColor clearColor]];
  }
  return self;
}


- (CKComponentRootView *)rootView
{
  if (!_rootView) {
    _rootView = [[CKComponentRootView alloc] initWithFrame:CGRectZero];
    [_rootView setBackgroundColor:[UIColor clearColor]];
    [[self contentView] addSubview:_rootView];
    [[self contentView] setBackgroundColor:[UIColor clearColor]];
    [self setBackgroundColor:[UIColor clearColor]];
  }
  return _rootView;
}


- (void)layoutSubviews
{
  [super layoutSubviews];
  
  const CGSize size = [[self contentView] bounds].size;
  [_rootView setFrame:CGRectMake(0, 0, size.width, size.height)];
}

@end


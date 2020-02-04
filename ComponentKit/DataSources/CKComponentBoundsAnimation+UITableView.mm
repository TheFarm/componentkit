//
//  CKComponentBoundsAnimation+UITableView.mm
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import "CKComponentBoundsAnimation+UITableView.h"

#import <ComponentKit/CKAvailability.h>

#import <vector>

@interface CKComponentBoundsAnimationTableViewContext : NSObject
- (instancetype)initWithTableView:(UITableView *)tv heightChange:(CGFloat)heightChange;
- (void)applyBoundsAnimationToTableView:(const CKComponentBoundsAnimation &)animation;
@end

id CKComponentBoundsAnimationPrepareForTableViewBatchUpdates(UITableView *tv, CGFloat heightChange)
{
  return [[CKComponentBoundsAnimationTableViewContext alloc] initWithTableView:tv heightChange:heightChange];
}

void CKComponentBoundsAnimationApplyAfterTableViewBatchUpdates(id context, const CKComponentBoundsAnimation &animation)
{
  [(CKComponentBoundsAnimationTableViewContext *)context applyBoundsAnimationToTableView:animation];
}

@implementation CKComponentBoundsAnimationTableViewContext
{
  UITableView *_tableView;
  NSInteger _numberOfSections;
  std::vector<NSUInteger> _numberOfItemsInSection;
  NSDictionary *_indexPathsToSnapshotViews;
  NSDictionary *_indexPathsToOriginalLayoutAttributes;
}

- (instancetype)initWithTableView:(UITableView *)tableView heightChange:(CGFloat)heightChange
{
  if (self = [super init]) {
    _tableView = tableView;
    _numberOfSections = [tableView numberOfSections];
    for (NSInteger i = 0; i < _numberOfSections; i++) {
      _numberOfItemsInSection.push_back([tableView numberOfRowsInSection:i]);
    }
    
    // We might need to use a snapshot view to animate cells that are going offscreen, but we don't know which ones yet.
    // Grab a snapshot view for every cell; they'll be used or discarded in -applyBoundsAnimationToTableView:.
    const CGSize visibleSize = tableView.bounds.size;
    const CGRect visibleRect = { tableView.contentOffset, visibleSize };
    
    // visible as a result of an item becoming smaller (heightChange < 0)? We grab the layout attributes of a few more
    // items that are offscreen so that we can animate them too. (Only some, though; we don't attempt to get *all*
    // layout attributes.) If an item becomes bigger, no additional cells would become visible, so there's no need to
    // extend the rectangle.
    const CGFloat offscreenHeight = heightChange > 0 ? 0 : -heightChange;
    const CGRect extendedRect = { visibleRect.origin, { visibleSize.width, visibleSize.height + offscreenHeight } };
    
    NSMutableDictionary *indexPathsToSnapshotViews = [NSMutableDictionary dictionary];
    NSMutableDictionary *indexPathsToOriginalLayoutAttributes = [NSMutableDictionary dictionary];
    
    for (NSIndexPath *extendedVisibleIndexPath in [tableView indexPathsForRowsInRect:extendedRect]) {
      NSIndexPath * const indexPath = extendedVisibleIndexPath;
      UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
      indexPathsToOriginalLayoutAttributes[indexPath] = cell;
      if (CGRectIntersectsRect(cell.frame, visibleRect)) {
        UIView *snapshotView = [cell snapshotViewAfterScreenUpdates:NO];
        if (snapshotView) {
          indexPathsToSnapshotViews[indexPath] = snapshotView;
        }
      }
    }
    
    _indexPathsToSnapshotViews = indexPathsToSnapshotViews;
    _indexPathsToOriginalLayoutAttributes = indexPathsToOriginalLayoutAttributes;
  }
  return self;
}

- (void)applyBoundsAnimationToTableView:(const CKComponentBoundsAnimation &)animation
{
  if (animation.duration == 0) {
    return;
  }
  // Don't animate the table view if it is not being displayed.
  if (!_tableView.window) {
    return;
  }
  // The documentation states that you must not use these functions with inserts or deletes. Let's be safe:
  if ([_tableView numberOfSections] != _numberOfSections) {
    return;
  }
  for (NSInteger i = 0; i < _numberOfSections; i++) {
    if (_numberOfItemsInSection.at(i) != [_tableView numberOfRowsInSection:i]) {
      return;
    }
  }
  const CGRect visibleRect = {.origin = [_tableView contentOffset], .size = [_tableView bounds].size};
  // If for some reason the table view is not visible do not attempt to apply any bounds animations.
  if (CGRectIsEmpty(visibleRect)) {
    return;
  }
  
  // First, move the cells to their old positions without animation:
  NSMutableDictionary *indexPathsToAnimatingViews = [NSMutableDictionary dictionary];
  NSMutableArray *snapshotViewsToRemoveAfterAnimation = [NSMutableArray array];
  NSIndexPath *largestAnimatingVisibleElement = largestAnimatingVisibleElementForOriginalLayout(_indexPathsToOriginalLayoutAttributes, visibleRect);
  [UIView performWithoutAnimation:^{
    [_indexPathsToOriginalLayoutAttributes enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *indexPath, UITableViewCell *attributes, BOOL *stop) {
      // If we're animating an item *out* of the table view's visible bounds, we can't rely on animating a
      // UITableViewCell. Confusingly enough there will be a cell at the exact moment this function is called,
      // but the UITableView will reclaim and hide it at the end of the run loop turn. Use a snapshot view instead.
      // Also, the largest animating visible element will be retained inside the visible bounds so don't use a snapshot view.
      if (CGRectIntersectsRect(visibleRect, [[_tableView cellForRowAtIndexPath:indexPath] frame]) || [indexPath isEqual:largestAnimatingVisibleElement]) {
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (cell) {
          // Surprisingly -applyLayoutAttributes: does not apply bounds or center; that's deeper magic.
          [cell setBounds:attributes.bounds];
          [cell setCenter:attributes.center];
          indexPathsToAnimatingViews[indexPath] = cell;
        }
      } else {
        UIView *snapshotView = _indexPathsToSnapshotViews[indexPath];
        if (snapshotView) {
          [snapshotView setBounds:attributes.bounds];
          [snapshotView setCenter:attributes.center];
          [_tableView addSubview:snapshotView];
          indexPathsToAnimatingViews[indexPath] = snapshotView;
          [snapshotViewsToRemoveAfterAnimation addObject:snapshotView];
        }
      }
    }];
  }];
  
  // The smallest adjustment we have to make the content-offset to keep the largest visible element from being animated off-screen. When the largest element suddenly disappears the user
  // loses context and the result is jarring.
  CGPoint contentOffsetAdjustment = contentOffsetAdjustmentToKeepElementInVisibleBounds(largestAnimatingVisibleElement, indexPathsToAnimatingViews, _tableView, visibleRect);
  
  // Then move them back to their current positions with animation:
  void (^restore)(void) = ^{
    [indexPathsToAnimatingViews enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *indexPath, UIView *view, BOOL *stop) {
      UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
      [view setBounds:cell.bounds];
      [view setCenter:cell.center];
    }];
    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x + contentOffsetAdjustment.x, _tableView.contentOffset.y + contentOffsetAdjustment.y)];
  };
  void (^completion)(BOOL) = ^(BOOL finished){
    for (UIView *v in snapshotViewsToRemoveAfterAnimation) {
      [v removeFromSuperview];
    }
  };
  CKComponentBoundsAnimationApply(animation, restore, completion);
  
  _tableView = nil;
  _indexPathsToSnapshotViews = nil;
  _indexPathsToOriginalLayoutAttributes = nil;
}

#pragma mark - Maintain context during bounds animation

// @abstract Returns the minimum content offset adjustment that would keep the largest visible element in the table view in the viewport post-animation.
// @param largestVisibleAnimatingElementIndexPath The index path of the largest visible element that will be animated for the bounds animation.
// @param indexPathsToAnimationViews A dictionary that maps index paths of the animating elements of the table view, to their view.
// @param tableView The table view the bounds change animation is being applied to.
// @param visibleRect The visible portion of the table-view's contents.
// @return The minimum content offset to set on the table-view that will keep the largest visible element still visible.
static CGPoint contentOffsetAdjustmentToKeepElementInVisibleBounds(NSIndexPath *largestVisibleAnimatingElementIndexPath, NSDictionary *indexPathsToAnimatingViews, UITableView *tableView, CGRect visibleRect)
{
  CGPoint contentOffsetAdjustment = CGPointZero;
  BOOL largestVisibleElementWillExitVisibleRect = elementWillExitVisibleRect(largestVisibleAnimatingElementIndexPath, indexPathsToAnimatingViews, tableView, visibleRect);
  
  if (largestVisibleElementWillExitVisibleRect) {
    CGRect currentBounds = ((UIView *)indexPathsToAnimatingViews[largestVisibleAnimatingElementIndexPath]).bounds;
    CGRect destinationBounds = ((UITableViewCell *) [tableView cellForRowAtIndexPath:largestVisibleAnimatingElementIndexPath]).bounds;
    
    CGFloat deltaX = CGRectGetMaxX(destinationBounds) - CGRectGetMaxX(currentBounds);
    CGFloat deltaY = CGRectGetMaxY(destinationBounds) - CGRectGetMaxY(currentBounds);
    
    contentOffsetAdjustment = CGPointMake(deltaX, deltaY);
  }
  return contentOffsetAdjustment;
}

// @abstract Returns the index-path of largest element in the table, inside the table views visible bounds, as returned by the table view's layout attributes.
// @param indexPathToOriginalLayoutAttributes A dictionary mapping the indexpath of elements to their table view layout attributes.
// @param visibleRect  The visible portion of the table-view's contents.
static NSIndexPath* largestAnimatingVisibleElementForOriginalLayout(NSDictionary *indexPathToOriginalLayoutAttributes, CGRect visibleRect) {
  __block CGRect largestSoFar = CGRectZero;
  __block NSIndexPath *prominentElementIndexPath = nil;
  [indexPathToOriginalLayoutAttributes enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *indexPath, UITableViewCell *attributes, BOOL *stop) {
    CGRect intersection = CGRectIntersection(visibleRect, attributes.frame);
    if (_CGRectArea(intersection) > _CGRectArea(largestSoFar)) {
      largestSoFar = intersection;
      prominentElementIndexPath = indexPath;
    }
  }];
  return prominentElementIndexPath;
}

// Returns YES if the element is current visible, but will not be visible (will be animated off-screen) post animation.
static BOOL elementWillExitVisibleRect(NSIndexPath *indexPath, NSDictionary *indexPathsToAnimatingViews, UITableView *tableView, CGRect visibleRect)
{
  UIView *animatingView = indexPathsToAnimatingViews[indexPath];
  UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
  
  BOOL isItemCurrentlyInVisibleRect = (CGRectIntersectsRect(visibleRect,animatingView.frame));
  BOOL willItemAnimateOffVisibleRect = !CGRectIntersectsRect(visibleRect, cell.frame);
  
  if (isItemCurrentlyInVisibleRect && willItemAnimateOffVisibleRect) {
    return YES;
  }
  return NO;
}

static CGFloat _CGRectArea(CGRect rect)
{
  return CGRectGetWidth(rect) * CGRectGetHeight(rect);
}

@end


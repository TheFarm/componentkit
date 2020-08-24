/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKTableViewDataSource.h"

#import "CKTableViewDataSourceCell.h"
#import "CKDataSourceConfigurationInternal.h"
#import "CKDataSourceListener.h"
#import "CKDataSourceItem.h"
#import "CKDataSourceState.h"
#import "CKDataSourceAppliedChanges.h"
#import "CKDataSourceInternal.h"
#import "CKTableViewDataSourceInternal.h"
#import "CKComponentRootViewInternal.h"
#import "CKComponentLayout.h"
#import "CKComponentAttachController.h"
#import "CKComponentBoundsAnimation+UITableView.h"
#import "CKComponentControllerEvents.h"
#import "CKTableViewDataSourceListenerAnnouncer.h"

@interface CKTableViewDataSource() <UITableViewDataSource, CKDataSourceListener>
{
  CKDataSource *_componentDataSource;
  __weak id<CKTableViewDataSourceDelegate> _delegate;
  CKDataSourceState *_currentState;
  CKComponentAttachController *_attachController;
  NSMapTable<UITableViewCell *, CKDataSourceItem *> *_cellToItemMap;
  CKTableViewDataSourceListenerAnnouncer *_announcer;
  BOOL _allowTapPassthroughForCells;
}
@end

@implementation CKTableViewDataSource
@synthesize delegate = _delegate;

- (instancetype)initWithTableView:(UITableView *)tableView
                         delegate:(id<CKTableViewDataSourceDelegate>)delegate
                    configuration:(CKDataSourceConfiguration *)configuration
{
  self = [super init];
  if (self) {
    _componentDataSource = [[CKDataSource alloc] initWithConfiguration:configuration];
    [_componentDataSource addListener:self];
    
    _tableView = tableView;
    _tableView.dataSource = self;
    [_tableView registerClass:[CKTableViewDataSourceCell class] forCellReuseIdentifier:kReuseIdentifier];
    
    _attachController = [[CKComponentAttachController alloc] init];
    _delegate = delegate;
    _cellToItemMap = [NSMapTable weakToStrongObjectsMapTable];
    _announcer = [CKTableViewDataSourceListenerAnnouncer new];
  }
  return self;
}

- (CKDataSourceState *)currentState
{
  CKAssertMainThread();
  return _currentState;
}

#pragma mark - Changeset application

- (void)applyChangeset:(CKDataSourceChangeset *)changeset
                  mode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo
{
  [_componentDataSource setTraitCollection:_tableView.traitCollection];
  [_componentDataSource applyChangeset:changeset
                                  mode:mode
                              userInfo:userInfo];
}


static void applyChangesToTableView(UITableView *tableView,
                                    CKComponentAttachController *attachController,
                                    NSMapTable<UITableViewCell *, CKDataSourceItem *> *cellToItemMap,
                                    CKDataSourceState *currentState,
                                    CKDataSourceAppliedChanges *changes)
{
  [changes.updatedIndexPaths enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, BOOL *stop) {
    if (CKTableViewDataSourceCell *cell = (CKTableViewDataSourceCell *) [tableView cellForRowAtIndexPath:indexPath]) {
      attachToCell(cell, [currentState objectAtIndexPath:indexPath], attachController, cellToItemMap);
    }
  }];
  [tableView deleteRowsAtIndexPaths:[changes.removedIndexPaths allObjects] withRowAnimation:UITableViewRowAnimationNone];
  [tableView deleteSections:changes.removedSections withRowAnimation:UITableViewRowAnimationNone];
  for (NSIndexPath *from in changes.movedIndexPaths) {
    NSIndexPath *to = changes.movedIndexPaths[from];
    [tableView deleteRowsAtIndexPaths:@[from] withRowAnimation:UITableViewRowAnimationNone];
    [tableView insertRowsAtIndexPaths:@[to] withRowAnimation:UITableViewRowAnimationNone];
  }
  [tableView insertSections:changes.insertedSections withRowAnimation:UITableViewRowAnimationNone];
  [tableView insertRowsAtIndexPaths:[changes.insertedIndexPaths allObjects] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - CKDataSourceListener

- (void)dataSource:(CKDataSource *)dataSource
     didModifyPreviousState:(CKDataSourceState *)previousState
                  withState:(CKDataSourceState *)state
          byApplyingChanges:(CKDataSourceAppliedChanges *)changes
{
  [_announcer dataSourceWillBeginUpdates:self];
  const BOOL changesIncludeNonUpdates = (changes.removedIndexPaths.count ||
                                         changes.insertedIndexPaths.count ||
                                         changes.movedIndexPaths.count ||
                                         changes.insertedSections.count ||
                                         changes.removedSections.count);
  const BOOL changesIncludeOnlyUpdates = (changes.updatedIndexPaths.count && !changesIncludeNonUpdates);
  
  if (changesIncludeOnlyUpdates) {
    // We are not able to animate the updates individually, so we pick the
    // first bounds animation with a non-zero duration.
    CKComponentBoundsAnimation boundsAnimation = {};
    for (NSIndexPath *indexPath in changes.updatedIndexPaths) {
      boundsAnimation = [[state objectAtIndexPath:indexPath] boundsAnimation];
      if (boundsAnimation.duration)
        break;
    }
    
    void (^applyUpdatedState)(CKDataSourceState *) = ^(CKDataSourceState *updatedState) {
      [_tableView performBatchUpdates:^{
        _currentState = updatedState;
      } completion:^(BOOL finished) {
        [_announcer dataSourceDidEndUpdates:self didModifyPreviousState:previousState withState:state byApplyingChanges:changes];
      }];
    };
    
    // We only apply the bounds animation if we found one with a duration.
    // Animating the table view is an expensive operation and should be
    // avoided when possible.
    if (boundsAnimation.duration) {
      id boundsAnimationContext = CKComponentBoundsAnimationPrepareForTableViewBatchUpdates(_tableView, heightChange(previousState, state, changes.updatedIndexPaths));
      [UIView performWithoutAnimation:^{
        applyUpdatedState(state);
      }];
      CKComponentBoundsAnimationApplyAfterTableViewBatchUpdates(boundsAnimationContext, boundsAnimation);
    } else {
      applyUpdatedState(state);
    }
    
    // Within an animation block we directly attach the updated items to
    // their respective cells if visible.
    CKComponentBoundsAnimationApply(boundsAnimation, ^{
      for (NSIndexPath *indexPath in changes.updatedIndexPaths) {
        CKDataSourceItem *item = [state objectAtIndexPath:indexPath];
        CKTableViewDataSourceCell *cell = (CKTableViewDataSourceCell *)[_tableView cellForRowAtIndexPath:indexPath];
        if (cell) {
          attachToCell(cell, item, _attachController, _cellToItemMap);
        }
      }
    }, nil);
  } else if (changesIncludeNonUpdates) {
    [_tableView performBatchUpdates:^{
      applyChangesToTableView(_tableView, _attachController, _cellToItemMap, state, changes);
      // Detach all the component layouts for items being deleted
      [self _detachComponentLayoutForRemovedItemsAtIndexPaths:[changes removedIndexPaths]
                                                      inState:previousState];
      [self _detachComponentLayoutForRemovedSections:[changes removedSections]
                                             inState:previousState];
      // Update current state
      _currentState = state;
    } completion:^(BOOL finished){
      [_announcer dataSourceDidEndUpdates:self didModifyPreviousState:previousState withState:state byApplyingChanges:changes];
    }];
  }
}

static auto heightChange(CKDataSourceState *previousState, CKDataSourceState *state, NSSet *updatedIndexPaths) -> CGFloat
{
  auto change = 0.0;
  for (NSIndexPath *indexPath in updatedIndexPaths) {
    auto const oldHeight = [previousState objectAtIndexPath:indexPath].rootLayout.size().height;
    auto const newHeight = [state objectAtIndexPath:indexPath].rootLayout.size().height;
    change += (newHeight - oldHeight);
  }
  return change;
}

- (void)dataSource:(CKDataSource *)dataSource
  willApplyDeferredChangeset:(CKDataSourceChangeset *)deferredChangeset {}

- (void)_detachComponentLayoutForRemovedItemsAtIndexPaths:(NSSet *)removedIndexPaths
                                                  inState:(CKDataSourceState *)state
{
  for (NSIndexPath *indexPath in removedIndexPaths) {
    CKComponentScopeRootIdentifier identifier = [[[state objectAtIndexPath:indexPath] scopeRoot] globalIdentifier];
    [_attachController detachComponentLayoutWithScopeIdentifier:identifier];
  }
}

- (void)_detachComponentLayoutForRemovedSections:(NSIndexSet *)removedSections inState:(CKDataSourceState *)state
{
  [removedSections enumerateIndexesUsingBlock:^(NSUInteger section, BOOL *stop) {
    [state enumerateObjectsInSectionAtIndex:section
                                 usingBlock:^(CKDataSourceItem *item, NSIndexPath *indexPath, BOOL *stop2) {
       [_attachController detachComponentLayoutWithScopeIdentifier:[[item scopeRoot] globalIdentifier]];
     }];
  }];
}

#pragma mark - State

- (id<NSObject>)modelForItemAtIndexPath:(NSIndexPath *)indexPath
{
  return [_currentState objectAtIndexPath:indexPath].model;
}

- (NSIndexPath *)indexPathForModel:(id)model
{
  __block NSIndexPath *foundIndexPath = nil;
  [_currentState enumerateObjectsUsingBlock:^(CKDataSourceItem *item, NSIndexPath *indexPath, BOOL *stop) {
    if ([item.model isEqual:model]) {
      foundIndexPath = indexPath;
      *stop = YES;
    }
  }];
  return foundIndexPath;
}

- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
  return [_currentState objectAtIndexPath:indexPath].rootLayout.size();
}

- (CGFloat)heightForItemAtIndexPath:(NSIndexPath *)indexPath
{
  return [self sizeForItemAtIndexPath:indexPath].height;
}


#pragma mark - Reload

- (void)reloadWithMode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo
{
  [_componentDataSource setTraitCollection:_tableView.traitCollection];
  [_componentDataSource reloadWithMode:mode userInfo:userInfo];
}

- (void)updateConfiguration:(CKDataSourceConfiguration *)configuration
                       mode:(CKUpdateMode)mode
                   userInfo:(NSDictionary *)userInfo
{
  [_componentDataSource setTraitCollection:_tableView.traitCollection];
  [_componentDataSource updateConfiguration:configuration mode:mode userInfo:userInfo];
}

#pragma mark - Appearance announcements

- (void)announceWillDisplayCell:(UITableViewCell *)cell
{
  CKComponentScopeRootAnnounceControllerAppearance([_cellToItemMap objectForKey:cell].scopeRoot);
}

- (void)announceDidEndDisplayingCell:(UITableViewCell *)cell
{
  CKComponentScopeRootAnnounceControllerDisappearance([_cellToItemMap objectForKey:cell].scopeRoot);
}

#pragma mark - UITableViewDataSource

static NSString *const kReuseIdentifier = @"com.component_kit.table_view_data_source.cell";

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  CKTableViewDataSourceCell *cell = [_tableView dequeueReusableCellWithIdentifier:kReuseIdentifier forIndexPath:indexPath];
  [cell.rootView setAllowTapPassthrough:_allowTapPassthroughForCells];
  attachToCell(cell, [_currentState objectAtIndexPath:indexPath], _attachController, _cellToItemMap);
  [cell.rootView setTransform:tableView.transform];
  return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
  return _currentState ? [_currentState numberOfSections] : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return _currentState ? [_currentState numberOfObjectsInSection:section] : 0;
}

static void attachToCell(CKTableViewDataSourceCell *cell,
                         CKDataSourceItem *item,
                         CKComponentAttachController *attachController,
                         NSMapTable<UITableViewCell *, CKDataSourceItem *> *cellToItemMap)
{
    CKComponentAttachControllerAttachComponentRootLayout(
        attachController,
        {.layoutProvider = item,
         .scopeIdentifier = [item.scopeRoot globalIdentifier],
         .boundsAnimation = item.boundsAnimation,
         .view = cell.rootView,
         .analyticsListener = [item.scopeRoot analyticsListener]});
    [cellToItemMap setObject:item forKey:cell];
}

#pragma mark - Internal

- (void)setAllowTapPassthroughForCells:(BOOL)allowTapPassthroughForCells
{
  CKAssertMainThread();
  _allowTapPassthroughForCells = allowTapPassthroughForCells;
}

- (void)setState:(CKDataSourceState *)state
{
  CKAssertMainThread();
  if (_currentState == state) {
    return;
  }
  
  auto const previousState = _currentState;
  [_announcer dataSource:self willChangeState:previousState];
  _currentState = state;
  
  [_attachController detachAll];
  [_componentDataSource removeListener:self];
  _componentDataSource = [[CKDataSource alloc] initWithState:state];
  [_componentDataSource addListener:self];
  [_tableView reloadData];
  [_announcer dataSource:self didChangeState:previousState withState:state];
}

- (void)addListener:(id<CKTableViewDataSourceListener>)listener
{
  [_announcer addListener:listener];
}

- (void)removeListener:(id<CKTableViewDataSourceListener>)listener
{
  [_announcer removeListener:listener];
}

@end

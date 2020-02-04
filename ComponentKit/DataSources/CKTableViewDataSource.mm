//
//  CKTableViewDataSource.m
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

#import "CKTableViewDataSource.h"

#import <ComponentKit/CKDataSource.h>
#import <ComponentKit/CKDataSourceConfiguration.h>
#import <ComponentKit/CKDataSourceListener.h>
#import <ComponentKit/CKDataSourceState.h>
#import <ComponentKit/CKDataSourceItem.h>
#import <ComponentKit/CKDataSourceAppliedChanges.h>
#import <ComponentKit/CKComponentRootView.h>
#import <ComponentKit/CKComponentLayout.h>
#import <ComponentKit/CKComponentAttachController.h>
#import <ComponentKit/CKComponentControllerEvents.h>
#import <ComponentKit/CKTableViewDataSourceCell.h>
#import <ComponentKit/CKComponentBoundsAnimation+UITableView.h>

@interface CKTableViewDataSource() <UITableViewDataSource, CKDataSourceListener>
{
  CKDataSource *_componentDataSource;
  CKComponentAttachController *_attachController;
  NSMapTable<UITableViewCell *, CKDataSourceItem *> *_cellToItemMap;
}

@property (nonatomic, strong) CKDataSourceState *currentState;

@end

@implementation CKTableViewDataSource

- (instancetype)initWithTableView:(UITableView *)tableView
                         delegate:(id<CKTableViewDataSourceDelegate>)delegate
                    configuration:(CKDataSourceConfiguration *)configuration
{
  self = [super init];
  if (self) {
    _componentDataSource =
    [[CKDataSource alloc]
     initWithConfiguration:configuration];
    [_componentDataSource addListener:self];
    
    _tableView = tableView;
    _tableView.dataSource = self;
    [_tableView
     registerClass:[CKTableViewDataSourceCell class]
     forCellReuseIdentifier:kReuseIdentifier];
    
    _attachController = [[CKComponentAttachController alloc] init];
    _delegate = delegate;
    _cellToItemMap = [NSMapTable weakToStrongObjectsMapTable];
  }
  return self;
}

#pragma mark - Changeset application

- (void)applyChangeset:(CKDataSourceChangeset *)changeset
                  mode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo
{
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
      attachToCell(cell, [currentState objectAtIndexPath:indexPath], attachController, cellToItemMap, YES);
    }
  }];
  
  [tableView
   deleteRowsAtIndexPaths:[changes.removedIndexPaths allObjects]
   withRowAnimation:UITableViewRowAnimationNone];
  
  [tableView
   deleteSections:changes.removedSections
   withRowAnimation:UITableViewRowAnimationNone];
  
  [tableView
   insertSections:changes.insertedSections
   withRowAnimation:UITableViewRowAnimationNone];
  
  for (NSIndexPath *from in changes.movedIndexPaths) {
    NSIndexPath *to = changes.movedIndexPaths[from];
    [tableView deleteRowsAtIndexPaths:@[from] withRowAnimation:UITableViewRowAnimationNone];
    [tableView insertRowsAtIndexPaths:@[to] withRowAnimation:UITableViewRowAnimationNone];
  }
  
  [tableView
   insertRowsAtIndexPaths:[changes.insertedIndexPaths allObjects]
   withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - CKDataSourceListener

- (void)dataSource:(CKDataSource *)dataSource
     didModifyPreviousState:(CKDataSourceState *)previousState
                  withState:(CKDataSourceState *)state
          byApplyingChanges:(CKDataSourceAppliedChanges *)changes
{
  //[_announcer dataSourceWillBeginUpdates:self];
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
      } completion:nil];
    };
    
    // We only apply the bounds animation if we found one with a duration.
    // Animating the collection view is an expensive operation and should be
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
          attachToCell(cell, item, _attachController, _cellToItemMap, YES);
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
    } completion:nil];
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
    [state
     enumerateObjectsInSectionAtIndex:section
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
  [_componentDataSource reloadWithMode:mode userInfo:userInfo];
}

- (void)updateConfiguration:(CKDataSourceConfiguration *)configuration
                       mode:(CKUpdateMode)mode
                   userInfo:(NSDictionary *)userInfo
{
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
                         NSMapTable<UITableViewCell *, CKDataSourceItem *> *cellToItemMap,
                         BOOL isUpdate = NO)
{
  CKComponentAttachControllerAttachComponentRootLayout(attachController, {
    .layoutProvider = item,
    .scopeIdentifier = item.scopeRoot.globalIdentifier,
    .boundsAnimation = item.boundsAnimation,
    .view = cell.rootView,
    .analyticsListener = item.scopeRoot.analyticsListener,
    .isUpdate = isUpdate
  });
  [cellToItemMap setObject:item forKey:cell];
}

@end


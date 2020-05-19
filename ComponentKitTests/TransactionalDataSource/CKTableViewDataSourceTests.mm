/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import <UIKit/UIKit.h>

#import <ComponentKit/CKTableViewDataSource.h>
#import <ComponentKit/CKTableViewDataSourceListener.h>
#import <ComponentKit/CKDataSourceChangeset.h>
#import <ComponentKit/CKDataSourceConfiguration.h>
#import <ComponentKit/CKDataSourceState.h>
#import <ComponentKit/CKDataSourceStateInternal.h>
#import <ComponentKit/CKTableViewDataSourceDelegate.h>
#import <ComponentKit/CKSizeRange.h>

#import <ComponentKit/CKTableViewDataSourceInternal.h>

@interface CKTableViewDataSource () <UITableViewDataSource>
@end

@interface CKTableViewDataSourceSpy : NSObject <CKTableViewDataSourceListener>
@property (nonatomic, assign) NSUInteger willApplyChangeset;
@property (nonatomic, assign) NSUInteger didApplyChangeset;
@property (nonatomic, assign) NSUInteger willChangeState;
@property (nonatomic, assign) NSUInteger didChangeState;
@property (nonatomic, retain) id state;
@property (nonatomic, retain) id previousState;
@end

@interface CKTableViewDataSourceTests : XCTestCase
@property (nonatomic, strong) CKTableViewDataSource *dataSource;
@property (nonatomic, strong) id mockTableView;
@property (nonatomic, strong) id mockTableViewDelegate;
@end

@implementation CKTableViewDataSourceTests

- (void)setUp {
  [super setUp];
  
  self.mockTableViewDelegate = [OCMockObject mockForProtocol:@protocol(CKTableViewDataSourceDelegate)];
  self.mockTableView = [OCMockObject niceMockForClass:[UITableView class]];
  
  CKDataSourceConfiguration *config = [[CKDataSourceConfiguration alloc]
                                       initWithComponentProviderFunc:nullptr
                                       context:nil
                                       sizeRange:CKSizeRange()];
  
  self.dataSource = [[CKTableViewDataSource alloc]
                     initWithTableView:self.mockTableView
                     delegate:self.mockTableViewDelegate
                     configuration:config];
}

- (void)testDataSourceListenerApplyChangeset
{
  OCMStub([self.mockTableView performBatchUpdates:[OCMArg any] completion:[OCMArg any]]).andDo(^(NSInvocation *invocation) {
    void(^block)(BOOL completed);
    [invocation getArgument:&block atIndex:3];
    block(YES);
  });
  
  auto const spy = [CKTableViewDataSourceSpy new];
  [self.dataSource addListener:spy];
  
  [self.dataSource applyChangeset:
   [[[[CKDataSourceChangesetBuilder new]
      withInsertedSections:[NSIndexSet indexSetWithIndex:0]]
     withInsertedItems:@{ [NSIndexPath indexPathForItem:0 inSection:0] : @"" }]
    build] mode:CKUpdateModeSynchronous userInfo:nil];
  
  XCTAssertEqual(spy.willApplyChangeset, 1);
  XCTAssertEqual(spy.didApplyChangeset, 1);
  XCTAssertNotEqual(spy.state, spy.previousState);
}

- (void)testDataSourceListenerSetState
{
  auto const spy = [CKTableViewDataSourceSpy new];
  [self.dataSource addListener:spy];
  
  id configuration = [[CKDataSourceConfiguration alloc] initWithComponentProviderFunc:nullptr context:nil sizeRange:{}];
  id newState = [[CKDataSourceState alloc] initWithConfiguration:configuration sections:@[]];
  
  [self.dataSource setState:newState];
  
  XCTAssertEqual(spy.willChangeState, 1);
  XCTAssertEqual(spy.didChangeState, 1);
  XCTAssertEqual(newState, spy.state);
  XCTAssertNotEqual(newState, spy.previousState);
}

@end

@implementation CKTableViewDataSourceSpy

- (void)dataSourceWillBeginUpdates:(CKTableViewDataSource *)dataSource
{
  _willApplyChangeset++;
}

- (void)dataSourceDidEndUpdates:(CKTableViewDataSource *)dataSource
         didModifyPreviousState:(CKDataSourceState *)previousState
                      withState:(CKDataSourceState *)state
              byApplyingChanges:(CKDataSourceAppliedChanges *)changes
{
  _didApplyChangeset++;
  _previousState = previousState;
  _state = state;
}

- (void)dataSource:(CKTableViewDataSource *)dataSource
   willChangeState:(CKDataSourceState *)state
{
  _willChangeState++;
}

- (void)dataSource:(CKTableViewDataSource *)dataSource
    didChangeState:(CKDataSourceState *)previousState
         withState:(CKDataSourceState *)state
{
  _didChangeState++;
  _previousState = previousState;
  _state = state;
}

@end

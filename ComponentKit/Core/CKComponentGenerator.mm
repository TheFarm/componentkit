/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKComponentGenerator.h"

#import <mutex>

#import <ComponentKit/CKAnalyticsListener.h>
#import <ComponentKit/CKAssert.h>
#import <ComponentKit/CKBuildComponent.h>
#import <ComponentKit/CKComponentController.h>
#import <ComponentKit/CKComponentControllerEvents.h>
#import <ComponentKit/CKComponentControllerHelper.h>
#import <ComponentKit/CKComponentScopeRoot.h>
#import <ComponentKit/CKComponentScopeRootFactory.h>
#import <ComponentKit/CKDelayedInitialisationWrapper.h>
#import <ComponentKit/CKGlobalConfig.h>
#import <ComponentKit/CKSystraceScope.h>
#import <ComponentKit/CKTraitCollectionHelper.h>

static void *kAffinedQueueKey = &kAffinedQueueKey;

#define CKAssertAffinedQueue() CKCAssert(_isRunningOnAffinedQueue(), @"This method must only be called on the affined queue")

struct CKComponentGeneratorInputs {
  CK::NonNull<CKComponentScopeRoot *> scopeRoot;
  CKComponentStateUpdateMap stateUpdates;
  BOOL enableComponentReuse;
  UITraitCollection *traitCollection;

  CKComponentGeneratorInputs(CK::NonNull<CKComponentScopeRoot *> scopeRoot) : scopeRoot(std::move(scopeRoot)) { }

  void updateModel(id<NSObject> model) {
    _didUpdateModelOrContext = _didUpdateModelOrContext || (model != _model);
    _model = model;
  }

  void updateContext(id<NSObject> context) {
    _didUpdateModelOrContext = _didUpdateModelOrContext || (context != _context);
    _context = context;
  }

  id<NSObject> model() const {
    return _model;
  }

  id<NSObject> context() const {
    return _context;
  }

  BOOL didUpdateModelOrContext() const {
    return _didUpdateModelOrContext;
  }

  bool operator==(const CKComponentGeneratorInputs &i) const {
    return scopeRoot == i.scopeRoot &&
      _model == i._model &&
      _context == i._context &&
      stateUpdates == i.stateUpdates &&
      enableComponentReuse == i.enableComponentReuse &&
      _didUpdateModelOrContext == i._didUpdateModelOrContext;
  }

  void reset(CK::NonNull<CKComponentScopeRoot *> newScopeRoot) {
    scopeRoot = newScopeRoot;
    stateUpdates = {};
    _didUpdateModelOrContext = NO;
  }

private:
  id<NSObject> _model;
  id<NSObject> _context;
  BOOL _didUpdateModelOrContext;
};

/**
 This makes sure accessing `inputs` is either thread-safe or affined to a specific queue.
 */
struct CKComponentGeneratorInputsStore {
  CKComponentGeneratorInputsStore(dispatch_queue_t affinedQueue,
                                  CKComponentGeneratorInputs inputs)
  : _affinedQueue(affinedQueue), _inputs(std::move(inputs)) {
    if (_affinedQueue != nil && _affinedQueue != dispatch_get_main_queue()) {
      dispatch_queue_set_specific(_affinedQueue, kAffinedQueueKey, kAffinedQueueKey, NULL);
    }
  }

  template <typename T>
  T acquireInputs(NS_NOESCAPE T(^block)(CKComponentGeneratorInputs &)) {
    if (_affinedQueue) {
      CKAssertAffinedQueue();
      return block(_inputs);
    } else {
      std::lock_guard<std::mutex> lock(_inputsMutex);
      return block(_inputs);
    }
  }
private:
  dispatch_queue_t _affinedQueue;
  std::mutex _inputsMutex;
  CKComponentGeneratorInputs _inputs;

  BOOL _isRunningOnAffinedQueue() const
  {
    if (_affinedQueue == dispatch_get_main_queue()) {
      return [NSThread isMainThread];
    } else {
      return (dispatch_get_specific(kAffinedQueueKey) == kAffinedQueueKey);
    }
  }
};

@interface CKComponentGenerator () <CKComponentStateListener>

@end

@implementation CKComponentGenerator
{
  CKComponentProviderFunc _componentProvider;
  __weak id<CKComponentGeneratorDelegate> _delegate;
  std::unique_ptr<CKComponentGeneratorInputsStore> _inputsStore;
  dispatch_queue_t _affinedQueue;
}

- (instancetype)initWithOptions:(const CKComponentGeneratorOptions &)options
{
  if (self = [super init]) {
    _delegate = options.delegate;
    _componentProvider = options.componentProvider;
    _inputsStore =
    std::make_unique<CKComponentGeneratorInputsStore>(options.affinedQueue,
      CKComponentScopeRootWithPredicates(self,
                                         options.analyticsListener ?: CKReadGlobalConfig().defaultAnalyticsListener,
                                         options.componentPredicates,
                                         options.componentControllerPredicates)
    );
    _affinedQueue = options.affinedQueue;
  }
  return self;
}

- (void)dealloc
{
  const auto scopeRoot = _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs){
    return inputs.scopeRoot;
  });
  const auto invalidateController = ^{
    CKComponentScopeRootAnnounceControllerInvalidation(scopeRoot);
  };
  if ([NSThread isMainThread]) {
    invalidateController();
  } else {
    dispatch_async(dispatch_get_main_queue(), invalidateController);
  }
}

- (void)updateTraitCollection:(UITraitCollection *)traitCollection
{
  _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs) {
    inputs.traitCollection = [traitCollection copy];
  });
}

- (void)updateModel:(id<NSObject>)model
{
  _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs) {
    inputs.updateModel(model);
  });
}

- (void)updateContext:(id<NSObject>)context
{
  _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs) {
    inputs.updateContext(context);
  });
}

- (CKBuildComponentResult)generateComponentSynchronously
{
  return
  _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs) {
    const auto enableComponentReuse = inputs.enableComponentReuse;
    inputs.enableComponentReuse = YES;
    __block CK::DelayedInitialisationWrapper<CKBuildComponentResult> result;
    CKPerformWithCurrentTraitCollection(inputs.traitCollection, ^{
      result = CKBuildComponent(inputs.scopeRoot, inputs.stateUpdates, ^{
        return _componentProvider(inputs.model(), inputs.context());
      }, enableComponentReuse, inputs.didUpdateModelOrContext());
    });
    _applyResult(result,
                 inputs,
                 _addedComponentControllersBetweenScopeRoots(result.get().scopeRoot, inputs.scopeRoot),
                 _invalidComponentControllersBetweenScopeRoots(result.get().scopeRoot, inputs.scopeRoot));
    return result;
  });
}

- (void)generateComponentAsynchronously
{
  const auto inputs = _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &_inputs){
    return std::make_shared<const CKComponentGeneratorInputs>(_inputs);
  });
  const auto asyncGeneration = CK::Analytics::willStartAsyncBlock(CK::Analytics::BlockName::ComponentGeneratorWillGenerate);
  // Avoid capturing `self` in global queue so that `CKComponentGenerator` does not have a chance to be deallocated outside affined queue.
  const auto componentProvider = _componentProvider;
  const auto affinedQueue = _affinedQueue;
  __weak const auto weakSelf = self;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    CKSystraceScope generationScope(asyncGeneration);
    __block std::shared_ptr<const CKBuildComponentResult> result = nullptr;
    CKPerformWithCurrentTraitCollection(inputs->traitCollection, ^{
      result = std::make_shared<const CKBuildComponentResult>(CKBuildComponent(
        inputs->scopeRoot,
        inputs->stateUpdates,
        ^{ return componentProvider(inputs->model(), inputs->context()); },
        inputs->enableComponentReuse,
        inputs->didUpdateModelOrContext()
      ));
    });
    const auto addedComponentControllers =
    std::make_shared<const std::vector<CKComponentController *>>(_addedComponentControllersBetweenScopeRoots(result->scopeRoot, inputs->scopeRoot));
    const auto invalidComponentControllers =
    std::make_shared<const std::vector<CKComponentController *>>(_invalidComponentControllersBetweenScopeRoots(result->scopeRoot, inputs->scopeRoot));
    const auto asyncApplication = CK::Analytics::willStartAsyncBlock(CK::Analytics::BlockName::ComponentGeneratorWillApply);

    const auto applyResult = ^{
      CKSystraceScope applicationScope(asyncApplication);
      const auto strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      if (![strongSelf->_delegate componentGeneratorShouldApplyAsynchronousGenerationResult:strongSelf]) {
        return;
      }
      // If the inputs haven't changed, apply the result; otherwise, retry.
      const auto shouldRetry = strongSelf->_inputsStore->acquireInputs(^(CKComponentGeneratorInputs &_inputs){
        if (_inputs == *inputs) {
          _inputs.enableComponentReuse = YES;
          _applyResult(*result,
                       _inputs,
                       addedComponentControllers != nullptr ? *addedComponentControllers : std::vector<CKComponentController *>{},
                       invalidComponentControllers != nullptr ? *invalidComponentControllers : std::vector<CKComponentController *>{});
          return NO;
        } else {
          return YES;
        }
      });
      if (shouldRetry) {
        [strongSelf generateComponentAsynchronously];
      } else {
        [strongSelf->_delegate componentGenerator:strongSelf didAsynchronouslyGenerateComponentResult:*result];
      }
    };

    if (affinedQueue) {
      dispatch_async(affinedQueue, applyResult);
    } else {
      applyResult();
    }
  });
}

- (void)ignoreComponentReuseInNextGeneration
{
  _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs){
    inputs.enableComponentReuse = NO;
  });
}

- (CKComponentScopeRoot *)scopeRoot
{
  return _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs){
    return inputs.scopeRoot;
  });
}

- (void)setScopeRoot:(CK::NonNull<CKComponentScopeRoot *>)scopeRoot
{
  _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs){
    _notifyInitializationControllerEvents(_addedComponentControllersBetweenScopeRoots(scopeRoot, inputs.scopeRoot));
    _notifyInvalidateControllerEvents(_invalidComponentControllersBetweenScopeRoots(scopeRoot, inputs.scopeRoot));
    inputs.scopeRoot = scopeRoot;
  });
}

#pragma mark - Private

static void _applyResult(const CKBuildComponentResult &result,
                         CKComponentGeneratorInputs &inputs,
                         const std::vector<CKComponentController *> &addedComponentControllers,
                         const std::vector<CKComponentController *> &invalidComponentControllers)
{
  _notifyInitializationControllerEvents(addedComponentControllers);
  _notifyInvalidateControllerEvents(invalidComponentControllers);
  inputs.reset(result.scopeRoot);
}

static void _notifyInvalidateControllerEvents(const std::vector<CKComponentController *> &invalidComponentControllers)
{
  const auto componentControllers = std::make_shared<std::vector<CKComponentController *>>(invalidComponentControllers);
  const auto invalidateControllers = ^{
    for (auto componentController : *componentControllers) {
      [componentController invalidateController];
    }
  };
  if ([NSThread isMainThread]) {
    invalidateControllers();
  } else {
    dispatch_async(dispatch_get_main_queue(), invalidateControllers);
  }
}

static void _notifyInitializationControllerEvents(const std::vector<CKComponentController *> &addedComponentControllers)
{
  const auto componentControllers = std::make_shared<std::vector<CKComponentController *>>(addedComponentControllers);
  const auto didInitControllers = ^{
    for (auto componentController : *componentControllers) {
      [componentController didInit];
    }
  };
  if ([NSThread isMainThread]) {
    didInitControllers();
  } else {
    dispatch_async(dispatch_get_main_queue(), didInitControllers);
  }
}

static std::vector<CKComponentController *> _invalidComponentControllersBetweenScopeRoots(CKComponentScopeRoot *newRoot,
                                                                                          CKComponentScopeRoot *previousRoot)
{
  if (!previousRoot) {
    return {};
  }
  return
  CKComponentControllerHelper::removedControllersFromPreviousScopeRootMatchingPredicate(newRoot,
                                                                                        previousRoot,
                                                                                        &CKComponentControllerInvalidateEventPredicate);
}

static std::vector<CKComponentController *> _addedComponentControllersBetweenScopeRoots(CKComponentScopeRoot *newRoot,
                                                                                        CKComponentScopeRoot *previousRoot)
{
  return CKComponentControllerHelper::addedControllersFromPreviousScopeRootMatchingPredicate(newRoot,
                                                                                             previousRoot,
                                                                                             &CKComponentControllerInitializeEventPredicate);
}

#pragma mark - CKComponentStateListener

- (void)componentScopeHandle:(CKComponentScopeHandle *)handle
              rootIdentifier:(CKComponentScopeRootIdentifier)rootIdentifier
       didReceiveStateUpdate:(id (^)(id))stateUpdate
                    metadata:(const CKStateUpdateMetadata &)metadata
                        mode:(CKUpdateMode)mode
{
  CKAssertMainThread();

  const auto enqueueStateUpdate = ^{
    _inputsStore->acquireInputs(^(CKComponentGeneratorInputs &inputs){
      inputs.stateUpdates[handle].push_back(stateUpdate);
      [[inputs.scopeRoot analyticsListener] didReceiveStateUpdateFromScopeHandle:handle rootIdentifier:rootIdentifier];
    });
    [_delegate componentGenerator:self didReceiveComponentStateUpdateWithMode:mode];
  };
  if (_affinedQueue == dispatch_get_main_queue()) {
    enqueueStateUpdate();
  } else if (!_affinedQueue) {
    // Dispatch to avoid potential deadlock.
    dispatch_async(dispatch_get_main_queue(), enqueueStateUpdate);
  } else {
    dispatch_async(_affinedQueue, enqueueStateUpdate);
  }
}

@end

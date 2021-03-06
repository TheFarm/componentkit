/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */


#ifndef CKTableViewDataSourceDelegate_h
#define CKTableViewDataSourceDelegate_h

#import <Foundation/Foundation.h>

@protocol CKTableViewDataSourceDelegate <NSObject>

- (BOOL)tableView:(UITableView *)tableView
canEditRowAtIndexPath:(NSIndexPath *)indexPath
           object:(id)object;

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath
           object:(id)object;

@end

#endif /* CKTableViewDataSourceDelegate_h */

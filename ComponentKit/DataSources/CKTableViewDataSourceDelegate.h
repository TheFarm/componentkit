//
//  CKTableViewDataSourceDelegate.h
//  ComponentKit
//
//  Created by Fredrik Palm on 2019-08-30.
//

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

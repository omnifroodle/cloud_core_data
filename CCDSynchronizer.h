//
//  CCDSynchronizer.h
//  Cloud Core Data
//
//  Created by Christopher Bradford on 3/1/10.
//  Copyright 2010 INM United. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface CCDSynchronizer : NSObject {
	NSManagedObjectContext *managedObjectContext;
}

@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;

- (void)synchronizeEntities: (NSArray *)entityNames;
- (NSNumber *)getMaxUpdated:(NSString *)entity;

- (id)initWithManagedObjectContext: (NSManagedObjectContext *)context;

@end

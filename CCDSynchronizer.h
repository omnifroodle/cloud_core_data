//
//  CCDSynchronizer.h
//  Cloud Core Data
//
//  Copyright 2010 Matt Overstreet and Christopher Bradford.  All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface CCDSynchronizer : NSObject {
	NSManagedObjectContext *managedObjectContext;
	NSString *server;
}

@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain, readonly) NSString *server;

- (void)synchronizeEntities: (NSDictionary *)entityPayload;
- (NSNumber *)getMaxUpdated:(NSString *)entity;

- (id)initWithManagedObjectContext: (NSManagedObjectContext *)context onServer: (NSString *)remote;

@end

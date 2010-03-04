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
	
	id delegate;
}

@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain, readonly) NSString *server;
@property (nonatomic, assign) id delegate;

- (void)synchronizeEntities: (NSDictionary *)entityPayload inParallel: (BOOL)parallel;
- (NSNumber *)getMaxUpdated:(NSString *)entity;

- (id)initWithManagedObjectContext: (NSManagedObjectContext *)context onServer: (NSString *)remote;

@end
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
	NSString *source_root;
	
	NSMutableArray *proceduralEntities;
	NSMutableSet *parallelEntities;
	
	id delegate;
}

@property (nonatomic, retain) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain) NSString *source_root;
@property (nonatomic, assign) id delegate;

- (void)synchronizeEntities;
- (void)synchronizeParallelEntities;
- (void)synchronizeProceduralEntities;
- (void) synchronizeEntity:(NSDictionary *)entity inParallel:(BOOL)parallel;

- (NSNumber *)getMaxUpdated:(NSString *)entity;

- (void)addEntity:(NSString *)entityName atPath:(NSString *)path inParallel:(BOOL)parallel;
- (void)addProceduralEntity:(NSString *)entityName atPath:(NSString *)path;
- (void)addParallelEntity:(NSString *)entityName atPath:(NSString *)path;

@end
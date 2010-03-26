//
//  CCDSynchronizer.m
//  Cloud Core Data
//
//  Copyright 2010 Matt Overstreet and Christopher Bradford.  All rights reserved.
//

#import "CCDSynchronizer.h"
#import "CCDSynchronizerDelegate.h"

@implementation CCDSynchronizer

#pragma mark -
#pragma mark Synthesized Properties

@synthesize managedObjectContext;
@synthesize source_root;
@synthesize delegate;

#pragma mark -
#pragma mark Sort Function

NSInteger intSort(id num1, id num2, void *context)
{
    int v1 = [num1 intValue];
    int v2 = [num2 intValue];
    if (v1 < v2)
        return NSOrderedAscending;
    else if (v1 > v2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}

#pragma mark -
#pragma mark Entity Management Methods

- (void)addEntity:(NSString *)entityName atPath:(NSString *)path inParallel:(BOOL)parallel {
	if (parallel) {
		[self addParallelEntity:entityName atPath:path];
	}
	else {
		[self addProceduralEntity:entityName atPath:path];
	}
}

- (void)addParallelEntity:(NSString *)entityName atPath:(NSString *)path {
	[parallelEntities addObject:[NSDictionary dictionaryWithObjectsAndKeys: entityName, @"entityName", path, @"entityPath", nil]];
}

- (void)addProceduralEntity:(NSString *)entityName atPath:(NSString *)path {
	[proceduralEntities addObject:[NSDictionary dictionaryWithObjectsAndKeys: entityName, @"entityName", path, @"entityPath", nil]];
}

#pragma mark -
#pragma mark Synchronization Methods

- (void)synchronizeEntities {
	// Start synchronizing parallel entities
	[self synchronizeParallelEntities];
	
	// Start synchronizing procedural entities
	[self synchronizeProceduralEntities];
}

- (void)synchronizeParallelEntities {
	// Traverse the set and start spinning of threads
	NSEnumerator *enumerator = [parallelEntities objectEnumerator];
	
	NSDictionary *entity;
	while (entity = (NSDictionary *)[enumerator nextObject]) {
		[self synchronizeEntity: entity inParallel: YES];
	}
}

- (void)synchronizeProceduralEntities {
	if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:willSynchronizeProceduralEntities:)]) {
		[(id<CCDSynchronizerDelegate>)delegate synchronizer: self willSynchronizeProceduralEntities: proceduralEntities];
	}
	
	NSDictionary *entity = (NSDictionary *)[proceduralEntities lastObject];
	
	if (entity != nil) {
		[proceduralEntities removeLastObject];
		[self synchronizeEntity: entity inParallel:NO];
	}
	else {
		if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:didSynchronizeProceduralEntities:)]) {
			[(id<CCDSynchronizerDelegate>)delegate synchronizer: self didSynchronizeProceduralEntities: proceduralEntities];
		}
	}
}

- (void)synchronizeEntity:(NSDictionary *)entity inParallel: (BOOL)parallel {
	NSMutableDictionary *entityPayload = [NSMutableDictionary dictionaryWithDictionary:entity];
	NSString *entityName = [entity objectForKey:@"entityName"];
	
	// Retrieve the max updated timestamp
	[entityPayload setObject:[self getMaxUpdated:entityName] forKey:@"maxUpdated"];
	NSLog(@"Entity: %@, Max Updated: %@", entityName, [entityPayload objectForKey:@"maxUpdated"]);
	
	// Spin off a thread to pull the updated items
	if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:willSynchronizeEntity:)]) {
		[(id<CCDSynchronizerDelegate>)delegate synchronizer: self willSynchronizeEntity: entityName];
	}
	
	if (parallel) {
		[NSThread detachNewThreadSelector: @selector(fetchEntity:)
								 toTarget: self withObject: entityPayload];
	}
	else {
		[self performSelectorOnMainThread:@selector(fetchEntity:) withObject:entityPayload waitUntilDone:YES];
	}
}

- (void)fetchEntity:(id)payload {
	NSDictionary *syncData = (NSDictionary *) payload;
	
    NSAutoreleasePool *entityPool = [[NSAutoreleasePool alloc] init];
	
	// Fetch the updated entries
	NSLog(@"Fetching %@ Entries", (NSString *)[syncData objectForKey:@"entityName"]);
	NSDictionary *entityData = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@?last=%d", self.source_root, (NSString *)[syncData objectForKey:@"entityPath"], [(NSNumber *)[syncData objectForKey:@"maxUpdated"] intValue]]]];
	
	// Return back to the main thread to update data
	NSDictionary *updatePayload = [NSDictionary dictionaryWithObjectsAndKeys:[syncData objectForKey:@"entityName"], @"entityName", entityData, @"entityData", nil];
	[self performSelectorOnMainThread:@selector(updateEntityData:) withObject:updatePayload waitUntilDone:YES];
	
	// Drain the pool and stop the thread
	[entityPool drain];
	[entityPool release];
	
	// If we are performing the tasks on the MainThread
	if(![NSThread isMainThread]) {
		[NSThread exit];
	}
	else {
		[self synchronizeProceduralEntities];
	}
}

- (void)updateEntityData:(id)updatePayload {
	NSDictionary *entityPayload = (NSDictionary *)updatePayload;
	NSDictionary *remoteEntities = [entityPayload objectForKey:@"entityData"];
	
	// If there are no records to process, do not continue
	if (remoteEntities == nil) {
		return;
	}
	
	// Retrieve a list of all of the Entity IDs for use in the search predicate
	NSArray *remoteEntityIDs = [[remoteEntities allKeys] sortedArrayUsingFunction:intSort context:NULL];
	
	// Build the fetch request to retrieve the items that exist locally
	NSFetchRequest *localFetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	NSEntityDescription *entity = [NSEntityDescription entityForName:[entityPayload objectForKey:@"entityName"] inManagedObjectContext:managedObjectContext];
	[localFetchRequest setEntity: entity];
	[localFetchRequest setPredicate: [NSPredicate predicateWithFormat: @"(ccd_remote_id IN %@)", remoteEntityIDs]];
	[localFetchRequest setSortDescriptors: [NSArray arrayWithObject: [[[NSSortDescriptor alloc] initWithKey: @"ccd_remote_id" ascending:YES] autorelease]]];
	
	// Perform the fetch request
	NSError *error;
	NSArray *localEntities = [managedObjectContext executeFetchRequest:localFetchRequest error:&error];
	
	// Create Iterators to walk through the entities and perform the necessary actions (create, update, delete)
	NSEnumerator *remoteEntityIDIterator = [remoteEntityIDs objectEnumerator];
	NSEnumerator *localEntityIterator = [localEntities objectEnumerator];
	
	// Create "walker" values, values that change as we iterate over the loaded data
	NSManagedObject *localEntity = (NSManagedObject *)[localEntityIterator nextObject];
	NSNumber *remoteEntityID;
	NSManagedObject *newLocalEntity;
	
	NSLog(@"Updating %@ Entities", [entityPayload objectForKey:@"entityName"]);
	
	// Loop over the remote Entity IDs, if the item exists locally update it, if not create the local Entity
	while (remoteEntityID = (NSNumber *)[remoteEntityIDIterator nextObject]) {
		NSMutableDictionary *remoteEntityData = [remoteEntities objectForKey: remoteEntityID];
		
		// Check to see if the current local entity matches our current remote entity
		if (localEntity != nil && [remoteEntityID intValue] == [(NSNumber *)[localEntity valueForKey:@"ccd_remote_id"] intValue]) {
			// The entity IDs match, determine if we should update or delete
			if ([[remoteEntityData objectForKey:@"deleted"] boolValue]) {
				NSLog(@"Deleting %@: %@", [entityPayload objectForKey:@"entityName"], remoteEntityID);
				
				// Delete the local Entity
				if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:willSynchronizeEntity:element:withAction:)]) {
					[(id<CCDSynchronizerDelegate>)delegate synchronizer: self willSynchronizeEntity: [entityPayload objectForKey:@"entityName"] element:localEntity withAction:@"Delete"];
				}
				
				[managedObjectContext deleteObject:localEntity];
				
				if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:didSynchronizeEntity:element:withAction:)]) {
					[(id<CCDSynchronizerDelegate>)delegate synchronizer: self didSynchronizeEntity: [entityPayload objectForKey:@"entityName"] element:nil withAction:@"Delete"];
				}
			}
			else {
				NSLog(@"Updating %@: %@", [entityPayload objectForKey:@"entityName"], remoteEntityID);
				
				// Remove the "deleted" key and update the local Entity
				if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:willSynchronizeEntity:element:withAction:)]) {
					[(id<CCDSynchronizerDelegate>)delegate synchronizer: self willSynchronizeEntity: [entityPayload objectForKey:@"entityName"] element:localEntity withAction:@"Update"];
				}
				
				[remoteEntityData removeObjectForKey:@"deleted"];
				[localEntity setValuesForKeysWithDictionary:remoteEntityData];
				
				if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:didSynchronizeEntity:element:withAction:)]) {
					[(id<CCDSynchronizerDelegate>)delegate synchronizer: self didSynchronizeEntity: [entityPayload objectForKey:@"entityName"] element:localEntity withAction:@"Update"];
				}
			}
			
			// Retrieve the next local Entity to check against
			localEntity = [localEntityIterator nextObject];
		}
		else if (![[remoteEntityData objectForKey:@"deleted"] boolValue]) {
			NSLog(@"Creating %@: %@", [entityPayload objectForKey:@"entityName"], remoteEntityID);
			
			// Create the new local Entity
			[remoteEntityData removeObjectForKey:@"deleted"];
			newLocalEntity = [[NSManagedObject alloc] initWithEntity:entity 
									  insertIntoManagedObjectContext:managedObjectContext];
			
			if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:willSynchronizeEntity:element:withAction:)]) {
				[(id<CCDSynchronizerDelegate>)delegate synchronizer: self willSynchronizeEntity: [entityPayload objectForKey:@"entityName"] element:newLocalEntity withAction:@"Create"];
			}
			
			[newLocalEntity setValuesForKeysWithDictionary:remoteEntityData];
			
			if (delegate != nil && [delegate respondsToSelector:@selector(synchronizer:didSynchronizeEntity:element:withAction:)]) {
				[(id<CCDSynchronizerDelegate>)delegate synchronizer: self didSynchronizeEntity: [entityPayload objectForKey:@"entityName"] element:newLocalEntity withAction:@"Create"];
			}
			
			[newLocalEntity release];
		}

	}
	
	NSLog(@"Finished Updating %@ Entities", [entityPayload objectForKey:@"entityName"]);
	
	// Actions are complete tell the persistent store to save the changes
	if (![managedObjectContext save: &error]) {
		NSLog(@"Could not save updates to the persistant store. Error: %@", error);
	}
}

- (NSNumber *)getMaxUpdated:(NSString *)entityName {
	int result = 0;
	
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:managedObjectContext];
	[request setEntity:entity];
	
	// Specify that the request should return dictionaries.
	[request setResultType:NSDictionaryResultType];
	
	// Create an expression for the key path.
	NSExpression *keyPathExpression = [NSExpression expressionForKeyPath:@"updated"];
	
	// Create an expression to represent the max value at the key path 
	NSExpression *maxExpression = [NSExpression expressionForFunction:@"max:" arguments:[NSArray arrayWithObject:keyPathExpression]];
	
	// Create an expression description using the minExpression and returning a date.
	NSExpressionDescription *expressionDescription = [[NSExpressionDescription alloc] init];
	
	// The name is the key that will be used in the dictionary for the return value.
	[expressionDescription setName:@"maxUpdated"];
	[expressionDescription setExpression:maxExpression];
	[expressionDescription setExpressionResultType:NSInteger64AttributeType];
	
	// Set the request's properties to fetch just the property represented by the expressions.
	[request setPropertiesToFetch:[NSArray arrayWithObject:expressionDescription]];
	
	// Execute the fetch.
	NSError *error;
	NSArray *objects = [managedObjectContext executeFetchRequest:request error:&error];
	if (objects == nil) {
		// Handle the error.
		
	} else {
		if ([objects count] > 0) {
			result = [[[objects objectAtIndex:0] valueForKey:@"maxUpdated"] intValue];
		}
	}
	
	[expressionDescription release];
	[request release];
	return [NSNumber numberWithInt:result];
}

#pragma mark -
#pragma mark NSObject Methods

- (id)init {
	self = [super init];
	
	if (self != nil) {
		managedObjectContext = nil;
		source_root = nil;
		
		parallelEntities = [[NSMutableSet alloc] init];
		proceduralEntities = [[NSMutableArray alloc] init];
	}
	
	return self;
}

- (void)dealloc {
	[managedObjectContext release];
	[source_root release];
	
	[parallelEntities release];
	[proceduralEntities release];
	
	[super dealloc];
}

@end

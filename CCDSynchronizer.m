//
//  CCDSynchronizer.m
//  Cloud Core Data
//
//  Copyright 2010 Matt Overstreet and Christopher Bradford.  All rights reserved.
//

#import "CCDSynchronizer.h"


@implementation CCDSynchronizer

#pragma mark -
#pragma mark Synthesized Properties

@synthesize managedObjectContext;
@synthesize server;

#pragma mark -
#pragma mark Synchronization Methods

- (void)synchronizeEntities: (NSDictionary *)entityPayload {
	NSEnumerator *entityEnumerator = [[entityPayload allKeys] objectEnumerator];
	
	NSString *entityName;
	while (entityName = (NSString *)[entityEnumerator nextObject]) {
		// Retrieve the max updated timestamp
		NSNumber *maxUpdated = [self getMaxUpdated:entityName];
		NSLog(@"Entity: %@, Max Updated: %@", entityName, maxUpdated);
		
		NSDictionary *threadPayload = [NSDictionary dictionaryWithObjectsAndKeys:entityName, @"entityName", maxUpdated, @"maxUpdated", [entityPayload objectForKey:entityName], @"entityURL", nil];
		
		// Spin off a thread to pull the updated items
		[NSThread detachNewThreadSelector: @selector(synchronizeEntity:)
								 toTarget: self withObject: threadPayload];
	}
}

-(void) synchronizeEntity:(id)payload {
	NSDictionary *syncData = (NSDictionary *) payload;
	
    NSAutoreleasePool *entityPool = [[NSAutoreleasePool alloc] init];
	
	// Fetch the updated entries
	NSLog(@"Fetching %@ Entries", (NSString *)[syncData objectForKey:@"entityName"]);
	NSDictionary *entityData = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@%@?last=%d", self.server, (NSString *)[syncData objectForKey:@"entityURL"], [(NSNumber *)[syncData objectForKey:@"maxUpdated"] intValue]]]];
	
	// Return back to the main thread to update data
	NSDictionary *updatePayload = [NSDictionary dictionaryWithObjectsAndKeys:[syncData objectForKey:@"entityName"], @"entityName", entityData, @"entityData", nil];
	[self performSelectorOnMainThread:@selector(updateEntityData:) withObject:updatePayload waitUntilDone:YES];
	
	// Drain the pool and stop the thread
	[entityPool drain];
	[entityPool release];
	
    [NSThread exit];
}

- (void)updateEntityData:(id)updatePayload {
	NSDictionary *entityPayload = (NSDictionary *)updatePayload;
	NSDictionary *remoteEntities = [entityPayload objectForKey:@"entityData"];
	
	// If there are no records to process, do not continue
	if (remoteEntities == nil) {
		return;
	}
	
	// Retrieve a list of all of the Entity IDs for use in the search predicate
	NSArray *remoteEntityIDs = [[remoteEntities allKeys] sortedArrayUsingSelector:@selector(compare:)];
	
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
				[managedObjectContext deleteObject:localEntity];
			}
			else {
				NSLog(@"Updating %@: %@", [entityPayload objectForKey:@"entityName"], remoteEntityID);
				
				// Remove the "deleted" key and update the local Entity
				[remoteEntityData removeObjectForKey:@"deleted"];
				[localEntity setValuesForKeysWithDictionary:remoteEntityData];
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
			[newLocalEntity setValuesForKeysWithDictionary:remoteEntityData];
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

- (id)initWithManagedObjectContext: (NSManagedObjectContext *)context onServer: (NSString *)remoteServer {
	self = [self init];
	
	if (self != nil) {
		managedObjectContext = context;
		server = remoteServer;
	}
	
	return self;
}

- (id)init {
	self = [super init];
	
	if (self != nil) {
		managedObjectContext = nil;
		server = nil;
	}
	
	return self;
}

- (void)dealloc {
	[managedObjectContext release];
	
	[super dealloc];
}

@end

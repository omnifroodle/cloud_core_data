//
//  CCDSynchronizer.m
//  Cloud Core Data
//
//  Created by Christopher Bradford on 3/1/10.
//  Copyright 2010 INM United. All rights reserved.
//

#import "CCDSynchronizer.h"


@implementation CCDSynchronizer

#pragma mark -
#pragma mark Synthesized Properties

@synthesize managedObjectContext;
@synthesize server;

#pragma mark -
#pragma mark Synchronization Methods

// This needs to appear before being referenced later
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

- (void)synchronizeEntities: (NSArray *)entityNames {
	NSEnumerator *entityEnumerator = [entityNames objectEnumerator];
	
	NSString *entityName;
	while (entityName = (NSString *)[entityEnumerator nextObject]) {
		// Retrieve the max updated timestamp
		NSNumber *maxUpdated = [self getMaxUpdated:entityName];
		NSLog(@"Entity: %@, Max Updated: %@", entityName, maxUpdated);
		
		NSDictionary *threadPayload = [NSDictionary dictionaryWithObjectsAndKeys:entityName, @"entityName", maxUpdated, @"maxUpdated", nil];
		
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
	NSDictionary *entityData = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@/%@.plist?last=%d", self.server, (NSString *)[syncData objectForKey:@"entityName"], [(NSNumber *)[syncData objectForKey:@"maxUpdated"] intValue]]]];
	
	// Return back to the main thread to update data
	NSDictionary *updatePayload = [NSDictionary dictionaryWithObjectsAndKeys:[syncData objectForKey:@"entityName"], @"entityName", entityData, @"entityData", nil];
	[self performSelectorOnMainThread:@selector(updateEntityData:) withObject:updatePayload waitUntilDone:YES];
	
	// Drain the pool and stop the thread
	[entityPool drain];
	[entityPool release];
	
    [NSThread exit];
}

- (void)updateEntityData:(id)updatePayload {
	if (updatePayload == nil) {
		return;
	}
	
	NSDictionary *updateDictionary = (NSDictionary *)updatePayload;
	if ([updateDictionary objectForKey:@"entityData"] == nil) {
		return;
	}
	
	NSLog(@"Updating %@ Entities", [updateDictionary objectForKey:@"entityName"]);
	
	NSDictionary *updatedEntityData = [updateDictionary objectForKey:@"entityData"];
	
	NSArray *updatedEntityIDs = [[updatedEntityData allKeys]
						  sortedArrayUsingFunction:intSort context:NULL];
	
	// create the fetch request to get all Stories matching the IDs
	[self managedObjectContext];
	NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	NSEntityDescription *entity = [NSEntityDescription entityForName:[updateDictionary objectForKey:@"entityName"] inManagedObjectContext:managedObjectContext];
	[fetchRequest setEntity: entity];
	[fetchRequest setPredicate: [NSPredicate predicateWithFormat: @"(cdc_master_id IN %@)", updatedEntityIDs]];
	
	// make sure the results are sorted as well
	[fetchRequest setSortDescriptors: [NSArray arrayWithObject:
									   [[[NSSortDescriptor alloc] initWithKey: @"cdc_master_id"
																	ascending:YES] autorelease]]];
	NSError *error;
	NSArray *matchedEntities = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
	
	NSEnumerator *updatedIterator = [updatedEntityIDs objectEnumerator];
	NSEnumerator *localIterator = [matchedEntities objectEnumerator];
	
	// iterate though the sorted arrays updating existing records or adding new ones
	NSManagedObject *mo = [localIterator nextObject];
	
	NSNumber *entityID;
	NSManagedObject *newMo;
	
	while (entityID = (NSNumber *)[updatedIterator nextObject]) {
		NSMutableDictionary *validEntityData;
		
		if ((mo != nil) && ([entityID intValue] == [[mo valueForKey: @"cdc_master_id"] intValue])) {
			if ([[validEntityData valueForKey: @"deleted"] boolValue]) {
				// Entity Instance has been deleted
				NSLog(@"Deleting %@: %@", [updateDictionary objectForKey:@"entityName"], entityID);
				
				[self.managedObjectContext deleteObject: mo];
			}
			else {
				// Update the recipe
				NSLog(@"Updating %@: %@", [updateDictionary objectForKey:@"entityName"], entityID);
				// update the recipe with the new version
				[mo setValuesForKeysWithDictionary:validEntityData];
				mo = [localIterator nextObject];				
			}
		} else if(![[validEntityData valueForKey: @"deleted"] boolValue]) {
			// Create the new entity instance
			NSLog(@"Creating %@: %@", [updateDictionary objectForKey:@"entityName"], entityID);
			newMo = [[NSManagedObject alloc] initWithEntity:entity
							 insertIntoManagedObjectContext:managedObjectContext];
			
			[newMo setValuesForKeysWithDictionary:[updatedEntityData objectForKey:entityID]];
			
			[newMo release];
		}
	}
	
	// Updates have been performed update the persistant store
	if (![self.managedObjectContext save: &error]) {
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

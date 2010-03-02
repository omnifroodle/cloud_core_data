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

#pragma mark -
#pragma mark Synchronization Methods


- (void)synchronizeEntities: (NSArray *)entityNames {
	NSEnumerator *entityEnumerator = [entityNames objectEnumerator];
	
	NSString *entityName;
	while (entityName = (NSString *)[entityEnumerator nextObject]) {
		NSNumber *maxUpdated = [self getMaxUpdated:entityName];
		NSLog(@"Entity: %@, Updated: %@", entityName, maxUpdated);
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

/*NSInteger intSort(id num1, id num2, void *context)
{
    int v1 = [num1 intValue];
    int v2 = [num2 intValue];
    if (v1 < v2)
        return NSOrderedAscending;
    else if (v1 > v2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;
}*/

#pragma mark -
#pragma mark NSObject Methods

- (id)initWithManagedObjectContext: (NSManagedObjectContext *)context {
	self = [self init];
	
	if (self != nil) {
		managedObjectContext = context;
	}
	
	return self;
}

- (id)init {
	self = [super init];
	
	if (self != nil) {
		managedObjectContext = nil;
	}
	
	return self;
}

- (void)dealloc {
	[managedObjectContext release];
	
	[super dealloc];
}

@end

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

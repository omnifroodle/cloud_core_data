//
//  CCDSynchronizerDelegate.h
//  Cloud Core Data
//
//  Copyright 2010 Matt Overstreet and Christopher Bradford. All rights reserved.
//

#import "CCDSynchronizer.h"

@protocol CCDSynchronizerDelegate
@optional
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer willSynchronizeProceduralEntities: (NSArray *)entities;
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer didSynchronizeProceduralEntities: (NSArray *)entities;
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer willSynchronizeEntity:(NSString *)entityName element:(NSManagedObject *)element withAction:(NSString *)action;
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer didSynchronizeEntity:(NSString *)entityName element:(NSManagedObject *)element withAction:(NSString *)action;
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer willSynchronizeEntity:(NSString *)entityName;
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer didSynchronizeEntity:(NSString *)entityName;
@end
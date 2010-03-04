//
//  CCDSynchronizerDelegate.h
//  Cloud Core Data
//
//  Copyright 2010 Matt Overstreet and Christopher Bradford. All rights reserved.
//

@protocol CCDSynchronizerDelegate
@optional
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer willSynchronizeEntity:(NSString *)entityName;
- (void)synchronizer:(CCDSynchronizer *)ccdSynchronizer didSynchronizeEntity:(NSString *)entityName;
@end
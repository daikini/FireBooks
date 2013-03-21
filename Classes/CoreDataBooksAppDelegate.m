
/*
     File: CoreDataBooksAppDelegate.m
 Abstract: Application delegate to set up the Core Data stack and configure the first view and navigation controllers.
  Version: 2
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2012 Apple Inc. All Rights Reserved.
 
 */

#import "CoreDataBooksAppDelegate.h"
#import "RootViewController.h"
#import <Firebase/Firebase.h>
#import <FireData/FireData.h>

@interface CoreDataBooksAppDelegate ()

@property (nonatomic, strong, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong) FireData *firedata;

- (NSURL *)applicationDocumentsDirectory;
- (void)saveContext;

@end



@implementation CoreDataBooksAppDelegate

@synthesize window=_window;
@synthesize managedObjectModel=_managedObjectModel, managedObjectContext=_managedObjectContext, persistentStoreCoordinator=_persistentStoreCoordinator;


#pragma mark -
#pragma mark Application lifecycle

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
    RootViewController *rootViewController = (RootViewController *)[[navigationController viewControllers] objectAtIndex:0];
    rootViewController.managedObjectContext = self.managedObjectContext;
        
    // Initialize an instance of FireData
    FireData *firedata = [[FireData alloc] init];
    
    // Listen for changes from the default managed object context
    [firedata observeManagedObjectContext:self.managedObjectContext];
    
    // Create a new managed object context to write changes from Firebase; set its parent to the default managed object context.
    NSManagedObjectContext *writingContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [writingContext setParentContext:self.managedObjectContext];
    [firedata setWriteManagedObjectContext:writingContext withCompletionBlock:^(NSManagedObjectContext *context) {
        [context performBlockAndWait:^{
            NSError *error = nil;
            if ([context save:&error]) {
                if (![self.managedObjectContext save:&error]) {
                    NSLog(@"Error saving: %@", error);
                }
            } else {
                NSLog(@"Error saving: %@", error);
            }
        }];
    }];
    
    
//
// Remove the line that starts with `#error` after you have filled
// in your Firebase URL.
//
#error You need to fill in your Firebase URL
    
    // Get a reference to Firebase
    Firebase *firebase = [[Firebase alloc] initWithUrl:@"https://EXAMPLE.firebaseio.com/"];
    
    // Link the `Book` Core Data entity and the `books` Firebase reference
    [firedata linkCoreDataEntity:@"Book" withFirebase:[firebase childByAppendingPath:@"books"]];
    
    // Check the existing data in Firebase
    [firebase observeSingleEventOfType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot) {
        // If Firebase is empty then replace with the data from Core Data
        if (snapshot.value == [NSNull null]) {
            // Add the firebaseKey to the existing books if it's not already been added
            NSPersistentStore *store = [[self persistentStoreCoordinator] persistentStoreForURL:[self persistentStoreURL]];
            NSMutableDictionary *storeMetaData = [[store metadata] mutableCopy];
            if (![[storeMetaData objectForKey:@"AddedFirebaseKey"] boolValue]) {
                NSManagedObjectContext *migrationContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
                [migrationContext setParentContext:self.managedObjectContext];
                
                NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
                [fetchRequest setFetchBatchSize:25];
                NSArray *books = [migrationContext executeFetchRequest:fetchRequest error:nil];
                [books enumerateObjectsUsingBlock:^(NSManagedObject *book, NSUInteger idx, BOOL *stop) {
                    [book setValue:[FireData firebaseKey] forKey:@"firebaseKey"];
                }];
                
                NSError *error = nil;
                if ([migrationContext save:&error]) {
                    [storeMetaData setObject:@(YES) forKey:@"AddedFirebaseKey"];
                    [store setMetadata:storeMetaData];
                } else {
                    NSLog(@"Error adding firebaseKeys: %@", error);
                }
            }
            
            [firedata replaceFirebaseFromCoreData];
        }
        
        // Start observing changes between Core Data and Firebase
        [firedata startObserving];
    }];
    
    // Hold on to FireData
    self.firedata = firedata;
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    [self saveContext];
}


- (void)applicationWillResignActive:(UIApplication *)application
{
    [self saveContext];
}


- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self saveContext];
}


- (void)saveContext
{
    NSError *error;
    if (_managedObjectContext != nil) {
        if ([_managedObjectContext hasChanges] && ![_managedObjectContext save:&error]) {
            /*
             Replace this implementation with code to handle the error appropriately.
     
             abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
             */
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        } 
    }
}


#pragma mark -
#pragma mark Core Data stack

/*
 Returns the managed object context for the application.
 If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
 */
- (NSManagedObjectContext *) managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [_managedObjectContext setPersistentStoreCoordinator: coordinator];
    }
    return _managedObjectContext;
}


// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"CoreDataBooks" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

/*
 Returns the persistent store url
 */
- (NSURL *)persistentStoreURL
{
    return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"CoreDataBooks.CDBStore"];
}

/*
 Returns the persistent store coordinator for the application.
 If the coordinator doesn't already exist, it is created and the application's store added to it.
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }

    NSURL *storeURL = [self persistentStoreURL];

    /*
     Set up the store.
     For the sake of illustration, provide a pre-populated default store.
     */
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // If the expected store doesn't exist, copy the default store.
    if (![fileManager fileExistsAtPath:[storeURL path]]) {
        NSURL *defaultStoreURL = [[NSBundle mainBundle] URLForResource:@"CoreDataBooks" withExtension:@"CDBStore"];
        if (defaultStoreURL) {
            [fileManager copyItemAtURL:defaultStoreURL toURL:storeURL error:NULL];
        }
    }

    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: [self managedObjectModel]];

    NSError *error;
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }

    return _persistentStoreCoordinator;
}


#pragma mark -
#pragma mark Application's documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}


@end

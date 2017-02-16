//
//  DDRCoreDataDocument.swift
//  DDRCoreDataKit
//
//  Created by David Reed on 6/19/15.
//  Copyright © 2015 David Reed. All rights reserved.
//


#if os(iOS)
    import UIKit
#endif

import CoreData

public enum DDRCoreDataSaveOrError {
    case saveOkHadChanges(Bool) // Bool indicates if saved changes to persistentStore (i.e., hasChanges was true)
    case error(NSError)
    case errorString(String)
}


public typealias DDRCoreDataDocumentCompletionClosure = (_ status: DDRCoreDataSaveOrError, _ doc: DDRCoreDataDocument?) -> Void



/**
class for accessing a Core Data Store

uses two NSManagedObjectContext
one context of type PrivateQueueConcurrencyType is used for saving to the store to avoid blocking the main thread; this context is private to the class

the mainQueueMOC is a child context of the private context and is intended for use with the GUI

also provices a method to get a child context of this main thread

the saveContext method saves from the mainQueueMOC to the private context and to the persistent store

a combination of ideas from Zarra's book and this blog post

http://martiancraft.com/blog/2015/03/core-data-stack/

*/
open class DDRCoreDataDocument {

    /// the main thread/queue NSManagedObjectContext that should be used
    open let mainQueueMOC : NSManagedObjectContext!


    fileprivate let managedObjectModel : NSManagedObjectModel!
    fileprivate let persistentStoreCoordinator : NSPersistentStoreCoordinator!
    fileprivate let storeURL : URL!

    // private data
    fileprivate var privateMOC : NSManagedObjectContext! = nil

    /// create a DDRCoreDataDocument with two contexts; will fail (return nil) if cannot create the persistent store
    ///
    /// - parameter storeURL: NSURL for the SQLite store; pass nil to use an in memory store
    /// - parameter modelURL: NSURL for the CoreData object model (i.e., URL to the .momd file package/directory)
    /// - parameter options: to pass when creating the persistent store coordinator; if pass nil, it uses [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true] for automatic migration; pass an empty dictionary [ : ] if want no options
    public init?(storeURL: URL?, modelURL: URL, options : [AnyHashable: Any]! = nil) {

        // try to read model file
        managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)

        // return nil if unable to
        guard managedObjectModel != nil else {
            persistentStoreCoordinator = nil
            mainQueueMOC = nil
            privateMOC = nil
            self.storeURL = nil
            return nil
        }

        persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)

        let storeType : String = (storeURL != nil) ? NSSQLiteStoreType : NSInMemoryStoreType
        var localURL = storeURL

        // if not an in memory store
        if storeType != NSInMemoryStoreType {
            var value: AnyObject?
            var isDirectory = false
            // check if URL is a directory
            if storeType != NSInMemoryStoreType {
                // check if URL is a directory
                do {
                    try (localURL! as NSURL).getResourceValue(&value, forKey: URLResourceKey.isDirectoryKey)
                    isDirectory = value!.boolValue
                } catch {
                    isDirectory = false
                }

                // if it is a directory, try looking in directory for StoreContent/persistentStore as that is what UIManagedDocument uses
                if isDirectory {
                    localURL = localURL?.appendingPathComponent("StoreContent").appendingPathComponent("persistentStore")
                }
            }
        }

        // try to create the persistent store
        do {
            let pscOptions : [AnyHashable: Any]

            // if passed in nil, use options for automatic migration otherwise used the specified options
            if options == nil {
                pscOptions = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
            } else {
                pscOptions = options
            }
            try persistentStoreCoordinator.addPersistentStore(ofType: storeType, configurationName: nil, at: localURL, options: pscOptions)
        } catch let error as NSError {
            print("Error adding persistent store to coordinator \(error.localizedDescription) \(error.userInfo)")
            mainQueueMOC = nil
            privateMOC = nil
            self.storeURL = nil
            return nil
        }

        // if everything went ok creating persistent store
        self.storeURL = localURL
        // create the private MOC
        privateMOC = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType)
        privateMOC!.persistentStoreCoordinator = persistentStoreCoordinator
        privateMOC!.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy

        // create the main thread/queue MOC that is a child context of the privateMOC
        mainQueueMOC = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType)
        mainQueueMOC!.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        mainQueueMOC!.parent = privateMOC
    }

    /// create a DDRCoreDataDocument with two contexts on a background thread
    ///
    /// - parameter storeURL: NSURL for the SQLite store; pass nil to use an in memory store
    /// - parameter modelURL: NSURL for the CoreData object model (i.e., URL to the .momd file package/directory)
    /// - parameter options: to pass when creating the persistent store coordinator; if pass nil, it uses [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true] for automatic migration; pass an empty dictionary [ : ] if want no options
    /// - parameter completionClosure: a closure (status: DDROkOrError, doc: DDRCoreDataDocument?
    /// :post: calls completionClosure with DDROkOrError.OK and the initialized DDRCoreDataDocument if success. otherwise completionClosure is called with DDROkOrError.ErrorString and doc is nil
    open class func createInBackgroundWithCompletionHandler(_ storeURL: URL?, modelURL: URL, options : [AnyHashable: Any]! = nil, completionClosure: DDRCoreDataDocumentCompletionClosure? = nil) {
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async(execute: { () -> Void in
            let doc = DDRCoreDataDocument(storeURL: storeURL, modelURL: modelURL, options: options)
            let status : DDRCoreDataSaveOrError
            if doc == nil {
                status = DDRCoreDataSaveOrError.errorString("Could not create DDRCoreDataDocument")
            }
            else {
                status = DDRCoreDataSaveOrError.saveOkHadChanges(false)
            }
            DispatchQueue.main.sync(execute: { () -> Void in
                completionClosure?(status, doc)
            })
        })
    }

    /// save the main and private contexts to the persistent store
    ///
    /// - parameter wait: true if want to wait for save to persistent store to complete; false if want to return as soon as main context saves to private context
    ///
    /// - returns: DDROkOrError.OkSaveHadChanges if save succeeds or DDROkOrError.Error otherwise
    open func saveContextAndWait(_ wait: Bool) -> DDRCoreDataSaveOrError {
        if mainQueueMOC == nil {
            return DDRCoreDataSaveOrError.errorString("no NSManagedObjectContext")
        }

        var error: NSError!

        var success = true
        // if mainQueueMOC has changes, save changes up to its parent context
        if mainQueueMOC.hasChanges {
            mainQueueMOC.performAndWait {
                do {
                    try self.mainQueueMOC.save()
                } catch let localError as NSError {
                    success = false
                    error = localError
                    print("error saving mainQueueMOC: \(error.localizedDescription)")
                } catch {
                    success = false
                    print("unknown error saving mainQueueMOC")
                    fatalError()
                }
            }
        }

        guard success == true else {
            return DDRCoreDataSaveOrError.error(error)
        }

        // closure for saving private context
        let saveClosure : () -> () = {
            do {
                try self.privateMOC.save()
            } catch let localError as NSError {
                error = localError
                success = false
            } catch {
                success = false
                print("unknown error saving privateMOC")
                fatalError()
            }
        }

        var hasChanges = false
        // save changes from privateMOC to persistent store
        if success {
            privateMOC.performAndWait() {
                hasChanges = self.privateMOC.hasChanges
            }
            if hasChanges {
                if wait {
                    privateMOC.performAndWait(saveClosure)
                }
                else {
                    privateMOC.perform(saveClosure)
                }
            }
        }

        if success {
            return DDRCoreDataSaveOrError.saveOkHadChanges(hasChanges)
        } else {
            return DDRCoreDataSaveOrError.error(error)

        }
    }

    #if os(iOS)
    /// save task on iOS so it runs even if app is quit
    public func saveContextWithBackgroundTask() {
        let backgroundTaskID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler {}
        saveContextAndWait(true)
        UIApplication.sharedApplication().endBackgroundTask(backgroundTaskID)
    }
    #endif

    /// creates a new child NSManagedObjectContext of the main thread/queue context
    ///
    /// param: concurrencyType specifies the NSManagedObjectContextConcurrencyType for the created context
    ///
    /// - returns: the created NSManagedObjectContext
    open func newChildOfMainObjectContextWithConcurrencyType(_ concurrencyType : NSManagedObjectContextConcurrencyType = NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType) -> NSManagedObjectContext {
        let moc = NSManagedObjectContext(concurrencyType: concurrencyType)
        moc.parent = mainQueueMOC
        return moc
    }
}

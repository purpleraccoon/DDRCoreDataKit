//
//  DDRManagedObject.swift
//  DDRCoreDataKit
//
//  Created by David Reed on 6/19/15.
//  Copyright © 2015 David Reed. All rights reserved.
//

import CoreData


/// DDRManagedObject protocol with default implementation of methods for creating and fetching instances of a NSManagedObject subclass
/// #Note
/// here is what the sample subclass would look like:
/// ```@objc(Person)
/// public class Person: NSManagedObject, DDRManagedObject {
///
///    public static func entityName() -> String {
///        return "Person"
///    }
///
///    override init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext!) {
///        super.init(entity: entity, insertIntoManagedObjectContext: context)
///    }
///
///    public required convenience init(managedObjectContext: NSManagedObjectContext!) {
///        let entity = self.dynamicType.entity(managedObjectContext)
///        self.init(entity: entity, insertIntoManagedObjectContext: managedObjectContext)
///    }
///
///}
public protocol DDRManagedObject {

    /// name of the NSManagedObject subclass for this entity; no default implementation is provided
    static func entityName() -> String

    /// NSEntityDescription for the NSManagedObject subclass for this entity
    static func entity(_ managedObjectContext: NSManagedObjectContext!) -> NSEntityDescription!

    /// NSFetchRequest for the NSManagedObject subclass for this entity
    static func fetchRequest() -> NSFetchRequest<NSFetchRequestResult>

    /// allInstancesInManagedObjectContext get objects of this entity that match predicate and sorted by sort descriptors
    /// - parameter moc: the NSManagedObjectContext to use
    /// - parameter predicate: the NSPredicate to limit which objects are returned
    /// - parameter sortedBy: array of NSSortDescriptor to use to sort the returned array
    /// - returns: array of instances that match pedicate sorted by sortDescriptors
    static func instancesInManagedObjectContext(_ moc: NSManagedObjectContext, withPredicate predicate: NSPredicate?, sortedBy sortDescriptors : [NSSortDescriptor]?, catchError: Bool) throws -> [AnyObject]

    /// get objects of this entity that match predicate
    ///
    /// - parameter moc: the NSManagedObjectContext to use
    /// - parameter predicate: [NSManagedObject] match predicate
    /// - returns: array of [NSManagedObject]
    static func instancesInManagedObjectContext(_ moc: NSManagedObjectContext, withPredicate predicate: NSPredicate?, catchError: Bool) throws -> [AnyObject]

    /// get objects of this entity sorted by specified sort descriptors
    ///
    /// - parameter moc: the NSManagedObjectContext to use
    /// - parameter predicate: [NSManagedObject] match predicate
    /// - returns: array of [NSManagedObject]
    static func allInstancesInManagedObjectContext(_ moc: NSManagedObjectContext, sortedBy sortDescriptors: [NSSortDescriptor], catchError: Bool) throws -> [AnyObject]

    /// get all objects of this entity
    ///
    /// - parameter moc the NSManagedObjectContext to use
    /// - returns: array of [NSManagedObject]
    static func allInstancesInManagedObjectContext(_ moc : NSManagedObjectContext, catchError: Bool) throws -> [AnyObject]!

    /// an NSManagedObject for the same object using the specifed managedObjectContext (or nil if non-temporary objectID)
    ///
    /// - precondition: this NSManagedObject has a non-temporary objectID (otherwise returns nil)
    /// - parameter managedObjectContext: the managedObjectContext to get the duplicate object on
    /// - returns: an NSManagedObject for the same object using the specifed managedObjectContext (or nil if non-temporary objectID)
    func sameManagedObjectUsingManagedObjectContext(managedObjectContext otherMoc: NSManagedObjectContext) -> NSManagedObject?

    // need these so the fault implementation of the following method compiles:
    // sameManagedObjectUsingManagedObjectContext(managedObjectContext otherMoc: NSManagedObjectContext) -> NSManagedObject?
    // since DDRManagedObject will be a protocol for NSManagedObject subclasses, these methods will automatically be provided
    var managedObjectContext: NSManagedObjectContext? { get }
    var objectID: NSManagedObjectID { get }

    static func deleteObjectAndProcessPendingChanges(_ obj: NSManagedObject)
}

//----------------------------------------------------------------------
// MARK: default implementation of protocol methods

/// provide default implementation of DDRManagedObject protocol methods
public extension DDRManagedObject {

    public static func entity(_ managedObjectContext: NSManagedObjectContext!) -> NSEntityDescription! {
        return NSEntityDescription.entity(forEntityName: entityName(), in: managedObjectContext);
    }

    public static func fetchRequest() -> NSFetchRequest<NSFetchRequestResult> {
        return NSFetchRequest(entityName: entityName())
    }

    public static func instancesInManagedObjectContext(_ moc: NSManagedObjectContext, withPredicate predicate: NSPredicate?, sortedBy sortDescriptors : [NSSortDescriptor]?, catchError: Bool = true) throws -> [AnyObject] {

        // create a new fetch request using instance method
        let request = fetchRequest()

        // set fetch request predicte if passed in
        if let pred = predicate {
            request.predicate = pred
        }

        // set fetch request sort descriptors if passed in
        if let sorters = sortDescriptors {
            request.sortDescriptors = sorters
        }

        // if parameter indicates we should catch any errors, catch it and print the error
        if catchError {
            // execute request
            do {
                return try moc.fetch(request)
            }
            catch let error as NSError {
                print("Error loading \(request) \(predicate) \(error)")
            }
        }

        // if not catching error, execute here and return the result of the fetch request
        return try moc.fetch(request)
    }

    public static func instancesInManagedObjectContext(_ moc: NSManagedObjectContext, withPredicate predicate: NSPredicate?, catchError: Bool = true) throws -> [AnyObject] {
        return try instancesInManagedObjectContext(moc, withPredicate: predicate, sortedBy: nil, catchError: catchError)
    }

    public static func allInstancesInManagedObjectContext(_ moc: NSManagedObjectContext, sortedBy sortDescriptors: [NSSortDescriptor], catchError: Bool = true) throws -> [AnyObject] {
        return try instancesInManagedObjectContext(moc, withPredicate: nil, sortedBy: sortDescriptors, catchError: catchError)
    }

    public static func allInstancesInManagedObjectContext(_ moc : NSManagedObjectContext, catchError: Bool = true) throws -> [AnyObject]! {
        return try instancesInManagedObjectContext(moc, withPredicate: nil, sortedBy: nil, catchError: catchError)
    }

    public func sameManagedObjectUsingManagedObjectContext(managedObjectContext otherMoc: NSManagedObjectContext) -> NSManagedObject? {
        if (self.managedObjectContext!.isEqual(otherMoc)) {
            #if DEBUG
                print("cannot use same managedObjectContext or will deadlock so return self")
            #endif
            return nil
        }

        let objectID = self.objectID
        if objectID.isTemporaryID {
            print("cannot use objectID that is temporaryID; must save context first")
            return nil
        }
        var otherObject: NSManagedObject? = nil
        otherMoc.performAndWait {
            var error: NSError? = nil
            do {
                otherObject = try otherMoc.existingObject(with: objectID)
            } catch let error1 as NSError {
                error = error1
                otherObject = nil
            } catch {
                fatalError()
            }
            if error != nil {
                otherObject = nil
                #if DEBUG
                    print("Error: existingObjectWithID \(error!.localizedDescription) \(error!.userInfo!)")
                #endif
            }
        }
        return otherObject
    }

    static func deleteObjectAndProcessPendingChanges(_ obj: NSManagedObject) {
        let moc = obj.managedObjectContext!
        moc.delete(obj)
        moc.processPendingChanges()
    }

}

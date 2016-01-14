
import Foundation

@objc public class AXModel: NSObject {

    private var eventHub = AXEventHub()
    private var observers:[String:AXModelObserver] = [:]
    private var allObjects:[String:AXObject] = [:]
    internal var channelFactory:((String, String) -> (AXChannel))?
    
    public override init() {
        
    }
    
    private convenience init(channelFactory: ((String, String) -> (AXChannel))) {
        self.init()
        self.channelFactory = channelFactory
    }
    
    public static func model() -> AXModel {
        return AXModel()
    }
    
    public subscript(key: String) -> AnyObject? {
        get {
            return observers[key]?.get()
        }
    }
    
    public func watch(name: String) {
        watch(name, collection: nil, expand: nil, order: nil, filter: nil)
    }
    
    public func watch(name: String, expand: Int) {
        watch(name, collection: nil, expand: expand, order: nil, filter: nil)
    }
    
    public func watch(name: String, filter: String) {
        watch(name, collection: nil, expand: nil, order: nil, filter: filter)
    }
    
    public func watch(name: String, order: String) {
        watch(name, collection: nil, expand: nil, order: order, filter: nil)
    }
    
    public func watch(name: String, collection: String?, expand: Int?, order: String?, filter: String?) {
        let observer = AXModelArrayObserver(model: self, name: name, collection: collection, expand: expand, order: order, filter: filter)
        observers[name] = observer
        observer.load()
        observer.connect()
    }
    
    public func on(type: String, handler: (AXModelEvent) -> ()) {
        eventHub.on(type) {
            if let event = $0 as? AXModelEvent {
                handler(event)
            }
        }
    }
    
    private func createChannel(name:String, filter:String) -> AXChannel {
        if let factory = channelFactory {
            return factory(name, filter)
        }
        return AXChannel(name, filter: filter)
    }
    
    private func notify(event: String) {
        eventHub.dispatch(AXModelEvent(type: event))
    }
    
    private func update(object: AXObject, depth: Int = 0) {
        normalize(object, depth: depth)
        observers.forEach() {
            $1.sort()
        }
        notify("change")
    }
    
    private func normalize(object: AXObject, depth: Int = 0) -> AXObject {
        var normalized = object
        if let id = object.objectID {
            if allObjects[id] == nil {
                normalized = object
                allObjects[id] = normalized
            } else {
                normalized = allObjects[id]!
                normalized.importValues(object)
            }
        }
        if depth >= 0 {
            object.allProperties.keys.forEach() { key in
                if let property = object.object(key) {
                    normalized[key] = self.normalize(property, depth: depth - 1)
                } else if let property = object.objects(key) {
                    normalized[key] = property.map() {
                        self.normalize($0, depth: depth - 1)
                    }
                }
            }
        }
        return normalized
    }
    
}

public class AXModelEvent: AXEvent {
    
}

private protocol AXModelObserver {
    func load()
    func connect()
    func sort()
    func get() -> AnyObject
}

private class AXModelArrayObserver: AXModelObserver {
    
    private var model: AXModel
    private let name: String
    private let collection: String
    private let order: String
    private let filter: String
    private let expand: Int
    private var objects: [AXObject] = []
    private var connectedRelations: [String:Bool] = [:]
    private var expandedObjects: [String:Int] = [:]
    
    init(model:AXModel, name: String, collection: String? = nil, expand: Int? = nil, order: String? = nil, filter: String? = nil) {
        self.model = model
        self.name = name
        self.collection = collection ?? name
        self.order = order ?? "-created"
        self.filter = filter ?? ""
        self.expand = expand ?? 0
    }
    
    private func set(objects: [AXObject]) {
        self.objects = objects.map {
            let x = model.normalize($0, depth: self.expand)
            self.registerRelations(x, depth: self.expand)
            return x
        }
        sort()
        model.notify("change")
    }
    
    private func add(object: AXObject) {
        objects.append(model.normalize(object))
        sort()
        model.notify("change")
    }
    
    private func update(object: AXObject) {
        let depth = expandedObjects[object.objectID ?? ""] ?? 0
        
        func _update() {
            model.update(object, depth: depth)
            registerRelations(object, depth: depth)
        }
        
        if depth > 0 {
            object.expand(depth) { _ in _update() }
        } else {
            _update()
        }
    }
    
    private func remove(object: AXObject) {
        if let index = objects.indexOf({ $0.objectID == object.objectID }) {
            objects.removeAtIndex(index)
        }
        sort()
        model.notify("change")
    }
    
    private func sort() {
        var property = order
        var direction = 1
        if order.characters.first == Character("-") {
            property = order.substringFromIndex(order.startIndex.advancedBy(1))
            direction = -1
        }
        
        switch property {
            case "created": property = "sysCreated"
            case "updated": property = "sysUpdated"
            default: break
        }
        
        if direction < 0 {
            self.objects.sortInPlace() {
                let v0 = $0.string(property) ?? ""
                let v1 = $1.string(property) ?? ""
                return v0 > v1
            }
        } else if direction > 0 {
            self.objects.sortInPlace() {
                let v0 = $0.string(property) ?? ""
                let v1 = $1.string(property) ?? ""
                return v0 < v1
            }
        }
    }
    
    func get() -> AnyObject {
        return objects
    }
    
    func load() {
        var options: [String:AnyObject] = [:]
        if expand > 0 {
            options["expand"] = expand
        }
        if filter != "" {
            AXObject.find(collection, queryString: filter, options: options, completion: handleLoadCompleted)
        } else {
            AXObject.findAll(collection, options: options, completion: handleLoadCompleted)
        }
    }
    
    func handleLoadCompleted(objects:[AXObject]?, error:NSError?) {
        if let objects = objects {
            self.set(objects)
        }
    }
    
    func connect() {
        let channel = model.createChannel("objects/\(collection)", filter: filter)
        channel.on("object.created") {
            if let object = $0.object {
                self.add(object)
            }
        }
        channel.on("object.updated") {
            if let object = $0.object {
                self.update(object)
            }
        }
        channel.on("object.deleted") {
            if let object = $0.object {
                self.remove(object)
            }
        }
    }
    
    func connectRelation(collection: String) {
        if !(connectedRelations[collection] ?? false) {
            connectedRelations[collection] = true
            let channel = model.createChannel("objects/\(collection)", filter: "")
            channel.on("object.updated") {
                if let object = $0.object {
                    self.update(object)
                }
            }
        }
    }
    
    func registerRelations(object: AXObject, depth: Int) {
        if let id = object.objectID {
            expandedObjects[id] = depth
        }
        if depth > 0 {
            object.relatedObjects.forEach() {
                self.connectRelation($0.collectionName)
                registerRelations($0, depth: depth-1)
            }
        }
    }
    
}

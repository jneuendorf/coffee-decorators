# node.js
if typeof global is "object" and global?.global is global
    root = global
    exports = module.exports
# browser
else
    root = window
    exports = window


wrap_in_named_function = (name, func) ->
    return eval("(function " + name + "(){return func.apply(this, arguments);})")




defineDecorator = (name, func) ->
    if root[name]?
        throw new Error("Can't define decorator because `root` already has a property with name '#{name}'.")
    root[name] = (args...) ->
        return func(args...)
    return root[name]


# HELPERS
abstractDecorationHelper = (createErrorMessage) ->
    return (args...) ->
        if args.length is 2
            namespace = args[0]
            cls = args[1]
        else if args.length is 1
            namespace = @
            cls = args[0]

        if typeof(namespace) isnt "object" or typeof(cls) isnt "function"
            throw new Error("Invalid arguments. Expected (namespace, class) or (class).")

        name = cls.name
        # cls is also the old constructor
        decoratedClass = class Decorated extends cls
            constructor: () ->
                if @constructor is Decorated
                    throw new Error(createErrorMessage.call(@))
                # call actual constructor
                super

            # Wrapping the function results in the loss of properties -> we use this reference to reattach them
            origClass = Decorated
            # wrap the constructor and give it the `name`
            Decorated = wrap_in_named_function(name, Decorated)
            # reattach __super__ and all other class attributes
            for own key, val of origClass
                Decorated[key] = val

        if namespace?
            namespace[name] = decoratedClass
        return decoratedClass


# DECORATORS

# These decorators only work for classes that are (directly) defined in the `App` namespace.
exports.abstract = defineDecorator "abstract", abstractDecorationHelper () ->
    return "Cannot instantiate abstract class '#{@constructor.name}'."

exports.interface = defineDecorator "interface", abstractDecorationHelper () ->
    return "Cannot instantiate interface '#{@constructor.name}'."







# helper function that converts given 1-elemtent dict (with any key) to {name, method}.
# the given dict is generated by using decorators/annotations like so:
#
# CoffeeScript:
#   @deprecated \
#   method: () ->
#
# JavaScript:
#   <CLASS_NAME>.deprecated({
#       method: function() {}
#   })
getStandardDict = (dict) ->
    result = {}
    for key, val of dict
        name = key
        method = val
    return {name, method}

# helper function to copy all properties in case of decorator chaining
copyMethodProps = (newMethod, oldMethod) ->
    for own key, val of oldMethod when not newMethod[prop]?
        newMethod[key] = val
    return newMethod

methodHelper = (callback) ->
    return (dict) ->
        {name, method} = getStandardDict(dict)
        cls = @
        method = callback(name, method, cls)
        # a potentially new method has been returned -> attach it to the class'es prototype
        if typeof(method) is "function"
            # if isClass(obj)
            cls::[name] = method
        return dict

isClass = (obj) ->
    return obj.prototype?

# Get the class name of `this` - wether it's a class or an instance.
methodString = (obj, methodName) ->
    if isClass(obj)
        return "#{obj.name}::#{methodName}"
    return "#{obj.constructor.name}.#{methodName}"


# DECORATORS FOR INSIDE CLASSES THAT EXTEND THE NATIVE OBJECT
# ALL ANNOTATIONS MUST RETURN THE GIVEN `dict` FOR ANNOTATION CHAINING
class CoffeeDecorators

    _console = console

    @setConsole: (console) ->
        _console = console
        return @

    @getConsole: () ->
        return _console

    @isDeprecated: (method) ->
        return method.__isDeprecated__ is true

    @isFinal: (method) ->
        return method.__isFinal__ is true



    @deprecated: methodHelper (name, method) ->
        wrapper = () ->
            _console.warn("Call of #{methodString(@, name)} is deprecated.")
            return method.apply(@, arguments)
        wrapper.__isDeprecated__ = true
        return copyMethodProps(wrapper, method)

    @override: methodHelper (name, method, cls) ->
        # the prototype chain does not already contain the method
        # => it was not defined in a superclass
        # => method is NOT overridden
        if not cls::[name]
            throw new Error(
                "OVERRIDE: #{cls.name}::#{name} does not override '#{name}' method. "
                + "Check your class inheritance or remove the `@override` decorator!"
            )
        # look for final super methods
        parent = cls
        while (parent = parent.__super__?.constructor)?
            parentMethod = parent::[name]
            if parentMethod? and cls.isFinal(parentMethod)
                throw new Error("Cannot override final method '#{parent.name}::#{name}' (in '#{cls.name}')).")
        return method
    # @override: (dict) ->
    #     {name, method} = getStandardDict(dict)
    #     # the prototype chain does not already contain the method
    #     # => it was not defined in a superclass
    #     # => method is NOT overridden
    #     if not @::[name]
    #         throw new Error("OVERRIDE: #{@name}::#{name} does not override '#{name}' method. Check your class inheritance or remove the `@override` decorator!")
    #     # look for final super methods
    #     parent = @__super__?.constructor
    #     while parent?
    #         parentMethod = parent::[name]
    #         if parentMethod? and parentMethod.isFinal is true
    #             throw new Error("Cannot override final method '#{parent.name}::#{name}' (in '#{@name}')).")
    #         parent = parent.__super__?.constructor
    #     @::[name] = method
    #     return dict

    # this method is different than most because it is used like:
    # @implements(App.ExampleInterface) \
    # method: (a, b) ->
    # Thus it gets the interface as argument and must return a function that gets the `dict`.
    @implements: (interfaceCls) ->
        # this function gets called immediately
        return (dict) =>
            {name, method} = getStandardDict(dict)
            @::[name] = method
            if interfaceCls not in heterarchy.mro(@) or interfaceCls::[name] not instanceof Function
                throw new Error("IMPLEMENTS: #{@name}::#{name} does not implement the '#{interfaceCls.name}' interface.")
            return dict

    @abstract: (dict) ->
        {name, method} = getStandardDict(dict)
        cls = @
        wrapperMethod = () ->
            # this check must contain dynamic lookup because the method could still be replaced by further decorators (-> wrappers)
            if @[name] is cls::[name]
                throw new Error("#{cls.getName()}::#{name} must not be called because it is abstract and must be overridden.")
        @::[name] = copyMethodProps(wrapperMethod, method)
        return dict

    @cachedProperty: (dict) ->
        {name, method} = getStandardDict(dict)
        nullRef = {}
        cache = nullRef
        Object.defineProperty @::, name, {
            get: () ->
                if cache is nullRef
                    cache = method.call(@)
                return cache
            set: (value) ->
                cache = value
                return cache
        }
        return dict

    # Incrementally fills a dictionary of arguments-result pairs.
    # Arguments are compared using the argument's `equals` interface or with `===`.
    # The decorated method has a `clearCache()` method to reset the cache.
    @cached: (dict) ->
        # TODO: fix this: the cache is used across all different instances of a class (which results in really wrong behavior)
        throw new Error("Don't use @cached yet!")
        {name, method} = getStandardDict(dict)
        nullRef = {}
        # maps arguments to return value
        argListsEqual = (args1, args2) ->
            if args1.length isnt args2.length
                return false
            for args1Elem, i in args1
                args2Elem = args2[i]
                if args1Elem.equals?(args2Elem) is false or
                    args2Elem.equals?(args1Elem) is false or
                    args1Elem isnt args2Elem
                        return false
            return true
        createCache = () ->
            return new App.Hash(null, nullRef, argListsEqual)
        cache = createCache()
        wrapperMethod = (args...) ->
            value = cache.get(args)
            if value is nullRef
                value = method.apply(@, args)
                cache.put(args, value)
            return value
        wrapperMethod.clearCache = () ->
            cache = createCache()
        @::[name] = copyMethodProps(wrapperMethod, method)
        return dict

    # only works if an accidental overriding method uses `@override` or calls `super`
    @final: (dict) ->
        {name, method} = getStandardDict(dict)
        cls = @
        wrapperMethod = () ->
            if @[name] isnt cls::[name]
                # `cls::getClassName()` is used insteaf of `cls.getName()` because heterarchy does not correctly support class method inheritance
                throw new Error("Method '#{cls::getClassName()}::#{name}' is final and must not be overridden (in '#{@getClassName()}')")
            return method.apply(@, arguments)
        wrapperMethod.isFinal = true
        @::[name] = copyMethodProps(wrapperMethod, method)
        return dict

exports.CoffeeDecorators = CoffeeDecorators

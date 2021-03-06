# CoffeeDecorators
This library provides functions that can be used
like Python decorators or Java annotations respectively.
I personally found those really helpful during a big refactoring.
In the project we used multiple inheritance.
Therefore, it was really helpful to use the decorators to

- quickly figure out where a method occurs in the MRO,
- explicate intentions (e.g. marking methods as abstract) and
- marking methods as deprecated.

Due to CoffeeScript's syntax a `\` is required if the decorators are defined above the method itself.

```coffee
@decorator \
method: ->
# OR
@decorator method: ->
```

## Decorators

Almost all decorators can be chained in any order.
For a list of exceptions see this [list](#decorator-combinations-that-require-a-certain-order).
For example the two are equal:

```coffee
@classmethod \
@deprecated \
classMethod: ->
    return someThing

@deprecated \
@classmethod \
classMethod: ->
    return someThing
```

### `@classmethod`
Because

```coffee
class A
    @decorator \
    @classMethod: ->
A.classMethod()
```

is invalid CoffeeScript the workaround to use decorators on classmethods
is to use the `@classmethod` decorator (like in Python).
So the example would then look like:

```coffee
class A
    @classmethod \
    @decorator \
    classMethod: ->
A.classMethod()
```

### `@deprecated`
When the method is called a warning will be printed (with `console.warn`).

### `@abstract`
This decorator exists for classes, class methods and (instance) methods.

#### Classes

```coffee
@abstract class Shape
    pass # necessary only if no statements exist within the class
@abstract namespace, class Shape
    pass # necessary only if no statements exist within the class
```

#### (Class) methods
The decorated method must not have a body and must not be called directly (but overridden).

### `@override`
A method with the same name as the decorated method must exist somewhere in the class hierarchy (above the method's class).

### `@final`
The decorated method must not be overridden.
If a method with the same name in a subclass is decorated with `@override` an error is thrown upon class creation.
Otherwise an error will be thrown when the final method is called and `this !== <instance of according class>` meaning the final method has been called from a context of a subclass (or an arbitrary context).

### `@cached`
The return value of the method is cached after the first computation.
The cache is populated for each instance because the function might depend on instance attributes.
If the method does not depend on instance attributes a `@classmethod` should be used.


## Decorator combinations that require a certain order

- `@override @classmethod`

## Examples

### Abstract classes and methods

```coffee
{abstract} = require("../coffee-decorators")

# In case of
# abstract class Shape
#   ...
# the local variable still points to the undecorated class
# so we need to update it.
Shape = abstract class Shape
    @abstract \
    area: ->

# OR use @abstract after attaching it to the global scope
global.abstract = abstract
(() ->
    @abstract \
    class Shape
        @abstract \
        area: ->
).call(global)

class Rectangle extends Shape
    constructor: (@w, @h) ->
    area: ->
        return @w * @h

class Circle extends Shape
    constructor: (@r) ->

expect(-> new Shape).to.throw()
expect(-> new Rectangle).to.not.throw()
expect((new Rectangle(2, 3)).area()).to.equal(6)
expect(-> (new Circle(2)).area()).to.throw()
```

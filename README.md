# HashLink (Embed)

This gem provides a method to embed and call into Haxe code via HashLink. Currently, most primitive types are supported, along with strings, references to objects, and closures/functions. See the table below for all features supported so far.

Providing Ruby objects to Haxe code is currently not supported, though Ruby code can hold references to Haxe objects.

This is currently a work in progress; if you encounter a bug, please file an issue.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hashlink-embed'
```

And then execute:

    $ bundle install

Note you need an embedded build of the hashlink library, build and install the changes from this pull request: https://github.com/HaxeFoundation/hashlink/pull/492

## Usage

See demo.rb for an interactive pry session with the spec binary, or the tests for more usage.

Note that Strings must be present in the compiled hl file. If you encounter errors, use `-dce no` if you don't use strings in your Haxe code.

```ruby
require 'hashlink-embed'
# compile your haxe code with no -main flag if you just want to use it as a library
hx = HashLink::Instance.new(File.read("your.hl", mode: "rb"))
objref = hx.types.my.package.MyClass.new("strings", 1234)
objref.method # => returns objref's or other primitives
my = hx.types.my # save the package root so you can do
my.package.MyClass.staticMethod()
hx.dispose # don't forget to dispose
```

## Haxe Integration
Array types support to_a for simple arrays, and to_h for maps provided the methods are present in the compiled .hl code. Use `-dce no` if necessary to disable dead code elimination in the standard library.

The `methods` method is generally supported

## Development

Current interesting bugs: entry point NPE for ruby with all code (stack offset error?)

There are lots of not-yet-implemented features, most throw NotImplementedError.
Not all tests pass yet.

### Supported features: Base HashLink

| Category | Integration | Implemented? (as/notes) |
| --- | --- | --- |
| Unwrap (Return) | void, null | :heavy_check_mark: (nil) |
| Unwrap (Return) | i32, f32, f64 | :heavy_check_mark: (Ruby Numeric)|
| Unwrap (Return) | bool | :heavy_check_mark: (true/false) |
| Unwrap (Return) | bytes | :heavy_check_mark: (Ruby String)|
| Unwrap (Return) | object (Haxe String) | :heavy_check_mark: (Ruby String)|
| Unwrap (Return) | object (non-String), virtual, abstract | :heavy_check_mark: (proxy)|
| Unwrap (Return) | enum | :heavy_check_mark: (wrapped pointer)|
| Unwrap (Return) | closure | :heavy_check_mark: (function pointer proxy)|
| Unwrap (Return) | others | :x:|
| Wrap (Call) | hl:dyn | :heavy_check_mark:|
| Wrap (Call) | nil | :heavy_check_mark:|
| Wrap (Call) | true,false | :heavy_check_mark:|
| Wrap (Call) | Ruby Float, Ruby Integer | :heavy_check_mark:|
| Wrap (Call) | Ruby Float -> f32 | :x:|
| Wrap (Call) | Ruby String | :heavy_check_mark:|
| Wrap (Call) | others | :x:|
| Read Array | hl:dyn -> Unwrap | :heavy_check_mark:|
| Read Array | non hl:dyn | :x:|
| Write Array (public) | any | :x: (internally supported for GC roots) |
| Read Field | Unwrap | :heavy_check_mark: |
| Write Field | any | :x:|

### Supported features: Haxe Integration

| Category | Integration | Implemented? (as/notes) |
| --- | --- | --- |
| Namespacing | Package Lookup | :heavy_check_mark: |
| Namespacing | Package Interation | :x: |
| Namespacing | Class Lookup | :heavy_check_mark: |
| Namespacing | Class Interation | :x: |
| Namespacing | Static Class Lookup | :heavy_check_mark: (exposed as class methods) |
| Namespacing | Static Class Interation | :x: |
| Calling | Constructor Calls | :heavy_check_mark:|
| Calling | Class Method Calls | :heavy_check_mark:|
| Calling | Class Method Iteration | :heavy_check_mark: |
| Calling | Instance Method Calls | :heavy_check_mark:|
| Calling | Instance Method Iteration | :heavy_check_mark: |
| Fields | Class Fields | :x: (internally supported)|
| Fields | Class Field Iteration | :heavy_check_mark: (via `methods`) |
| Fields | Instance Fields | :heavy_check_mark: (via `field!`)|
| Fields | Instance Field Iteration | :heavy_check_mark: (via `methods`) |
| Ruby Integration | hl:array -> Ruby Array | :heavy_check_mark: (via `#to_a`, see stdlib note below)|
| Ruby Integration | haxe:List, haxe:Array -> Ruby Array | :heavy_check_mark: (via `#to_a`, see stdlib note below)|
| Ruby Integration | haxe:Map -> Ruby Hash | :heavy_check_mark: (via `#to_h`, see stdlib note below)|
| Ruby Integration | hl:closure -> Ruby Proc | :heavy_check_mark: (via `#to_proc`)|
| Ruby Integration | Exceptions | :heavy_check_mark: (wrapped)|
| Ruby Integration | to_s -> toString | :x:|


### Supported features: Internal

| Category | Integration | Implemented? (as/notes) |
| --- | --- | --- |
| GC | HL -> Ruby | :heavy_check_mark: |
| GC | Ruby -> HL | :x: |

See gc-interop.rb for the GC pinning details

### Haxe stdlib note

In order to support Haxe-Ruby interop, the following Haxe classes must be present in the compiled HashLink VM code:

 * String

Additionally, for iterating and converting List & Map Haxe instances into Ruby instances, the Haxe standard library iteration functions must be present in the compiled HashLink VM code. If you encounter issues with `#to_a` or `#to_h`, consider adding iteration to your Haxe code, or adding the compilation flag `-dce no` to disable stdlib dead code elimination when compiling the .hl file.

## License

LGPL v3.0 (or later)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/byteit101/hashlink-embed.

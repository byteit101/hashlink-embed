# HashLink (Embed)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hashlink-embed'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install hashlink-embed

## Usage

See demo.rb for an interactive pry session with the spec binary, or the tests for more usage

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

## Development


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/hashlink-embed.


require_relative 'lib/hashlink-embed/version'

Gem::Specification.new do |spec|
  spec.name          = "hashlink-embed"
  spec.version       = HashLink::VERSION
  spec.authors       = ["Patrick Plenefisch"]
  spec.email         = ["simonpatp@gmail.com"]
  spec.licenses    = ['LGPL-3.0-or-later']
  spec.summary       = %q{Embed HashLink in Ruby}
  spec.description   = %q{A library to enable Ruby to call into Haxe code via the HashLink/JIT VM}
  spec.homepage      = "https://github.com/byteit101/hashlink-embed"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/byteit101/hashlink-embed"
  spec.metadata["changelog_uri"] = "https://github.com/byteit101/hashlink-embed"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `find lib -type f -print0`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end

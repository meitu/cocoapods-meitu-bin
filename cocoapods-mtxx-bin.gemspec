# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cocoapods-mtxx-bin/gem_version.rb'

Gem::Specification.new do |spec|
  spec.name          = 'cocoapods-mtxx-bin'
  spec.version       = CBin::VERSION
  spec.authors       = ['Jensen']
  spec.email         = ['zys2@meitu.com']
  spec.description   = %q{cocoapods-mtxx-bin is a plugin which helps develpers switching pods between source code and binary.}
  spec.summary       = %q{cocoapods-mtxx-bin is a plugin which helps develpers switching pods between source code and binary.}
  spec.homepage      = 'https://github.com/Zhangyanshen/cocoapods-mtxx-bin'
  spec.license       = 'MIT'

  spec.files = Dir["lib/**/*.rb","spec/**/*.rb","lib/**/*.plist"] + %w{README.md LICENSE.txt }
  # spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'parallel', '~> 1.22.0'
  spec.add_dependency 'cocoapods', ['>= 1.10.2', '<= 1.11.2']
  # spec.add_dependency 'cocoapods', '1.10.2'
  spec.add_dependency "cocoapods-generate",'~> 2.0.1'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end

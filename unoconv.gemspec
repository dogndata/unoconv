# Encoding: UTF-8

Gem::Specification.new do |spec|
  spec.name = 'unoconv'
  spec.version = '0.0.6'

  spec.authors = ['Sofus']
  spec.required_ruby_version = '>= 2.3.1'
  spec.description = 'Unoconv document conversion interface for Ruby'
  spec.summary = <<-SUM
    Use Unoconv::Listener to handle converting multiple documents to pdf in
    Libre Office.
  SUM
  spec.files = `git ls-files`.split("\n")
  spec.require_paths = ['lib']
end

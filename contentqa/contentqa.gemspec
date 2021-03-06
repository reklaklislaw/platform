$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "contentqa/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "dpla_contentqa"
  s.version     = Contentqa::VERSION
  s.authors     = ["Jeffrey Licht"]
  s.email       = ["jeff@podconsulting.com"]
  s.homepage    = "http://dp.la"
  s.summary     = "Support QA for content being ingested into the DPLA"
  s.description = "Support QA for content being ingested into the DPLA"

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 3.2.11"
  # s.add_dependency "jquery-rails"

  s.add_dependency "httparty"
  s.add_dependency "twitter-bootstrap-rails"
end

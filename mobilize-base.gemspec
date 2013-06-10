# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "mobilize-base/version"

Gem::Specification.new do |s|
  s.name        = "mobilize-base"
  s.version     = Mobilize::Base::VERSION
  s.authors     = ["Cassio Paes-Leme"]
  s.email       = ["cpaesleme@dena.com"]
  s.homepage    = "http://github.com/ngmoco/mobilize-base"
  s.summary     = %q{Moves datasets and schedules data transfers using MongoDB, Resque and Google Docs}
  s.description = %q{Manage your organization's workflows entirely through Google Docs and irb.
                     Mobilize schedules jobs, queues workers, sends failure notifications, and
                     integrates mobilize-hadoop, -http, -mysql, and -mongodb packages
                     to allow seamless transport of TSV and JSON data between any two endpoints. }

  s.rubyforge_project = "mobilize-base"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'rake'
  s.add_runtime_dependency 'bson','1.8.4'
  s.add_runtime_dependency 'bson_ext','1.8.4'
  s.add_runtime_dependency "mongoid", "~>3.0.0"
  s.add_runtime_dependency 'mongoid-grid_fs'
  s.add_runtime_dependency 'resque', '1.24.0'
  s.add_runtime_dependency 'google_drive','0.3.2'
  s.add_runtime_dependency 'popen4','0.1.2'
  s.add_runtime_dependency 'actionmailer','3.1.1'
end

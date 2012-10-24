require "mobilize-base/version"
require "mobilize-base/extensions/array"
require "mobilize-base/extensions/hash"
require "mobilize-base/extensions/object"
require "mobilize-base/extensions/string"

module Mobilize
  module Base
    def self.env
      begin
        Rails.env
      rescue
        ENV['GEM_ENV'] || "development"
      end
    end
    def self.root
      File.expand_path('../..', __FILE__)
    end
    # Your code goes here...
  end
end
require 'mongo'
require 'mongoid'
Mongoid.load!("#{Mobilize::Base.root}/lib/mobilize-base/mongoid.yml", Mobilize::Base.env)

require 'google_drive'
require 'resque'
require 'popen4'
require "mobilize-base/jobtracker"
require "mobilize-base/models/dataset"
require "mobilize-base/models/requestor"
require "mobilize-base/models/job"
require "mobilize-base/handlers/gdriver"
require "mobilize-base/handlers/mongoer"

#require "mobilize-base/handlers/*"
#require "mobilize-base/models/*"

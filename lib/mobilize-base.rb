require "mobilize-base/version"
require "mobilize-base/extensions/array"
require "mobilize-base/extensions/hash"
require "mobilize-base/extensions/object"
require "mobilize-base/extensions/string"
#this is the base of the mobilize object, any methods that should be
#made available application-wide go over here
#these also define base variables for Rails
module Mobilize
  module Base
    def Base.root
      begin
        Rails.root
      rescue
        File.expand_path('../..', __FILE__)
      end
    end
    def Base.conf(conf_name)
      conf_dir = begin
                   "#{Rails.root}/config/"
                 rescue
                   "#{Base.root}/conf/"
                 end
      YAML.load_file("#{conf_dir}#{conf_name}.yml")
    end
    def Base.env
      begin
        Rails.env
      rescue
        ENV['MOBILIZE_ENV'] || "development"
      end
    end
  end
end
require 'mongo'
require 'mongoid'
mongoid_conf_path = "#{Mobilize::Base.root}/conf/mongoid.yml"
Mongoid.load!(mongoid_conf_path, Mobilize::Base.env)
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

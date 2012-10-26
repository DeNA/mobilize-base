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
    def Base.queues
      ['mobilize_jobtracker','mobilize_worker','mobilize_requestor']
    end
    def Base.config(config_name)
      config_dir = begin
                     "#{Rails.root}/config/"
                   rescue
                     "#{Base.root}/config/"
                   end
      yaml_path = "#{config_dir}#{config_name}.yml"
      if File.exists?(yaml_path)
        return YAML.load_file(yaml_path)
      else
        raise "Could not find #{config_name}.yml in #{config_dir}"
      end
    end
    def Base.env
      begin
        Rails.env
      rescue
        #use MOBILIZE_ENV to manually set your environment when you start your app
        ENV['MOBILIZE_ENV'] || "development"
      end
    end
    def Base.log_path(log_name)
      log_dir = begin
                  "#{Rails.root}/log/"
                rescue
                  "#{Base.root}/log/"
                end
      log_path = "#{log_dir}#{log_name}.log"
      if File.exists?(log_dir)
        return log_path
      else
        raise "Could not find #{log_dir} folder for logs"
      end
    end
  end
end
mongoid_config_path = "#{Mobilize::Base.root}/config/mongoid.yml"
if File.exists?(mongoid_config_path)
  require 'mongo'
  require 'mongoid'
  Mongoid.load!(mongoid_config_path, Mobilize::Base.env)
  require "mobilize-base/models/dataset"
  require "mobilize-base/models/requestor"
  require "mobilize-base/models/job"
end
require 'google_drive'
require 'resque'
require "mobilize-base/extensions/resque"
require 'popen4'
require "mobilize-base/jobtracker"
require "mobilize-base/handlers/gdriver"
require "mobilize-base/handlers/mongoer"

#require "mobilize-base/handlers/*"
#require "mobilize-base/models/*"
